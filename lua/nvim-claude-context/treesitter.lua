local M = {}

local function_types = {
  "function_declaration",
  "function_definition",
  "method_definition",
  "method_declaration",
  "constructor_declaration",
  "function_item",
  "arrow_function",
  "lambda",
}

local class_types = {
  "class_declaration",
  "class_definition",
  "struct_declaration",
  "struct_item",
  "interface_declaration",
  "impl_item",
}

local get_name_from_node = function(node, bufnr)
  if node == nil then
    return nil
  end

  -- Try direct name field first (function foo() style)
  local ok, name_node = pcall(function()
    return node:child_by_field_name("name")
  end)
  if ok and name_node then
    return vim.treesitter.get_node_text(name_node, bufnr)
  end

  -- Fallback: find identifier child directly on the node (Java methods, etc.)
  for child in node:iter_children() do
    if child:type() == "identifier" then
      return vim.treesitter.get_node_text(child, bufnr)
    end
  end

  -- Handle anonymous functions assigned to variables
  -- Lua: local foo = function() / foo = function()
  -- JS/TS: const foo = () => {} / const foo = function() {}
  local current = node:parent()
  while current do
    local t = current:type()

    -- Lua: variable_declaration → variable_list has the name
    if t == "variable_declaration" or t == "assignment_statement" then
      local var_list = current:child(0)
      if var_list then
        local first_var = var_list:child(0)
        if first_var then
          return vim.treesitter.get_node_text(first_var, bufnr)
        end
      end
    end

    -- JS/TS: variable_declarator - try name field or first identifier child
    if t == "variable_declarator" then
      local ok2, name = pcall(function()
        return current:child_by_field_name("name")
      end)
      if ok2 and name then
        return vim.treesitter.get_node_text(name, bufnr)
      end
      -- Fallback: find first identifier child
      for child in current:iter_children() do
        if child:type() == "identifier" then
          return vim.treesitter.get_node_text(child, bufnr)
        end
      end
    end

    -- Stop if we've gone too far up
    if t == "program" or t == "chunk" then
      break
    end

    current = current:parent()
  end

  return nil
end

local find_ancestor = function(node, node_types)
  while node do
    if vim.tbl_contains(node_types, node:type()) then
      return node
    end
    node = node:parent()
  end
  return nil
end

M.get_context = function()
  local bufnr = vim.api.nvim_get_current_buf()

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end

  -- Ensure treesitter is started for this buffer
  pcall(vim.treesitter.start, bufnr)

  local node = vim.treesitter.get_node()
  if not node then
    return nil
  end

  local func_node = find_ancestor(node, function_types)
  local class_node = find_ancestor(node, class_types)

  local func_name = get_name_from_node(func_node, bufnr)
  local class_name = get_name_from_node(class_node, bufnr)

  if not func_name and not class_name then
    return nil
  end

  local result = {}
  if func_name then
    result["function"] = func_name
  end
  if class_name then
    result["class"] = class_name
  end

  return result
end

return M
