local M = {}

local default_config = {
	project_directory = vim.fn.getcwd(), -- Default to current working directory
	days_back = 7, -- Look for commits in the last 7 days
	max_depth = 3, -- Maximum directory depth to scan
	filter_author = nil, -- Filter commits by author (nil = show all, "me" = current git user, or specific email/name)
	ignore_patterns = { -- Patterns to ignore when scanning
		"node_modules",
		".git",
		"target",
		"build",
		"dist",
		"__pycache__",
		".venv",
		"venv",
	},
	batch_size_dirs = vim.loop.available_parallelism() or 8, -- Process directories in batches during scanning for better performance
	max_commits_per_repo = 200, -- Limit commits per repository for faster processing
	parallel_git_jobs = vim.loop.available_parallelism() or 5, -- Number of git operations to run in parallel
}

M.config = vim.deepcopy(default_config)

function M.setup(user_config)
	user_config = user_config or {}
	M.config = vim.tbl_deep_extend("force", default_config, user_config)
end

local function find_git_repos_async(directory, max_depth, current_depth)
	return coroutine.create(function()
		current_depth = current_depth or 0
		local git_repos = {}

		if current_depth >= max_depth then
			return git_repos
		end

		-- Quick check if this directory is a git repo
		local git_dir = directory .. "/.git"
		if vim.fn.isdirectory(git_dir) == 1 then
			table.insert(git_repos, directory)
			return git_repos
		end

		-- Get all subdirectories first
		local subdirs = {}
		local handle = vim.loop.fs_scandir(directory)
		if handle then
			while true do
				local name, type = vim.loop.fs_scandir_next(handle)
				if not name then
					break
				end

				if type == "directory" then
					local should_ignore = false
					for _, pattern in ipairs(M.config.ignore_patterns) do
						if name:match(pattern) then
							should_ignore = true
							break
						end
					end

					if not should_ignore then
						table.insert(subdirs, directory .. "/" .. name)
					end
				end
			end
		end

		-- Process subdirectories in batches using coroutines
		local batch_size = M.config.batch_size_dirs
		for i = 1, #subdirs, batch_size do
			local batch_end = math.min(i + batch_size - 1, #subdirs)
			local batch_coroutines = {}

			-- Create coroutines for current batch
			for j = i, batch_end do
				table.insert(batch_coroutines, {
					dir = subdirs[j],
					coroutine = find_git_repos_async(subdirs[j], max_depth, current_depth + 1),
				})
			end

			-- Process current batch
			for _, batch_item in ipairs(batch_coroutines) do
				local co_success, subrepos = coroutine.resume(batch_item.coroutine)
				if co_success and subrepos then
					for _, repo in ipairs(subrepos) do
						table.insert(git_repos, repo)
					end
				elseif not co_success then
					print("Error scanning directory " .. batch_item.dir .. ": " .. tostring(subrepos))
				end
			end

			-- Yield after each batch to keep Neovim responsive
			if batch_end < #subdirs then
				coroutine.yield()
			end
		end

		return git_repos
	end)
end

-- Legacy synchronous version for fallback
local function find_git_repos(directory, max_depth, current_depth)
	current_depth = current_depth or 0
	local git_repos = {}

	if current_depth >= max_depth then
		return git_repos
	end

	local git_dir = directory .. "/.git"
	if vim.fn.isdirectory(git_dir) == 1 then
		table.insert(git_repos, directory)
		return git_repos
	end

	local handle = vim.loop.fs_scandir(directory)
	if handle then
		while true do
			local name, type = vim.loop.fs_scandir_next(handle)
			if not name then
				break
			end

			if type == "directory" then
				local should_ignore = false
				for _, pattern in ipairs(M.config.ignore_patterns) do
					if name:match(pattern) then
						should_ignore = true
						break
					end
				end

				if not should_ignore then
					local subdir = directory .. "/" .. name
					local subrepos = find_git_repos(subdir, max_depth, current_depth + 1)
					for _, repo in ipairs(subrepos) do
						table.insert(git_repos, repo)
					end
				end
			end
		end
	end

	return git_repos
end

local function get_current_git_user()
	local user_name = vim.fn.system("git config --global user.name"):gsub("\n", "")
	local user_email = vim.fn.system("git config --global user.email"):gsub("\n", "")

	-- try config in current directory
	if user_name == "" or user_email == "" then
		user_name = vim.fn.system("git config user.name"):gsub("\n", "")
		user_email = vim.fn.system("git config user.email"):gsub("\n", "")
	end

	return {
		name = user_name ~= "" and user_name or nil,
		email = user_email ~= "" and user_email or nil,
	}
end

local function matches_author_filter(author, filter)
	if not filter then
		return true -- show all
	end

	if filter == "me" then
		local user = get_current_git_user()
		if user.name and author:find(user.name, 1, true) then
			return true
		end
		if user.email and author:find(user.email, 1, true) then
			return true
		end
		return false
	else
		return author:lower():find(filter:lower(), 1, true) ~= nil
	end
end

-- Simple but effective parallel approach using background processes
local function execute_parallel_git_commands(repo_batch, days_back, author_filter)
	local since_date = os.date("%Y-%m-%d", os.time() - (days_back * 24 * 60 * 60))
	local temp_files = {}
	local commands = {}

	-- Create temporary files and commands for each repo
	for i, repo in ipairs(repo_batch) do
		local temp_file = vim.fn.tempname()
		table.insert(temp_files, temp_file)

		local git_cmd = string.format(
			"cd '%s' && git log --all --since='%s' --max-count=%d --pretty=format:'%%h|%%an|%%ad|%%s|%%D' --date=short > '%s' 2>/dev/null &",
			repo,
			since_date,
			M.config.max_commits_per_repo,
			temp_file
		)
		table.insert(commands, git_cmd)
	end

	-- Execute all commands in parallel
	local full_command = table.concat(commands, " ") .. " wait"
	os.execute(full_command)

	-- Read results from temp files
	local batch_results = {}
	for i, temp_file in ipairs(temp_files) do
		local repo = repo_batch[i]
		local commits = {}
		local seen_hashes = {}

		local file = io.open(temp_file, "r")
		if file then
			for line in file:lines() do
				if line and line ~= "" then
					local hash, author, date, message, refs = line:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|?(.*)")
					if hash and author and date and message then
						hash = vim.trim(hash)
						author = vim.trim(author)
						date = vim.trim(date)
						message = vim.trim(message)
						refs = refs and vim.trim(refs) or ""

						if not seen_hashes[hash] and matches_author_filter(author, author_filter) then
							seen_hashes[hash] = true

							local branch = "main"
							if refs and refs ~= "" then
								branch = refs:match("origin/([^,%)]+)") or refs:match("([^,%)]+)") or "main"
								branch = branch:gsub("^refs/heads/", ""):gsub("^refs/remotes/origin/", "")
							end

							table.insert(commits, {
								hash = hash,
								author = author,
								date = date,
								message = message,
								branch = branch,
							})
						end
					end
				end
			end
			file:close()

			-- Sort commits by date (newest first)
			table.sort(commits, function(a, b)
				return a.date > b.date
			end)

			if #commits > 0 then
				table.insert(batch_results, {
					path = repo,
					commits = commits,
				})
			end
		end

		-- Clean up temp file
		os.remove(temp_file)
	end

	return batch_results
end

function M.scan_projects()
	local scan_coroutine = find_git_repos_async(M.config.project_directory, M.config.max_depth)
	local repos = nil
	local scan_start_time = vim.loop.now()

	while coroutine.status(scan_coroutine) ~= "dead" do
		local success, result = coroutine.resume(scan_coroutine)
		if not success then
			print("Error during directory scanning: " .. tostring(result))
			print("Falling back to synchronous directory scanning...")
			repos = find_git_repos(M.config.project_directory, M.config.max_depth)
			break
		end

		if result then
			repos = result
		end

		-- Show progress during directory scanning
		if coroutine.status(scan_coroutine) ~= "dead" then
			vim.cmd("redraw")
		end
	end

	local scan_duration = (vim.loop.now() - scan_start_time) / 1000

	if not repos then
		print("Failed to scan for repositories")
		return {}
	end

	local results = {}
	local filter_info = ""
	if M.config.filter_author then
		if M.config.filter_author == "me" then
			local current_user = get_current_git_user()
			filter_info = string.format(" (filtered by: %s)", current_user.name or current_user.email or "current user")
		else
			filter_info = string.format(" (filtered by: %s)", M.config.filter_author)
		end
	end

	print(string.format("📁 Found %d Git repositories in %.2fs%s", #repos, scan_duration, filter_info))
	print("🔄 Processing repositories for recent commits in parallel...")

	local git_start_time = vim.loop.now()

	-- Process repositories in truly parallel batches using background processes
	local parallel_jobs = M.config.parallel_git_jobs
	local processed_count = 0

	for i = 1, #repos, parallel_jobs do
		local batch_end = math.min(i + parallel_jobs - 1, #repos)
		local repo_batch = {}

		-- Collect repos for this batch
		for j = i, batch_end do
			table.insert(repo_batch, repos[j])
		end

		-- Execute git commands in parallel for this batch
		local batch_results = execute_parallel_git_commands(repo_batch, M.config.days_back, M.config.filter_author)

		-- Add results to main results
		for _, result in ipairs(batch_results) do
			table.insert(results, result)
		end

		processed_count = processed_count + #repo_batch

		-- Progress update and UI refresh
		if processed_count % 10 == 0 or processed_count == #repos then
			print(string.format("Processed %d/%d repositories...", processed_count, #repos))
			vim.cmd("redraw")
		end
	end

	local git_duration = (vim.loop.now() - git_start_time) / 1000
	local total_duration = scan_duration + git_duration

	print(
		string.format("✅ Completed in %.2fs (scan: %.2fs, git: %.2fs)", total_duration, scan_duration, git_duration)
	)
	return results
end

function M.show_results()
	local results = M.scan_projects()

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = math.floor(vim.o.columns * 0.9),
		height = math.floor(vim.o.lines * 0.8),
		row = math.floor(vim.o.lines * 0.1),
		col = math.floor(vim.o.columns * 0.05),
		border = "rounded",
		title = " Recent Work Results ",
		title_pos = "center",
	})

	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "modifiable", true)

	local lines = {}
	table.insert(lines, string.format("Recent Work - Recent Commits (Last %d days)", M.config.days_back))
	table.insert(lines, string.format("Project Directory: %s", M.config.project_directory))

	if M.config.filter_author then
		if M.config.filter_author == "me" then
			local current_user = get_current_git_user()
			local user_display = current_user.name or current_user.email or "current user"
			table.insert(lines, string.format("Author Filter: %s (me)", user_display))
		else
			table.insert(lines, string.format("Author Filter: %s", M.config.filter_author))
		end
	else
		table.insert(lines, "Author Filter: All authors")
	end

	table.insert(lines, "")
	table.insert(lines, string.rep("=", 80))
	table.insert(lines, "")

	if #results == 0 then
		table.insert(lines, "No Git repositories with recent commits found.")
	else
		for _, result in ipairs(results) do
			table.insert(lines, string.format("📁 %s", result.path))
			table.insert(lines, string.format("   %d recent commits:", #result.commits))
			table.insert(lines, "")

			-- Group commits by branch and author
			local groups = {}
			for _, commit in ipairs(result.commits) do
				local group_key = commit.branch .. "|" .. commit.author
				if not groups[group_key] then
					groups[group_key] = {
						branch = commit.branch,
						author = commit.author,
						commits = {},
					}
				end
				table.insert(groups[group_key].commits, commit)
			end

			local sorted_groups = {}
			for _, group in pairs(groups) do
				table.insert(sorted_groups, group)
			end

			-- Sort by branch, author
			table.sort(sorted_groups, function(a, b)
				if a.branch == b.branch then
					return a.author < b.author
				end
				return a.branch < b.branch
			end)

			-- Display each group
			for _, group in ipairs(sorted_groups) do
				-- header
				table.insert(lines, string.format("   🌿 %s - 👤 %s", group.branch, group.author))

				-- Sort commits (newest first)
				table.sort(group.commits, function(a, b)
					return a.date > b.date
				end)

				for _, commit in ipairs(group.commits) do
					table.insert(lines, string.format("      %s (%s) %s", commit.hash, commit.date, commit.message))
				end

				table.insert(lines, "")
			end

			table.insert(lines, string.rep("-", 60))
			table.insert(lines, "")
		end
	end

	table.insert(lines, "")
	table.insert(lines, "Press 'q' to close this window")

	-- Set content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	-- Set up key mappings for the buffer
	vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })

	-- Set syntax highlighting
	vim.api.nvim_buf_set_option(buf, "filetype", "recentwork")
end

-- Configure project directory
function M.set_project_directory(directory)
	if directory and vim.fn.isdirectory(directory) == 1 then
		M.config.project_directory = directory
		print(string.format("Project directory set to: %s", directory))
	else
		print("Invalid directory: " .. (directory or "nil"))
	end
end

-- Configure days back
function M.set_days_back(days)
	if days and type(days) == "number" and days > 0 then
		M.config.days_back = days
		print(string.format("Days back set to: %d", days))
	else
		print("Invalid days value. Must be a positive number.")
	end
end

-- Configure author filter
function M.set_author_filter(author)
	if not author or author == "" then
		M.config.filter_author = nil
		print("Author filter cleared - showing all authors")
		return
	end

	if author == "me" then
		local current_user = get_current_git_user()
		if not current_user.name and not current_user.email then
			print("Could not determine current Git user. Please set git config user.name and user.email")
			return
		end
		M.config.filter_author = "me"
		local user_display = current_user.name or current_user.email
		print(string.format("Author filter set to: %s (me)", user_display))
	else
		M.config.filter_author = author
		print(string.format("Author filter set to: %s", author))
	end
end

-- Clear author filter
function M.clear_author_filter()
	M.config.filter_author = nil
	print("Author filter cleared - showing all authors")
end

-- Get current author filter info
function M.get_author_filter_info()
	if not M.config.filter_author then
		return "No author filter (showing all authors)"
	elseif M.config.filter_author == "me" then
		local current_user = get_current_git_user()
		local user_display = current_user.name or current_user.email or "current user"
		return string.format("Filtering by: %s (me)", user_display)
	else
		return string.format("Filtering by: %s", M.config.filter_author)
	end
end

-- Configure directory scanning batch size for performance tuning
function M.set_directory_batch_size(dir_batch)
	if dir_batch and dir_batch > 0 then
		M.config.batch_size_dirs = dir_batch
		print(string.format("Directory batch size set to: %d", M.config.batch_size_dirs))
	else
		print("Current directory batch size: " .. M.config.batch_size_dirs)
		print("Usage: M.set_directory_batch_size(8)")
		print("Higher values = faster directory scanning, lower values = more responsive")
	end
end

-- Configure maximum commits per repository
function M.set_max_commits(max_commits)
	if max_commits and max_commits > 0 then
		M.config.max_commits_per_repo = max_commits
		print(string.format("Max commits per repository set to: %d", M.config.max_commits_per_repo))
	else
		print("Current max commits per repository: " .. M.config.max_commits_per_repo)
		print("Usage: M.set_max_commits(200)")
		print("Lower values = faster git operations, higher values = more complete history")
	end
end

-- Configure parallel git jobs
function M.set_parallel_jobs(jobs)
	if jobs and jobs > 0 then
		M.config.parallel_git_jobs = jobs
		print(string.format("Parallel git jobs set to: %d", M.config.parallel_git_jobs))
	else
		print("Current parallel git jobs: " .. M.config.parallel_git_jobs)
		print("Usage: M.set_parallel_jobs(5)")
		print("Higher values = faster processing, but may overwhelm system resources")
	end
end

-- Get performance statistics
function M.get_performance_info()
	return {
		batch_size_dirs = M.config.batch_size_dirs,
		max_commits_per_repo = M.config.max_commits_per_repo,
		parallel_git_jobs = M.config.parallel_git_jobs,
		parallelization = "Parallel git operations + optimized directory scanning + commit limits",
	}
end

return M
