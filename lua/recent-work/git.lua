-- Git operations for recent-work.nvim
-- Handles Git user detection, commit parsing, and repository scanning

local M = {}

--- Get current Git user information
--- @return table User information with name and email fields
function M.get_current_user()
	local user_name = vim.fn.system("git config --global user.name"):gsub("\n", "")
	local user_email = vim.fn.system("git config --global user.email"):gsub("\n", "")

	-- Try local config if global is empty
	if user_name == "" or user_email == "" then
		user_name = vim.fn.system("git config user.name"):gsub("\n", "")
		user_email = vim.fn.system("git config user.email"):gsub("\n", "")
	end

	return {
		name = user_name ~= "" and user_name or nil,
		email = user_email ~= "" and user_email or nil,
	}
end

--- Check if an author matches the given filter
--- @param author string Author name/email from commit
--- @param filter string|nil Filter criteria ("me", specific name/email, or nil for all)
--- @return boolean Whether the author matches the filter
function M.matches_author_filter(author, filter)
	if not filter then
		return true -- Show all authors
	end

	if filter == "me" then
		local user = M.get_current_user()
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

--- Parse a single Git log line into commit information
--- @param line string Raw Git log line
--- @return table|nil Parsed commit data or nil if parsing failed
function M.parse_commit_line(line)
	if not line or line == "" then
		return nil
	end

	local hash, author, date, message, refs = line:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|?(.*)")
	if not (hash and author and date and message) then
		return nil
	end

	-- Clean up fields
	hash = vim.trim(hash)
	author = vim.trim(author)
	date = vim.trim(date)
	message = vim.trim(message)
	refs = refs and vim.trim(refs) or ""

	-- Extract branch name from refs
	local branch = "main"
	if refs and refs ~= "" then
		branch = refs:match("origin/([^,%)]+)") or refs:match("([^,%)]+)") or "main"
		branch = branch:gsub("^refs/heads/", ""):gsub("^refs/remotes/origin/", "")
	end

	return {
		hash = hash,
		author = author,
		date = date,
		message = message,
		branch = branch,
	}
end

--- Execute Git commands in parallel for a batch of repositories
--- @param repo_batch table List of repository paths
--- @param days_back number Number of days to look back
--- @param author_filter string|nil Author filter
--- @param max_commits number Maximum commits per repository
--- @return table Results with commits for each repository
function M.execute_parallel_commands(repo_batch, days_back, author_filter, max_commits)
	local since_date = os.date("%Y-%m-%d", os.time() - (days_back * 24 * 60 * 60))
	local temp_files = {}
	local commands = {}

	-- Create temporary files and commands for each repository
	for _, repo in ipairs(repo_batch) do
		local temp_file = vim.fn.tempname()
		table.insert(temp_files, temp_file)

		local git_cmd = string.format(
			"cd '%s' && git log --all --since='%s' --max-count=%d --pretty=format:'%%h|%%an|%%ad|%%s|%%D' --date=short > '%s' 2>/dev/null &",
			repo,
			since_date,
			max_commits,
			temp_file
		)
		table.insert(commands, git_cmd)
	end

	-- Execute all commands in parallel
	local full_command = table.concat(commands, " ") .. " wait"
	os.execute(full_command)

	-- Process results from temporary files
	return M.process_batch_results(repo_batch, temp_files, author_filter)
end

--- Process results from temporary files after parallel Git execution
--- @param repo_batch table List of repository paths
--- @param temp_files table List of temporary file paths
--- @param author_filter string|nil Author filter
--- @return table Processed results with commits for each repository
function M.process_batch_results(repo_batch, temp_files, author_filter)
	local batch_results = {}

	for i, temp_file in ipairs(temp_files) do
		local repo = repo_batch[i]
		local commits = {}
		local seen_hashes = {}

		local file = io.open(temp_file, "r")
		if file then
			for line in file:lines() do
				local commit = M.parse_commit_line(line)
				if
					commit
					and not seen_hashes[commit.hash]
					and M.matches_author_filter(commit.author, author_filter)
				then
					seen_hashes[commit.hash] = true
					table.insert(commits, commit)
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

		-- Clean up temporary file
		os.remove(temp_file)
	end

	return batch_results
end

return M
