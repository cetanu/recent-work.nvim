local M = {}

--- Check if a directory should be ignored based on patterns
--- @param name string Directory name
--- @param ignore_patterns table List of patterns to ignore
--- @return boolean Whether the directory should be ignored
local function should_ignore_directory(name, ignore_patterns)
	for _, pattern in ipairs(ignore_patterns) do
		if name:match(pattern) then
			return true
		end
	end
	return false
end

--- Find Git repositories asynchronously using coroutines
--- @param directory string Root directory to scan
--- @param max_depth number Maximum depth to scan
--- @param ignore_patterns table Patterns to ignore
--- @param batch_size number Batch size for processing
--- @param current_depth number|nil Current depth (for recursion)
--- @return thread Coroutine for async execution
function M.find_git_repos_async(directory, max_depth, ignore_patterns, batch_size, current_depth)
	return coroutine.create(function()
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

		local subdirs = {}
		local handle = vim.loop.fs_scandir(directory)
		if handle then
			while true do
				local name, type = vim.loop.fs_scandir_next(handle)
				if not name then
					break
				end

				if type == "directory" and not should_ignore_directory(name, ignore_patterns) then
					table.insert(subdirs, directory .. "/" .. name)
				end
			end
		end

		-- Process subdirectories in batches using coroutines
		for i = 1, #subdirs, batch_size do
			local batch_end = math.min(i + batch_size - 1, #subdirs)
			local batch_coroutines = {}

			-- Create coroutines for current batch
			for j = i, batch_end do
				table.insert(batch_coroutines, {
					dir = subdirs[j],
					coroutine = M.find_git_repos_async(
						subdirs[j],
						max_depth,
						ignore_patterns,
						batch_size,
						current_depth + 1
					),
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
					vim.notify(
						"Error scanning directory " .. batch_item.dir .. ": " .. tostring(subrepos),
						vim.log.levels.WARN
					)
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

--- Synchronous fallback for Git repository discovery
--- @param directory string Root directory to scan
--- @param max_depth number Maximum depth to scan
--- @param ignore_patterns table Patterns to ignore
--- @param current_depth number|nil Current depth (for recursion)
--- @return table List of Git repository paths
function M.find_git_repos_sync(directory, max_depth, ignore_patterns, current_depth)
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

			if type == "directory" and not should_ignore_directory(name, ignore_patterns) then
				local subdir = directory .. "/" .. name
				local subrepos = M.find_git_repos_sync(subdir, max_depth, ignore_patterns, current_depth + 1)
				for _, repo in ipairs(subrepos) do
					table.insert(git_repos, repo)
				end
			end
		end
	end

	return git_repos
end

--- Scan for Git repositories with async support and fallback
--- @param config table Configuration object
--- @return table List of Git repository paths
function M.scan_repositories(config)
	local repos = nil

	local future = M.find_git_repos_async(
		config.project_directory,
		config.max_depth,
		config.ignore_patterns,
		config.batch_size_dirs
	)

	while coroutine.status(future) ~= "dead" do
		local success, result = coroutine.resume(future)
		if not success then
			vim.notify("Error during async directory scanning: " .. tostring(result), vim.log.levels.WARN)
			vim.notify("Falling back to synchronous directory scanning...", vim.log.levels.INFO)
			repos = M.find_git_repos_sync(config.project_directory, config.max_depth, config.ignore_patterns)
			break
		end
		if result then
			repos = result
		end
	end

	if not repos then
		vim.notify("Failed to scan for repositories", vim.log.levels.ERROR)
		return {}
	end

	return repos
end

return M
