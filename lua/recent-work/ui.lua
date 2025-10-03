local M = {}

--- Group commits by branch and author for better display
--- @param commits table List of commits
--- @return table Grouped commits
local function group_commits_by_branch_author(commits)
	local groups = {}

	for _, commit in ipairs(commits) do
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

	-- Convert to sorted array
	local sorted_groups = {}
	for _, group in pairs(groups) do
		table.insert(sorted_groups, group)
	end

	-- Sort by branch, then author
	table.sort(sorted_groups, function(a, b)
		if a.branch == b.branch then
			return a.author < b.author
		end
		return a.branch < b.branch
	end)

	return sorted_groups
end

--- Format author filter information for display
--- @param filter_author string|nil Current author filter
--- @param get_current_user function Function to get current Git user
--- @return string Formatted filter information
local function format_author_filter(filter_author, get_current_user)
	if not filter_author then
		return "All authors"
	elseif filter_author == "me" then
		local current_user = get_current_user()
		local user_display = current_user.name or current_user.email or "current user"
		return string.format("%s (me)", user_display)
	else
		return filter_author
	end
end

--- Generate content lines for the results window
--- @param results table Scan results
--- @param config table Current configuration
--- @param get_current_user function Function to get current Git user
--- @return table List of lines to display
function M.generate_content_lines(results, config, get_current_user)
	local lines = {}

	-- Header information
	table.insert(lines, string.format("Recent Work - Recent Commits (Last %d days)", config.days_back))
	table.insert(lines, string.format("Project Directory: %s", config.project_directory))
	table.insert(
		lines,
		string.format("Author Filter: %s", format_author_filter(config.filter_author, get_current_user))
	)
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

			-- Group and display commits
			local groups = group_commits_by_branch_author(result.commits)
			for _, group in ipairs(groups) do
				-- Branch and author header
				table.insert(lines, string.format("   🌿 %s - 👤 %s", group.branch, group.author))

				-- Sort commits by date (newest first)
				table.sort(group.commits, function(a, b)
					return a.date > b.date
				end)

				-- Add commit lines
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

	return lines
end

--- Create and configure the results window
--- @param lines table Content lines to display
--- @return number, number Buffer and window handles
function M.create_results_window(lines)
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

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	M.setup_window_keymaps(buf)

	vim.api.nvim_buf_set_option(buf, "filetype", "recentwork")
	return buf, win
end

--- Set up key mappings for the results window
--- @param buf number Buffer handle
function M.setup_window_keymaps(buf)
	local opts = { noremap = true, silent = true }
	vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", opts)
	vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", opts)
end

return M
