local M = {}

local uv = vim.loop or vim.uv
local pid = vim.fn.getpid()
local treesitter = require("nvim-claude-context.treesitter")

local debounce_timer = nil
local config = nil

M.set_config = function(cfg)
  config = cfg
end

local read_context = function()
  local path = vim.fn.expand(config.output_path)
  local file = io.open(path, "r")
  if not file then
    return { instances = {} }
  end

  local content = file:read("*a")
  file:close()

  if content == "" then
    return { instances = {} }
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return { instances = {} }
  end

  return decoded
end

local get_buffers = function()
  local buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      local buftype = vim.bo[buf].buftype
      if name ~= "" and buftype == "" then
        table.insert(buffers, name)
      end
    end
  end
  return buffers
end

local get_active_file = function()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local buftype = vim.bo[buf].buftype

  if name == "" or buftype ~= "" then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local result = {
    file = name,
    line = cursor[1],
    col = cursor[2] + 1,
  }

  if config.include.treesitter then
    local ts_context = treesitter.get_context()
    if ts_context then
      result.treesitter = ts_context
    end
  end

  return result
end

local build_instance_data = function()
  local data = {
    pid = pid,
    timestamp = os.time(),
  }

  if config.include.cwd then
    data.cwd = vim.fn.getcwd()
  end

  if config.include.active_file then
    data.active = get_active_file()
  end

  if config.include.cursor and data.active then
    -- cursor info is already in active
  end

  if config.include.buffers then
    data.buffers = get_buffers()
  end

  return data
end

local update_instance = function(context, instance_data)
  local found = false
  for i, inst in ipairs(context.instances) do
    if inst.pid == pid then
      context.instances[i] = instance_data
      found = true
      break
    end
  end

  if not found then
    table.insert(context.instances, instance_data)
  end

  return context
end

local write_context = function(context)
  local path = vim.fn.expand(config.output_path)
  local dir = vim.fn.fnamemodify(path, ":h")

  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  local temp_path = path .. ".tmp." .. pid
  local encoded = vim.json.encode(context)

  local file = io.open(temp_path, "w")
  if not file then
    vim.notify("[nvim-claude-context] Failed to write context file", vim.log.levels.ERROR)
    return false
  end

  file:write(encoded)
  file:close()

  local ok = uv.fs_rename(temp_path, path)
  if not ok then
    os.remove(temp_path)
    vim.notify("[nvim-claude-context] Failed to rename temp file", vim.log.levels.ERROR)
    return false
  end

  return true
end

M.write = function()
  if not config or not config.enabled then
    return
  end

  local context = read_context()
  local instance_data = build_instance_data()
  context = update_instance(context, instance_data)
  write_context(context)
end

M.write_debounced = function()
  if not config or not config.enabled then
    return
  end

  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
    debounce_timer = nil
  end

  debounce_timer = uv.new_timer()
  debounce_timer:start(config.debounce_ms, 0, vim.schedule_wrap(function()
    if debounce_timer then
      debounce_timer:stop()
      debounce_timer:close()
      debounce_timer = nil
    end
    M.write()
  end))
end

M.remove_instance = function()
  if not config then
    return
  end

  local context = read_context()
  local new_instances = {}

  for _, inst in ipairs(context.instances) do
    if inst.pid ~= pid then
      table.insert(new_instances, inst)
    end
  end

  context.instances = new_instances

  if #new_instances == 0 then
    local path = vim.fn.expand(config.output_path)
    os.remove(path)
  else
    write_context(context)
  end
end

return M
