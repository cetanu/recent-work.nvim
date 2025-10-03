local M = {}

--- Validate and set project directory
--- @param directory string Directory path
--- @param config_module table Configuration module
local function validate_and_set_directory(directory, config_module)
	if directory and vim.fn.isdirectory(directory) == 1 then
		config_module.set("project_directory", directory)
		vim.notify(string.format("Project directory set to: %s", directory))
	else
		vim.notify("Invalid directory: " .. (directory or "nil"), vim.log.levels.ERROR)
	end
end

--- Validate and set days back
--- @param days number Number of days
--- @param config_module table Configuration module
local function validate_and_set_days(days, config_module)
	if days and type(days) == "number" and days > 0 then
		config_module.set("days_back", days)
		vim.notify(string.format("Days back set to: %d", days))
	else
		vim.notify("Invalid days value. Must be a positive number.", vim.log.levels.ERROR)
	end
end

--- Handle author filter setting with validation
--- @param author string Author filter value
--- @param config_module table Configuration module
--- @param git_module table Git operations module
local function handle_author_filter(author, config_module, git_module)
	if not author or author == "" then
		config_module.set("filter_author", nil)
		vim.notify("Author filter cleared - showing all authors")
		return
	end

	if author == "me" then
		local current_user = git_module.get_current_user()
		if not current_user.name and not current_user.email then
			vim.notify(
				"Could not determine current Git user. Please set git config user.name and user.email",
				vim.log.levels.ERROR
			)
			return
		end
		config_module.set("filter_author", "me")
	else
		config_module.set("filter_author", author)
	end
end

--- Register all user commands
--- @param plugin_module table Main plugin module
--- @param config_module table Configuration module
--- @param git_module table Git operations module
function M.register_commands(plugin_module, config_module, git_module)
	vim.api.nvim_create_user_command("RecentWork", function()
		plugin_module.show_results()
	end, {
		desc = "Show recent work across Git projects",
	})

	vim.api.nvim_create_user_command("RecentWorkSetDir", function(opts)
		local directory = opts.args
		if directory == "" then
			directory = vim.fn.input("Enter directory to scan: ", vim.fn.getcwd(), "dir")
		end
		validate_and_set_directory(directory, config_module)
	end, {
		nargs = "?",
		complete = "dir",
		desc = "Set the directory to scan for Git projects",
	})

	vim.api.nvim_create_user_command("RecentWorkSetDays", function(opts)
		local days = tonumber(opts.args)
		if not days then
			days = tonumber(vim.fn.input("Enter number of days to look back: ", "7"))
		end
		validate_and_set_days(days, config_module)
	end, {
		nargs = "?",
		desc = "Set the number of days to look back for commits",
	})

	vim.api.nvim_create_user_command("RecentWorkSetAuthor", function(opts)
		local author = opts.args
		if author == "" then
			local config = config_module.get()
			local current_filter = config.filter_author or ""
			author = vim.fn.input("Enter author to filter by ('me' for current user, empty to clear): ", current_filter)
		end
		handle_author_filter(author, config_module, git_module)
	end, {
		nargs = "?",
		desc = 'Set author filter (use "me" for current git user, empty to clear)',
	})

	vim.api.nvim_create_user_command("RecentWorkClearAuthor", function()
		config_module.set("filter_author", nil)
		vim.notify("Author filter cleared - showing all authors")
	end, {
		desc = "Clear author filter to show all authors",
	})

	vim.api.nvim_create_user_command("RecentWorkMyCommits", function()
		handle_author_filter("me", config_module, git_module)
		plugin_module.show_results()
	end, {
		desc = "Show only commits by current git user",
	})

	vim.api.nvim_create_user_command("RecentWorkSetMaxCommits", function(opts)
		local max_commits = tonumber(opts.args)
		if max_commits and max_commits > 0 then
			config_module.set("max_commits_per_repo", max_commits)
			vim.notify(string.format("Max commits per repository set to: %d", max_commits))
		else
			local config = config_module.get()
			print("Current max commits per repository: " .. config.max_commits_per_repo)
			print("Usage: :RecentWorkSetMaxCommits 200")
			print("Lower values = faster git operations, higher values = more complete history")
		end
	end, {
		nargs = "?",
		desc = "Set maximum commits per repository",
	})
end

return M
