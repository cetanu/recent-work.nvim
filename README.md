# recent-work.nvim

A neovim plugin to collect your most recent commits, across any local
branch, across all your projects.

Designed to help me keep track of what I need to create pull-requests for!

## Features

- Discovers Git repos
- Shows commits from the last N days
- Filter commits by author
- Configurable depth and ignore patterns

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "cetanu/recent-work.nvim",
  config = function()
    require("recent-work").setup({
      project_directory = vim.fn.expand("~/projects"), -- Directory to scan
      days_back = 7,                                   -- Look back 7 days
      max_depth = 3,                                   -- Maximum scan depth
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "recent-work",
  config = function()
    require("recent-work").setup()
  end
}
```

## Configuration

```lua
require("recent-work").setup({
  project_directory = vim.fn.getcwd(), -- Directory to scan (default: current working directory)
  days_back = 7,                       -- Number of days to look back for commits
  max_depth = 3,                       -- Maximum directory depth to scan
  filter_author = nil,                 -- Filter commits by author (nil = show all, "me" = current git user, or specific email/name)
  ignore_patterns = {                  -- Directory patterns to ignore
    "node_modules",
    ".git",
    "target",
    "build",
    "dist",
    "__pycache__",
    ".venv",
    "venv"
  }
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:RecentWork` | Open the main results window with all recent commits |
| `:RecentWorkSetDir [directory]` | Set the directory to scan (prompts if no argument) |
| `:RecentWorkSetDays [number]` | Set the number of days to look back (prompts if no argument) |
| `:RecentWorkSetAuthor [author]` | Set author filter (use "me" for current user, prompts if no argument) |
| `:RecentWorkClearAuthor` | Clear author filter to show all authors |
| `:RecentWorkMyCommits` | Show only commits by current git user |
| `:RecentWorkConfig` | Show current configuration |

## Usage

`:RecentWork` to see all recent commits

### Setting Custom Directory

```vim
:RecentWorkSetDir ~/my-projects
:RecentWork
```

### Filtering

```vim
" Show a certain time range
:RecentWorkSetDays 14
:RecentWork
```

```vim
" Show only your commits
:RecentWorkMyCommits

" Filter by specific author
:RecentWorkSetAuthor "John Doe"
:RecentWork

" Filter by email
:RecentWorkSetAuthor "john@example.com"
:RecentWork

" Clear author filter to show all commits
:RecentWorkClearAuthor
:RecentWork
```

## Output Format

```
Recent Work - Recent Commits (Last 7 days)
Project Directory: /home/user/projects

================================================================================

📁 /home/user/projects/my-awesome-project
   5 recent commits:

   🔸 a1b2c3d [main] (2023-12-01)
      👤 John Doe
      💬 Fix critical bug in authentication

   🔸 e4f5g6h [feature/new-ui] (2023-11-30)
      👤 Jane Smith
      💬 Add new user interface components

------------------------------------------------------------

📁 /home/user/projects/another-project
   2 recent commits:

   🔸 i7j8k9l [develop] (2023-12-01)
      👤 Bob Johnson
      💬 Update documentation

------------------------------------------------------------

Press 'q' to close this window
```

## API

```lua
local plugin = require('recent-work')

local results = plugin.scan_projects()

-- Minimal statistics
local stats = plugin.quick_scan()

-- Config
plugin.set_project_directory('/path/to/projects')
plugin.set_days_back(14)

-- Display results
plugin.show_results()
```

## Requirements

- neovim 0.7+
- git

## Contributing

Contributions are welcome! 

Please feel free to submit issues and pull requests.

## License

Functional Source License- see LICENSE.md file for details.

## Changelog

### v1.0.0
- Initial release
- Basic Git repository scanning
- Multi-branch commit detection
- Configurable time ranges and scan depth
- Syntax highlighting
- User commands
