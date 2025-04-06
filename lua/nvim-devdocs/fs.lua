local M = {}

---@param registry string
M.write_registry = function(registry) REGISTRY_PATH:write(registry, "w") end

---@param index IndexTable
M.write_index = function(index)
  local encoded = vim.fn.json_encode(index)
  INDEX_PATH:write(encoded, "w")
end

---@param lockfile LockTable
M.write_lockfile = function(lockfile)
  local encoded = vim.fn.json_encode(lockfile)
  LOCK_PATH:write(encoded, "w")
end

---@return RegistryEntry[]?
M.read_registry = function()
  if not REGISTRY_PATH:exists() then return end
  local buf = REGISTRY_PATH:read()
  return vim.fn.json_decode(buf)
end

---@return IndexTable?
M.read_index = function()
  if not INDEX_PATH:exists() then return end
  local buf = INDEX_PATH:read()
  return vim.fn.json_decode(buf)
end

---@return LockTable?
M.read_lockfile = function()
  if not LOCK_PATH:exists() then return end
  local buf = LOCK_PATH:read()
  return vim.fn.json_decode(buf)
end

---@param alias string
M.remove_docs = function(alias)
  local doc_path = DOCS_DIR:joinpath(alias)
  doc_path:rm({ recursive = true })
end

return M
