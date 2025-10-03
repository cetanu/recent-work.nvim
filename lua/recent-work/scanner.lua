local M = {}

local uv = vim.uv or vim.loop

local joinpath = vim.fs and vim.fs.joinpath

local function path_join(a, b)
	if joinpath then
		return joinpath(a, b)
	end
	if a:sub(-1) == "/" then
		return a .. b
	end
	return a .. "/" .. b
end

--- Check if a directory should be ignored based on patterns
--- @param name string Directory name
--- @param ignore_patterns string[] List of patterns to ignore
--- @return boolean Whether the directory should be ignored
local function should_ignore_directory(name, ignore_patterns)
	for _, pattern in ipairs(ignore_patterns) do
		if name:match(pattern) then
			return true
		end
	end
	return false
end

--- Scan for Git repositories using a high-performance synchronous strategy
--- @param config table Configuration object
--- @return table List of Git repository paths
function M.scan_repositories(config)
	local max_depth = config.max_depth
	if max_depth <= 0 then
		return {}
	end

	local ignore_patterns = config.ignore_patterns or {}
	local has_ignored = #ignore_patterns > 0
	local stack = { { path = config.project_directory, depth = 0 } }
	local stack_index = 1
	local repositories = {}

	while stack_index <= #stack do
		local current = stack[stack_index]
		stack_index = stack_index + 1

		if current and current.depth < max_depth then
			local git_dir = path_join(current.path, ".git")
			local git_stat = uv.fs_stat(git_dir)
			if git_stat then
				repositories[#repositories + 1] = current.path
			else
				local handle, err = uv.fs_scandir(current.path)
				if handle then
					while true do
						local name, t = uv.fs_scandir_next(handle)
						if not name then
							break
						end

						if
							t == "directory" and (not has_ignored or not should_ignore_directory(name, ignore_patterns))
						then
							stack[#stack + 1] = {
								path = path_join(current.path, name),
								depth = current.depth + 1,
							}
						end
					end
				elseif err then
					vim.notify(string.format("Error scanning directory %s: %s", current.path, err), vim.log.levels.WARN)
				end
			end
		end
	end

	return repositories
end

return M
