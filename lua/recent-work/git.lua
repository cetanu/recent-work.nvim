local M = {}

local cached_user = nil

--- Get git config via the OS
--- @param key string The config to display
--- @return string Config the git configuration line
local function gitconfig(key)
	local handle = io.popen("git config " .. key .. " 2>/dev/null")
	if not handle then
		return ""
	end
	local result = handle:read("*a") or ""
	handle:close()
	return result:gsub("\n", "")
end

--- Get current Git user information
--- @return table User information with name and email fields
function M.get_current_user()
	if cached_user then
		return cached_user
	end

	local user_name = gitconfig("--global user.name")
	local user_email = gitconfig("--global user.email")

	if user_name == "" or user_email == "" then
		user_name = gitconfig("user.name")
		user_email = gitconfig("user.email")
	end

	cached_user = {
		name = user_name ~= "" and user_name or nil,
		email = user_email ~= "" and user_email or nil,
	}

	return cached_user
end

--- Clear the cached user information (useful for testing or when git config changes)
function M.clear_user_cache()
	cached_user = nil
end

--- Check if an author matches the given filter
--- @param author string Author name/email from commit
--- @param filter table Resolved filter with type and values
--- @return boolean Whether the author matches the filter
function M.matches_author_filter(author, filter)
	if not filter or filter.type == "all" then
		return true -- Show all authors
	end

	if filter.type == "me" then
		if filter.name and author:find(filter.name, 1, true) then
			return true
		end
		if filter.email and author:find(filter.email, 1, true) then
			return true
		end
		return false
	elseif filter.type == "specific" then
		return author:lower():find(filter.value:lower(), 1, true) ~= nil
	end

	return false
end

--- Resolve author filter to avoid unsafe calls in libuv context
--- @param filter string|nil Filter criteria ("me", specific name/email, or nil for all)
--- @return table Resolved filter information
function M.resolve_author_filter(filter)
	if not filter then
		return { type = "all" }
	end

	if filter == "me" then
		local user = M.get_current_user()
		return {
			type = "me",
			name = user.name,
			email = user.email,
		}
	else
		return {
			type = "specific",
			value = filter,
		}
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

	-- Safe trim function to replace vim.trim
	local function safe_trim(str)
		if not str then
			return ""
		end
		return str:match("^%s*(.-)%s*$") or ""
	end

	-- Clean up fields
	hash = safe_trim(hash)
	author = safe_trim(author)
	date = safe_trim(date)
	message = safe_trim(message)
	refs = refs and safe_trim(refs) or ""

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
--- @param callback function|nil Optional callback for async execution
--- @return table|nil Results with commits for each repository
function M.execute_parallel_commands(repo_batch, days_back, author_filter, max_commits, callback)
	local since_date = os.date("%Y-%m-%d", os.time() - (days_back * 24 * 60 * 60))
	local total_repos = #repo_batch
	local completed_repos = 0
	local batch_results = {}
	local is_async = callback ~= nil

	-- Resolve author upfront to avoid calls in uv context
	local filter = M.resolve_author_filter(author_filter)

	if total_repos == 0 then
		if is_async then
			vim.schedule(function()
				callback({})
			end)
			return
		else
			return {}
		end
	end

	local repo_states = {}

	local function complete_repo(repo_index, success, commits)
		local state = repo_states[repo_index]
		if state.completed then
			return
		end
		state.completed = true
		completed_repos = completed_repos + 1

		-- Cleanup resources
		if state.stdout_pipe and not vim.uv.is_closing(state.stdout_pipe) then
			vim.uv.close(state.stdout_pipe)
		end
		if state.stderr_pipe and not vim.uv.is_closing(state.stderr_pipe) then
			vim.uv.close(state.stderr_pipe)
		end
		if state.handle and not vim.uv.is_closing(state.handle) then
			vim.uv.close(state.handle)
		end

		if success and commits and #commits > 0 then
			table.insert(batch_results, {
				path = repo_batch[repo_index],
				commits = commits,
			})
		end

		if completed_repos == total_repos then
			if is_async then
				vim.schedule(function()
					callback(batch_results)
				end)
			end
		end
	end

	-- Process each repository
	for i, repo in ipairs(repo_batch) do
		local state = {
			repo = repo,
			stdout_data = {},
			stderr_data = {},
			stdout_pipe = vim.uv.new_pipe(),
			stderr_pipe = vim.uv.new_pipe(),
			handle = nil,
			completed = false,
		}
		repo_states[i] = state

		local git_args = {
			"log",
			"--all",
			"--since=" .. since_date,
			"--max-count=" .. max_commits,
			"--pretty=format:%h|%an|%ad|%s|%D",
			"--date=short",
		}

		state.handle, _ = vim.uv.spawn("git", {
			args = git_args,
			cwd = repo,
			stdio = { nil, state.stdout_pipe, state.stderr_pipe },
		}, function(code, _)
			if code == 0 then
				local commits = {}
				local seen_hashes = {}
				local full_output = table.concat(state.stdout_data, "")

				for line in full_output:gmatch("[^\r\n]+") do
					local commit = M.parse_commit_line(line)
					if commit and not seen_hashes[commit.hash] and M.matches_author_filter(commit.author, filter) then
						seen_hashes[commit.hash] = true
						table.insert(commits, commit)
					end
				end

				-- Sort commits by date (newest first)
				table.sort(commits, function(a, b)
					return a.date > b.date
				end)

				complete_repo(i, true, commits)
			else
				-- Git command failed
				complete_repo(i, false, nil)
			end
		end)

		if state.handle then
			vim.uv.read_start(state.stdout_pipe, function(err, data)
				if err then
					complete_repo(i, false, nil)
				elseif data then
					table.insert(state.stdout_data, data)
				else
					vim.uv.close(state.stdout_pipe)
				end
			end)

			vim.uv.read_start(state.stderr_pipe, function(err, data)
				if err then
					complete_repo(i, false, nil)
				elseif data then
					table.insert(state.stderr_data, data)
				else
					vim.uv.close(state.stderr_pipe)
				end
			end)
		else
			-- Failed to spawn process
			complete_repo(i, false, nil)
		end
	end

	if not is_async then
		local start_time = vim.uv.hrtime()
		local timeout = 30000000000 -- 30 seconds

		while completed_repos < total_repos do
			vim.uv.run("nowait")
			-- Use uv.sleep instead of vim.wait for safety in fast event context
			vim.uv.sleep(10)

			-- Check for timeout
			if vim.uv.hrtime() - start_time > timeout then
				-- Cleanup processes
				for _, state in ipairs(repo_states) do
					if not state.completed then
						if state.handle and not vim.uv.is_closing(state.handle) then
							vim.uv.process_kill(state.handle, "sigterm")
							vim.uv.close(state.handle)
						end
						if state.stdout_pipe and not vim.uv.is_closing(state.stdout_pipe) then
							vim.uv.close(state.stdout_pipe)
						end
						if state.stderr_pipe and not vim.uv.is_closing(state.stderr_pipe) then
							vim.uv.close(state.stderr_pipe)
						end
					end
				end
				break
			end
		end

		return batch_results
	end
end

return M
