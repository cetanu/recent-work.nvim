local M = {}

local config = require("recent-work.config")
local scanner = require("recent-work.scanner")
local git = require("recent-work.git")
local ui = require("recent-work.ui")
local commands = require("recent-work.commands")

--- Setup the plugin with user configuration
--- @param user_config table|nil User configuration overrides
function M.setup(user_config)
	config.setup(user_config)
	commands.register_commands(M, config, git)
end

--- Get current configuration
--- @return table Current configuration
function M.get_config()
	return config.get()
end

--- Scan for Git repositories and their recent commits
--- @return table List of repositories with their commits
function M.scan_projects()
	local current_config = config.get()

	local repos, _ = scanner.scan_repositories(current_config)
	if #repos == 0 then
		vim.notify("No Git repositories found", vim.log.levels.INFO)
		return {}
	end

	local results = {}
	local batch_size = current_config.parallel_git_jobs

	for i = 1, #repos, batch_size do
		local repo_index = math.min(i + batch_size - 1, #repos)
		local repo_batch = {}

		for j = i, repo_index do
			table.insert(repo_batch, repos[j])
		end

		local git_results = git.execute_parallel_commands(
			repo_batch,
			current_config.days_back,
			current_config.filter_author,
			current_config.max_commits_per_repo
		)
		for _, result in ipairs(git_results) do
			table.insert(results, result)
		end
	end

	return results
end

function M.show_results()
	local results = M.scan_projects()
	local lines = ui.generate_content_lines(results, config.get(), git.get_current_user)
	ui.create_results_window(lines)
end

function M.set_project_directory(directory)
	if directory and vim.fn.isdirectory(directory) == 1 then
		config.set("project_directory", directory)
		vim.notify(string.format("Project directory set to: %s", directory))
	else
		vim.notify("Invalid directory: " .. (directory or "nil"), vim.log.levels.ERROR)
	end
end

function M.set_days_back(days)
	if days and type(days) == "number" and days > 0 then
		config.set("days_back", days)
		vim.notify(string.format("Days back set to: %d", days))
	else
		vim.notify("Invalid days value. Must be a positive number.", vim.log.levels.ERROR)
	end
end

function M.set_author_filter(author)
	if not author or author == "" then
		config.set("filter_author", nil)
		vim.notify("Author filter cleared - showing all authors")
		return
	end

	if author == "me" then
		local current_user = git.get_current_user()
		if not current_user.name and not current_user.email then
			vim.notify(
				"Could not determine current Git user. Please set git config user.name and user.email",
				vim.log.levels.ERROR
			)
			return
		end
		config.set("filter_author", "me")
	else
		config.set("filter_author", author)
	end
end

function M.clear_author_filter()
	config.set("filter_author", nil)
	vim.notify("Author filter cleared - showing all authors")
end

function M.get_author_filter_info()
	local current_config = config.get()
	if not current_config.filter_author then
		return "No author filter (showing all authors)"
	elseif current_config.filter_author == "me" then
		local current_user = git.get_current_user()
		local user_display = current_user.name or current_user.email or "current user"
		return string.format("Filtering by: %s (me)", user_display)
	else
		return string.format("Filtering by: %s", current_config.filter_author)
	end
end

function M.set_directory_batch_size(dir_batch)
	if dir_batch and dir_batch > 0 then
		config.set("batch_size_dirs", dir_batch)
		vim.notify(string.format("Directory batch size set to: %d", dir_batch))
	else
		local current_config = config.get()
		print("Current directory batch size: " .. current_config.batch_size_dirs)
		print("Usage: M.set_directory_batch_size(8)")
		print("Higher values = faster directory scanning, lower values = more responsive")
	end
end

function M.set_max_commits(max_commits)
	if max_commits and max_commits > 0 then
		config.set("max_commits_per_repo", max_commits)
		vim.notify(string.format("Max commits per repository set to: %d", max_commits))
	else
		local current_config = config.get()
		print("Current max commits per repository: " .. current_config.max_commits_per_repo)
		print("Usage: M.set_max_commits(200)")
		print("Lower values = faster git operations, higher values = more complete history")
	end
end

function M.set_parallel_jobs(jobs)
	if jobs and jobs > 0 then
		config.set("parallel_git_jobs", jobs)
		vim.notify(string.format("Parallel git jobs set to: %d", jobs))
	else
		local current_config = config.get()
		print("Current parallel git jobs: " .. current_config.parallel_git_jobs)
		print("Usage: M.set_parallel_jobs(5)")
		print("Higher values = faster processing, but may overwhelm system resources")
	end
end

-- expose config directly
M.config = setmetatable({}, {
	__index = function(_, key)
		return config.get()[key]
	end,
	__newindex = function(_, key, value)
		config.set(key, value)
	end,
})

return M
