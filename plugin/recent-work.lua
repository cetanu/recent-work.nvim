-- Recent Work Plugin Commands
-- This file defines the user commands for the Recent Work plugin

if vim.g.loaded_recent_work then
	return
end
vim.g.loaded_recent_work = 1

local plugin = require("recent-work")

-- Main command to show results
vim.api.nvim_create_user_command("RecentWork", function()
	plugin.show_results()
end, {
	desc = "Show recent work across Git projects",
})

-- Command to set scan directory
vim.api.nvim_create_user_command("RecentWorkSetDir", function(opts)
	local directory = opts.args
	if directory == "" then
		directory = vim.fn.input("Enter directory to scan: ", vim.fn.getcwd(), "dir")
	end
	plugin.set_project_directory(directory)
end, {
	nargs = "?",
	complete = "dir",
	desc = "Set the directory to scan for Git projects",
})

-- Command to set days back
vim.api.nvim_create_user_command("RecentWorkSetDays", function(opts)
	local days = tonumber(opts.args)
	if not days then
		days = tonumber(vim.fn.input("Enter number of days to look back: ", "7"))
	end
	plugin.set_days_back(days)
end, {
	nargs = "?",
	desc = "Set the number of days to look back for commits",
})

-- Command to show current configuration
vim.api.nvim_create_user_command("RecentWorkConfig", function()
	local config = plugin.config
	print("Recent Work Configuration:")
	print(string.format("  Project Directory: %s", config.project_directory))
	print(string.format("  Days Back: %d", config.days_back))
	print(string.format("  Max Depth: %d", config.max_depth))
	print(string.format("  Author Filter: %s", plugin.get_author_filter_info()))
	print("  Ignore Patterns: " .. table.concat(config.ignore_patterns, ", "))
end, {
	desc = "Show current Recent Work configuration",
})

-- Command to set author filter
vim.api.nvim_create_user_command("RecentWorkSetAuthor", function(opts)
	local author = opts.args
	if author == "" then
		local current_filter = plugin.config.filter_author or ""
		author = vim.fn.input("Enter author to filter by ('me' for current user, empty to clear): ", current_filter)
	end
	plugin.set_author_filter(author)
end, {
	nargs = "?",
	desc = 'Set author filter (use "me" for current git user, empty to clear)',
})

-- Command to clear author filter
vim.api.nvim_create_user_command("RecentWorkClearAuthor", function()
	plugin.clear_author_filter()
end, {
	desc = "Clear author filter to show all authors",
})

-- Command to filter by current user only
vim.api.nvim_create_user_command("RecentWorkMyCommits", function()
	plugin.set_author_filter("me")
	plugin.show_results()
end, {
	desc = "Show only commits by current git user",
})

