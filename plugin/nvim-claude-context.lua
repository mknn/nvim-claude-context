if vim.g.loaded_nvim_claude_context then
  return
end
vim.g.loaded_nvim_claude_context = true

vim.api.nvim_create_user_command("ClaudeContextRefresh", function()
  require("nvim-claude-context").refresh()
end, { desc = "Refresh Claude context file" })

vim.api.nvim_create_user_command("ClaudeContextDisable", function()
  require("nvim-claude-context").disable()
end, { desc = "Disable Claude context updates" })

vim.api.nvim_create_user_command("ClaudeContextEnable", function()
  require("nvim-claude-context").enable()
end, { desc = "Enable Claude context updates" })
