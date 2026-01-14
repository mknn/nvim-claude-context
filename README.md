# nvim-claude-context

A Neovim plugin that exports your editing context (open buffers, cursor position) to a JSON file for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to read.

## Why?

Claude Code integrates with popular IDEs to see what files you have open. This plugin brings that same functionality to Neovim—Claude can see what you're working on and provide better context-aware assistance.

## Installation

### lazy.nvim

```lua
{
  "mknn/nvim-claude-context",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "mknn/nvim-claude-context",
  config = function()
    require("nvim-claude-context").setup()
  end,
}
```

### vim-plug

```vim
Plug 'mknn/nvim-claude-context'
```

Then in your init.lua:

```lua
require("nvim-claude-context").setup()
```

## Configuration

```lua
require("nvim-claude-context").setup({
  output_path = "~/.claude/nvim-context.json",  -- Where to write the context file
  debounce_ms = 100,                      -- Delay before writing (ms)
  include = {
    cwd = true,          -- Include current working directory
    active_file = true,  -- Include active file path
    cursor = true,       -- Include cursor line/column
    buffers = true,      -- Include list of open buffers
  },
  enabled = true,        -- Enable/disable the plugin
})
```

## Claude Code Setup

Add one of these lines to your `CLAUDE.md` (either global `~/.claude/CLAUDE.md` or project-level):

### Option 1: Emphasized

Best if you have a large CLAUDE.md and want to ensure Claude always checks your editor context.

```
IMPORTANT: Before discussing code, check ~/.claude/nvim-context.json to see what files I have open in nvim.
```

### Option 2: Workflow Section

Best if you organize your CLAUDE.md with headers and sections.

```
# Editor Context
Always check ~/.claude/nvim-context.json at the start of coding tasks to see my open nvim buffers and cursor position.
```

### Option 3: Conditional (Recommended)

Best for most users. Only triggers for code-related questions, less noisy for general conversation.

```
When I ask about code or files, first check ~/.claude/nvim-context.json to see what I'm currently editing in nvim.
```

Claude will then read this file to understand what you're working on.

## JSON Output Format

```json
{
  "instances": [
    {
      "pid": 12345,
      "cwd": "/Users/you/project",
      "active": {
        "file": "/Users/you/project/src/main.ts",
        "line": 42,
        "col": 15
      },
      "buffers": [
        "/Users/you/project/src/main.ts",
        "/Users/you/project/src/utils.ts"
      ],
      "timestamp": 1705234567
    }
  ]
}
```

## Multi-Instance Support

Running multiple Neovim instances? Each instance is tracked by its PID. The JSON file contains an array of all running instances—Claude can see context from all your open editors.

When a Neovim instance exits, it removes itself from the file.

## Commands

- `:ClaudeContextRefresh` - Manually refresh the context file
- `:ClaudeContextDisable` - Temporarily disable context updates
- `:ClaudeContextEnable` - Re-enable context updates

## How It Works

1. The plugin hooks into Neovim events (`BufEnter`, `CursorMoved`, etc.)
2. On each event, it debounces and writes context to a JSON file
3. The write is atomic (temp file + rename) to prevent corruption
4. On Neovim exit, the instance is removed from the file

## License

MIT
