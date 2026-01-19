local M = {}

local writer = require("nvim-claude-context.writer")

local defaults = {
  output_path = "~/.claude/nvim-context.json",
  debounce_ms = 100,
  mode = "auto", -- "auto" or "manual"
  include = {
    cwd = true,
    active_file = true,
    buffers = true,
    treesitter = true,
  },
  enabled = true,
}

local config = nil
local augroup = nil

local merge_config = function(user_config)
  local merged = vim.tbl_deep_extend("force", {}, defaults, user_config or {})
  return merged
end

local setup_autocmds = function()
  augroup = vim.api.nvim_create_augroup("NvimClaudeContext", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufDelete" }, {
    group = augroup,
    callback = function()
      writer.write_debounced()
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    callback = function()
      writer.write_debounced()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      writer.remove_instance()
    end,
  })
end

M.setup = function(opts)
  config = merge_config(opts)
  writer.set_config(config)
  setup_autocmds()
  writer.write()
end

M.disable = function()
  if config then
    config.enabled = false
  end
end

M.enable = function()
  if config then
    config.enabled = true
    writer.write()
  end
end

M.refresh = function()
  writer.write(true)
end

M.copy_formatted = function()
  writer.copy_formatted()
end

return M
