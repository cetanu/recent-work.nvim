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
}

M.config = vim.deepcopy(default_config)

function M.setup(user_config)
	user_config = user_config or {}
	M.config = vim.tbl_deep_extend("force", default_config, user_config)
end

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

local function get_local_branches(repo_path)
	local cmd = string.format("cd '%s' && git branch --format='%%(refname:short)'", repo_path)
	local handle = io.popen(cmd)
	if not handle then
		print("Failed to list local branches within directory: " .. repo_path)
		return
	end
	local result = handle:read("*all")
	handle:close()

	local branches = {}
	for branch in result:gmatch("[^\r\n]+") do
		if branch and branch ~= "" then
			table.insert(branches, vim.trim(branch))
		end
	end

	return branches
end

local function get_recent_commits_from_branch(repo_path, branch, days_back)
	local since_date = os.date("%Y-%m-%d", os.time() - (days_back * 24 * 60 * 60))
	local cmd = string.format(
		"cd '%s' && git log %s --since='%s' --pretty=format:'%%h|%%an|%%ad|%%s' --date=short",
		repo_path,
		branch,
		since_date
	)

	local handle = io.popen(cmd)
	if not handle then
		print("Failed to get recent commits from branch: " .. branch .. " in project: " .. repo_path)
		return
	end
	local result = handle:read("*all")
	handle:close()

	local commits = {}
	for line in result:gmatch("[^\r\n]+") do
		if line and line ~= "" then
			local hash, author, date, message = line:match("([^|]*)|([^|]*)|([^|]*)|(.*)")
			if hash and author and date and message then
				table.insert(commits, {
					hash = vim.trim(hash),
					author = vim.trim(author),
					date = vim.trim(date),
					message = vim.trim(message),
					branch = branch,
				})
			end
		end
	end

	return commits
end

local function get_all_recent_commits(repo_path, days_back, author_filter)
	local branches = get_local_branches(repo_path)
	local all_commits = {}
	if branches == nil then
		return
	end

	for _, branch in ipairs(branches) do
		local commits = get_recent_commits_from_branch(repo_path, branch, days_back)
		if commits ~= nil then
			for _, commit in ipairs(commits) do
				if matches_author_filter(commit.author, author_filter) then
					table.insert(all_commits, commit)
				end
			end
		end
	end

	-- Sort commits by date (newest first)
	table.sort(all_commits, function(a, b)
		return a.date > b.date
	end)

	local unique_commits = {}
	local seen_hashes = {}
	for _, commit in ipairs(all_commits) do
		if not seen_hashes[commit.hash] then
			seen_hashes[commit.hash] = true
			table.insert(unique_commits, commit)
		end
	end

	return unique_commits
end

function M.scan_projects()
	local repos = find_git_repos(M.config.project_directory, M.config.max_depth)
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

	print(string.format("Found %d Git repositories in %s%s", #repos, M.config.project_directory, filter_info))

	for _, repo in ipairs(repos) do
		local commits = get_all_recent_commits(repo, M.config.days_back, M.config.filter_author)
		if #commits > 0 then
			table.insert(results, {
				path = repo,
				commits = commits,
			})
		end
	end

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

			for _, commit in ipairs(result.commits) do
				table.insert(lines, string.format("   🔸 %s [%s] (%s)", commit.hash, commit.branch, commit.date))
				table.insert(lines, string.format("      👤 %s", commit.author))
				table.insert(lines, string.format("      💬 %s", commit.message))
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

return M

