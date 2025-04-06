local M = {}

local fs = require("nvim-devdocs.fs")
local log = require("nvim-devdocs.log")

M.get_registry = function()
  local registry = fs.read_registry()

  if not registry then
    log.error("DevDocs registry not found, please run :DevdocsFetch")
    return
  end

  local lockfile = fs.read_lockfile() or {}
  local installed = vim.tbl_keys(lockfile)

  for _, entry in pairs(registry) do
    local is_installed = vim.tbl_contains(installed, entry.slug)
    if is_installed then
      local lockfile_entry = vim.tbl_get(lockfile, entry.slug)
      local has_update = entry.mtime > lockfile_entry.mtime
      entry.has_update = has_update
    end
    entry.installed = is_installed
  end

  return registry
end

---@return string[]
M.get_installed_alias = function()
  local lockfile = fs.read_lockfile() or {}
  local installed = vim.tbl_keys(lockfile)

  return installed
end

---@return string[]
M.get_non_installed_alias = function()
  local results = {}
  local registry = fs.read_registry()
  local installed = M.get_installed_alias()

  if not registry then return {} end

  for _, entry in pairs(registry) do
    if not vim.tbl_contains(installed, entry.slug) then table.insert(results, entry.slug) end
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

M.get_updatable_registry = function()
  local updatable = M.get_updatable()
  local predicate = function(entry) return vim.tbl_contains(updatable, entry.slug) end
  return get_registry_entry(predicate)
end

---@return string[]
M.get_updatable = function()
  local results = {}
  local registry = fs.read_registry()
  local lockfile = fs.read_lockfile()

  if not registry or not lockfile then return {} end

  for alias, lockfile_entry in pairs(lockfile) do
    for _, doc in pairs(registry) do
      if doc.slug == lockfile_entry.slug and doc.mtime > lockfile_entry.mtime then
        table.insert(results, alias)
        break
      end
    end
  end

  return results
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
