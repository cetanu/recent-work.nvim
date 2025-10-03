-- Basic setup with default configuration
require("recent-work").setup()

-- Advanced setup with custom configuration
require("recent-work").setup({
	-- Directory to scan for Git repositories
	project_directory = vim.fn.expand("~/projects"),

	-- Number of days to look back for commits
	days_back = 14,

	-- Maximum directory depth to scan
	max_depth = 4,

	-- Performance tuning options
	batch_size_dirs = 8, -- Directory scanning batch size
	max_commits_per_repo = 150, -- Limit commits per repo for faster processing
	parallel_git_jobs = 6, -- Number of parallel Git operations

	-- Additional patterns to ignore when scanning
	ignore_patterns = {
		"node_modules",
		".git",
		"target",
		"build",
		"dist",
		"__pycache__",
		".venv",
		"venv",
		".pytest_cache",
		".mypy_cache",
		"coverage",
		".coverage",
	},
})

-- Key mappings for easy access
vim.keymap.set("n", "<leader>rw", ":RecentWork<CR>", { desc = "Recent Work" })
vim.keymap.set("n", "<leader>rd", ":RecentWorkSetDir<CR>", { desc = "Set Project Directory" })
vim.keymap.set("n", "<leader>rt", ":RecentWorkSetDays<CR>", { desc = "Ignore commits older than X days" })
vim.keymap.set("n", "<leader>rc", ":RecentWorkConfig<CR>", { desc = "Show Config" })

-- Example: Custom command to scan a specific directory quickly
vim.api.nvim_create_user_command("RecentWorkScanDir", function(opts)
	local scanner = require("recent-work")
	local original_dir = scanner.config.project_directory

	-- Temporarily change directory
	scanner.set_project_directory(opts.args)
	scanner.show_results()

	-- Restore original directory
	scanner.set_project_directory(original_dir)
end, {
	nargs = 1,
	complete = "dir",
	desc = "Scan a specific directory for Git projects",
})

-- Example: Function to get recent commits for current working directory
local function scan_current_dir()
	local scanner = require("recent-work")
	local original_dir = scanner.config.project_directory

	scanner.set_project_directory(vim.fn.getcwd())
	scanner.show_results()
	scanner.set_project_directory(original_dir)
end

-- Map it to a key combination
vim.keymap.set("n", "<leader>r.", scan_current_dir, { desc = "Scan current directory for Git projects" })

-- Example: Integration with telescope (if you use telescope.nvim)
-- This creates a custom telescope picker for the Git scan results
--[[
local function telescope_recent_work()
  local scanner = require('recent-work')
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  
  local results = scanner.scan_projects()
  local entries = {}
  
  for _, result in ipairs(results) do
    for _, commit in ipairs(result.commits) do
      table.insert(entries, {
        display = string.format("%s [%s] %s: %s", 
          commit.hash, commit.branch, commit.author, commit.message),
        ordinal = commit.message,
        value = {
          repo = result.path,
          commit = commit
        }
      })
    end
  end
  
  pickers.new({}, {
    prompt_title = 'Recent Git Commits',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          display = entry.display,
          ordinal = entry.ordinal,
          value = entry.value
        }
      end
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        
        -- Navigate to the repository
        vim.cmd('cd ' .. selection.value.repo)
        vim.notify('Changed to: ' .. selection.value.repo)
      end)
      return true
    end,
  }):find()
end

-- Command for telescope integration
vim.api.nvim_create_user_command('RecentWorkTelescope', telescope_recent_work, {
  desc = 'Open Recent Work results in Telescope'
})
--]]
