local M = {}

local uv = vim.loop or vim.uv
local pid = vim.fn.getpid()
local treesitter = require("nvim-claude-context.treesitter")

local debounce_timer = nil
local config = nil

local LOCK_TIMEOUT_MS = 1000
local LOCK_STALE_SEC = 5
local LOCK_RETRY_MS = 10

local get_lock_path = function()
  return vim.fn.expand(config.output_path) .. ".lock"
end

local is_lock_stale = function(lock_path)
  local stat = uv.fs_stat(lock_path)
  if not stat then
    return true
  end
  return (os.time() - stat.mtime.sec) > LOCK_STALE_SEC
end

local acquire_lock = function()
  local lock_path = get_lock_path()
  local start = uv.hrtime()
  local timeout_ns = LOCK_TIMEOUT_MS * 1000000

  while (uv.hrtime() - start) < timeout_ns do
    local fd = uv.fs_open(lock_path, "wx", 438)
    if fd then
      uv.fs_write(fd, tostring(pid))
      uv.fs_close(fd)
      return true
    end

    if is_lock_stale(lock_path) then
      os.remove(lock_path)
    else
      vim.wait(LOCK_RETRY_MS)
    end
  end

  return false
end

local release_lock = function()
  os.remove(get_lock_path())
end

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

local pretty_json
pretty_json = function(data, indent)
  indent = indent or 0
  local spaces = string.rep("  ", indent)
  local inner_spaces = string.rep("  ", indent + 1)

  if type(data) ~= "table" then
    return vim.json.encode(data)
  end

  local is_array = vim.islist(data)
  local parts = {}

  if is_array then
    if #data == 0 then
      return "[]"
    end
    table.insert(parts, "[\n")
    for i, v in ipairs(data) do
      table.insert(parts, inner_spaces .. pretty_json(v, indent + 1))
      if i < #data then
        table.insert(parts, ",")
      end
      table.insert(parts, "\n")
    end
    table.insert(parts, spaces .. "]")
  else
    local keys = vim.tbl_keys(data)
    if #keys == 0 then
      return "{}"
    end
    table.sort(keys)
    table.insert(parts, "{\n")
    for i, k in ipairs(keys) do
      table.insert(parts, inner_spaces .. '"' .. tostring(k) .. '": ' .. pretty_json(data[k], indent + 1))
      if i < #keys then
        table.insert(parts, ",")
      end
      table.insert(parts, "\n")
    end
    table.insert(parts, spaces .. "}")
  end

  return table.concat(parts)
end

local copy_to_clipboard = function(instance_data)
  local encoded = pretty_json(instance_data)
  vim.fn.setreg('+', encoded)
  vim.notify("[nvim-claude-context] Context copied to clipboard", vim.log.levels.INFO)
end

local format_for_ai = function(data)
  local lines = {}
  table.insert(lines, "<neovim-context>")
  table.insert(lines, "The user is sharing their current editor position. Analyze this location:")
  table.insert(lines, "")

  if data.active then
    table.insert(lines, "**File**: `" .. data.active.file .. "`")
    table.insert(lines, "**Position**: Line " .. data.active.line .. ", column " .. data.active.col)

    if data.active.treesitter then
      local ts = data.active.treesitter
      if ts["function"] then
        table.insert(lines, "**Inside**: function `" .. ts["function"] .. "`")
      elseif ts["class"] then
        table.insert(lines, "**Inside**: class `" .. ts["class"] .. "`")
      end
    end
  end

  if data.cwd then
    table.insert(lines, "**Working directory**: `" .. data.cwd .. "`")
  end

  if data.buffers and #data.buffers > 0 then
    local names = {}
    for _, buf in ipairs(data.buffers) do
      table.insert(names, vim.fn.fnamemodify(buf, ":t"))
    end
    table.insert(lines, "**Open buffers**: " .. table.concat(names, ", "))
  end

  table.insert(lines, "")
  table.insert(lines, "Instructions:")
  table.insert(lines, "1. Read the active file at the specified position")
  table.insert(lines, "2. Examine the surrounding code to understand the context")
  table.insert(lines, "3. If inside a function/class, understand its purpose and how this line fits")
  table.insert(lines, "4. Consider the open buffers as potentially related files")
  table.insert(lines, "</neovim-context>")

  return table.concat(lines, "\n")
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

M.write = function(explicit)
  if not config or not config.enabled then
    return
  end

  -- In manual mode, only write on explicit command
  if config.mode == "manual" and not explicit then
    return
  end

  local instance_data = build_instance_data()

  if config.mode == "manual" then
    copy_to_clipboard(instance_data)
  else
    if not acquire_lock() then
      return
    end
    local context = read_context()
    context = update_instance(context, instance_data)
    write_context(context)
    release_lock()
  end
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

  if not acquire_lock() then
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

  release_lock()
end

M.copy_formatted = function()
  local instance_data = build_instance_data()
  local formatted = format_for_ai(instance_data)
  vim.fn.setreg('+', formatted)
  vim.notify("[nvim-claude-context] Formatted context copied to clipboard", vim.log.levels.INFO)
end

return M
