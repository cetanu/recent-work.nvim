local M = {}

-- Default configuration values
M.defaults = {
	project_directory = vim.fn.getcwd(), -- Default to current working directory
	days_back = 7, -- Look for commits in the last 7 days
	max_depth = 3, -- Maximum directory depth to scan
	filter_author = "", -- Filter commits by author (nil = show all, "me" = current git user, or specific email/name)
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
	-- Performance settings
	batch_size_dirs = vim.loop.available_parallelism(),
	max_commits_per_repo = 200,
	parallel_git_jobs = vim.loop.available_parallelism(),
}

-- Current configuration (starts as copy of defaults)
M.current = vim.deepcopy(M.defaults)

--- Setup configuration with user overrides
--- @param user_config table|nil User configuration to merge with defaults
function M.setup(user_config)
	user_config = user_config or {}
	M.current = vim.tbl_deep_extend("force", M.defaults, user_config)
	M.validate()
end

function M.validate()
	if not vim.fn.isdirectory(M.current.project_directory) then
		vim.notify("Warning: Project directory does not exist: " .. M.current.project_directory, vim.log.levels.WARN)
	end

	if M.current.days_back <= 0 then
		vim.notify("Warning: days_back must be positive, using default", vim.log.levels.WARN)
		M.current.days_back = M.defaults.days_back
	end

	if M.current.max_depth <= 0 then
		vim.notify("Warning: max_depth must be positive, using default", vim.log.levels.WARN)
		M.current.max_depth = M.defaults.max_depth
	end
end

--- Get current configuration
--- @return table Current configuration
function M.get()
	return M.current
end

--- Reset configuration to defaults
function M.reset()
	M.current = vim.deepcopy(M.defaults)
end

--- Update a specific configuration value
--- @param key string Configuration key
--- @param value any New value
--- @return boolean success Whether the update was successful
function M.set(key, value)
	if M.defaults[key] == nil then
		vim.notify("Unknown configuration key: " .. key, vim.log.levels.ERROR)
		return false
	end
	M.current[key] = value
	M.validate()
	return true
end

return M
