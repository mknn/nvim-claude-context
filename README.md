# nvim-claude-context

A Neovim plugin that exports your editing context (open buffers, cursor position) to a JSON file for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to read.

## Why?

Claude Code integrates with popular IDEs to see what files you have open. This plugin brings that same functionality to Neovim—Claude can see what you're working on and provide better context-aware assistance.

## Usage

The typical workflow uses two terminals side by side:

```
┌─────────────────────────────────┬─────────────────────────────────┐
│                                 │                                 │
│           Neovim                │         Claude Code             │
│                                 │                                 │
│  You edit code here.            │  You talk to Claude here.       │
│  Cursor position and open       │                                 │
│  buffers are tracked.           │  > refactor this                │
│                                 │  > what's wrong here?           │
│  src/services/auth.ts:42        │  > simplify this function       │
│  ▌                              │  > add error handling           │
│                                 │                                 │
└─────────────────────────────────┴─────────────────────────────────┘
```

Because Claude knows exactly which file and line you're looking at, you can give short, natural commands without specifying file paths or pasting code. Just position your cursor and ask.

**Example commands that just work:**
- "refactor this" — Claude reads your cursor position and refactors the function you're in
- "what does this do?" — explains the code at your cursor
- "add types" — adds TypeScript types to the current function
- "this is slow, why?" — analyzes performance of the code you're looking at

## Installation

Install with your favorite plugin manager, for example lazy.nvim:

```lua
{
  "mknn/nvim-claude-context",
  opts = {},
}
```

All options with defaults:

```lua
{
  "mknn/nvim-claude-context",
  opts = {
    output_path = "~/.claude/nvim-context.json",
    debounce_ms = 100,
    include = {
      cwd = true,
      active_file = true,
      cursor = true,
      buffers = true,
      treesitter = true,  -- include current function/class name
    },
    enabled = true,
  },
}
```

## Claude Code Setup

Add one of these to your `CLAUDE.md` (either global `~/.claude/CLAUDE.md` or project-level):

### Option 1: Strict (Recommended)

Best for ensuring Claude always checks your editor context, especially for ambiguous commands like "simplify this" or "fix this".

```
# FIRST PRIORITY - Nvim Context
CRITICAL: When I give ANY ambiguous command about code (like "simplify this", "fix this", "what's wrong here", "refactor this"), you MUST IMMEDIATELY check ~/.claude/nvim-context.json BEFORE doing anything else. This file tells you exactly what file and line I'm looking at.

DO NOT:
- Guess from branch names
- Explore the codebase looking for context
- Ask clarifying questions

INSTEAD: Read nvim-context.json first. Always.
```

### Option 2: Simple

A shorter version if you prefer minimal CLAUDE.md instructions.

```
IMPORTANT: Before discussing code, check ~/.claude/nvim-context.json to see what files I have open in nvim.
```

### Option 3: Conditional

Only triggers for explicit code-related questions, less assertive.

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
        "col": 15,
        "treesitter": {
          "function": "handleAuth",
          "class": "AuthService"
        }
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

The `treesitter` field is only present when the cursor is inside a recognized function or class and treesitter is available for the buffer.

## Treesitter Context

The `treesitter` option adds function and class names to the context output. This requires [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) with parsers installed.

### Requirements

1. **nvim-treesitter** plugin (use the `master` branch):
```lua
{
  "nvim-treesitter/nvim-treesitter",
  branch = "master",
  build = ":TSUpdate",
}
```

2. **tree-sitter CLI** (for compiling parsers):
```bash
brew install tree-sitter  # macOS
# or see https://github.com/tree-sitter/tree-sitter
```

3. **Language parsers** for your languages:
```vim
:TSInstall lua typescript tsx java python go rust
```

### Tested Languages

| Language | Status |
|----------|--------|
| Lua | ✅ Tested |
| TypeScript/JavaScript | ✅ Tested |
| Java | ✅ Tested |
| Python, Go, Rust, C/C++ | May work (untested) |

Other languages may work since the plugin uses common treesitter node types (`function_declaration`, `method_declaration`, `class_declaration`, etc.). If a language doesn't work, open an issue.

### Graceful Degradation

If treesitter isn't available or the parser isn't installed for a language, the plugin continues working—you just won't see the `treesitter` field in the output

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
