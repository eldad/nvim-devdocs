local M = {}

local fs = require("nvim-devdocs.fs")
local log = require("nvim-devdocs.log")

M.get_registry = function(named)
  local registry = fs.read_registry()

  if not registry then
    log.error("DevDocs registry not found, please run :DevdocsFetch")
    return
  end

  local lockfile = fs.read_lockfile() or {}
  local installed = vim.tbl_keys(lockfile)

  local named_registry = {}

  for _, entry in pairs(registry) do
    local is_installed = vim.tbl_contains(installed, entry.slug)
    if is_installed then
      local lockfile_entry = vim.tbl_get(lockfile, entry.slug)
      local has_update = entry.mtime > lockfile_entry.mtime
      entry.has_update = has_update
    end
    entry.installed = is_installed

    if named then named_registry[entry.slug] = entry end
  end

  if named then
    return named_registry
  else
    return registry
  end
end

---@return string[]
M.get_installed_alias = function()
  local lockfile = fs.read_lockfile() or {}
  local installed = vim.tbl_keys(lockfile)

  return installed
end

---@return string[]
M.get_all_alias = function()
  local results = {}
  local registry = fs.read_registry() or {}
  for _, entry in pairs(registry) do
    table.insert(results, entry.slug)
  end
  return results
end

---@param aliases string[]
---@return DocEntry[] | nil
M.get_doc_entries = function(aliases)
  local entries = {}
  local index = fs.read_index()

  if not index then return end

  for _, alias in pairs(aliases) do
    if index[alias] then
      local current_entries = index[alias].entries

      for idx, doc_entry in ipairs(current_entries) do
        local next_path = nil
        local entries_count = #current_entries

        if idx < entries_count then next_path = current_entries[idx + 1].path end

        local entry = {
          name = doc_entry.name,
          path = doc_entry.path,
          link = doc_entry.link,
          alias = alias,
          next_path = next_path,
        }

        table.insert(entries, entry)
      end
    end
  end

  return entries
end

---@param predicate function
---@return RegistryEntry[]?
local function get_registry_entry(predicate)
  local registry = fs.read_registry()

  if not registry then
    log.error("DevDocs registry not found, please run :DevdocsFetch")
    return
  end

  return vim.tbl_filter(predicate, registry)
end

M.get_installed_registry = function()
  local installed = M.get_installed_alias()
  local predicate = function(entry) return vim.tbl_contains(installed, entry.slug) end
  return get_registry_entry(predicate)
end

---@return string[]
M.get_updatable_registry = function()
  local registry = M.get_registry()

  if not registry then
    log.error("Registry nil")
    return {}
  end

  local predicate = function(entry) return entry.installed and entry.has_update end
  return vim.tbl_filter(predicate, registry)
end

---@param name string
---@return string[]
M.get_doc_variants = function(name)
  local variants = {}
  local entries = fs.read_registry()

  if not entries then return {} end

  for _, entry in pairs(entries) do
    if vim.startswith(entry.slug, name) then table.insert(variants, entry.slug) end
  end

  return variants
end

return M
