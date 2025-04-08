local M = {}

local job = require("plenary.job")
local curl = require("plenary.curl")

local fs = require("nvim-devdocs.fs")
local log = require("nvim-devdocs.log")
local list = require("nvim-devdocs.list")
local state = require("nvim-devdocs.state")
local build = require("nvim-devdocs.build")
local config = require("nvim-devdocs.config")
local keymaps = require("nvim-devdocs.keymaps")

local devdocs_site_url = "https://devdocs.io"
local devdocs_cdn_url = "https://documents.devdocs.io"

M.fetch = function()
  log.info("Fetching DevDocs registry...")

  curl.get(devdocs_site_url .. "/docs.json", {
    headers = {
      ["User-agent"] = "chrome", -- fake user agent, see #25
    },
    callback = function(response)
      if not DATA_DIR:exists() then
        log.debug("Docs directory not found, creating a new directory")
        DATA_DIR:mkdir()
      end
      fs.write_registry(response.body)
      log.info("DevDocs registry has been written to the disk")
    end,
    on_error = function(error) log.error("Error when fetching registry, exit code: " .. error.exit) end,
  })
end

---@param entry RegistryEntry
---@param is_update? boolean
M.install = function(entry, is_update)
  if not REGISTRY_PATH:exists() then
    log.error("DevDocs registry not found, please run :DevdocsFetch")
  end

  local slug = entry.slug
  local installed = list.get_installed_alias()
  local is_installed = vim.tbl_contains(installed, slug)

  if not is_update and is_installed then
    log.debug("Documentation for " .. slug .. " is already installed")
  else
    local ui = vim.api.nvim_list_uis()

    if ui[1] and entry.db_size > 10000000 then
      log.debug(string.format("%s docs is too large (%s)", slug, entry.db_size))

      local input = vim.fn.input({
        prompt = "Building large docs can freeze neovim, continue? y/n ",
      })

      if input ~= "y" then return end
    end

    local callback = function(index)
      local doc_url = string.format("%s/%s/db.json?%s", devdocs_cdn_url, entry.slug, entry.mtime)

      log.info("Downloading " .. slug .. " documentation...")
      curl.get(doc_url, {
        callback = vim.schedule_wrap(function(response)
          local docs = vim.fn.json_decode(response.body)
          build.build_docs(entry, index, docs)
        end),
        on_error = function(error)
          log.error("(" .. slug .. ") Error during download, exit code: " .. error.exit)
        end,
      })
    end

    local index_url = string.format("%s/%s/index.json?%s", devdocs_cdn_url, entry.slug, entry.mtime)

    log.info("Fetching " .. slug .. " documentation entries...")
    curl.get(index_url, {
      callback = vim.schedule_wrap(function(response)
        local index = vim.fn.json_decode(response.body)
        callback(index)
      end),
      on_error = function(error)
        log.error("(" .. slug .. ") Error during download, exit code: " .. error.exit)
      end,
    })
  end
end

---@param slugs string[]
M.install_args = function(slugs)
  local registry = list.get_registry(true)

  if not registry then
    log.error("DevDocs registry not found, please run :DevdocsFetch")
    return
  end

  for _, slug in ipairs(slugs) do
    local registry_entry = vim.tbl_get(registry, slug)
    if not registry_entry then
      log.error("No documentation available for " .. slug .. " (slug not found in registry)")
    else
      if registry_entry.installed then
        if not registry_entry.has_update then
          log.warn(slug .. ": documentation is already installed and up to date")
        else
          log.info(slug .. ": Updating")
          M.install(registry_entry, true)
        end
      else
        log.info(slug .. ": Installing")
        M.install(registry_entry, false)
      end
    end
  end
end

---@param alias string
M.uninstall = function(alias)
  local installed = list.get_installed_alias()

  if not vim.tbl_contains(installed, alias) then
    log.warn(alias .. " documentation is not installed")
  else
    local index = fs.read_index()
    local lockfile = fs.read_lockfile()

    if not index or not lockfile then return end

    index[alias] = nil
    lockfile[alias] = nil

    fs.write_index(index)
    fs.write_lockfile(lockfile)
    fs.remove_docs(alias)

    log.info(alias .. " documentation has been uninstalled")
  end
end

---@param entry DocEntry
---@return string[]
M.read_entry = function(entry)
  local splited_path = vim.split(entry.path, ",")
  local file = splited_path[1]
  local file_path = DOCS_DIR:joinpath(entry.alias, file .. ".md")
  local content = file_path:read()
  local pattern = splited_path[2]
  local next_pattern = nil

  if entry.next_path ~= nil then next_pattern = vim.split(entry.next_path, ",")[2] end

  local lines = vim.split(content, "\n")
  local filtered_lines = M.filter_doc(lines, pattern, next_pattern)

  return filtered_lines
end

---@param entry DocEntry
---@param callback function
M.read_entry_async = function(entry, callback)
  local splited_path = vim.split(entry.path, ",")
  local file = splited_path[1]
  local file_path = DOCS_DIR:joinpath(entry.alias, file .. ".md")

  file_path:_read_async(vim.schedule_wrap(function(content)
    local pattern = splited_path[2]
    local next_pattern = nil

    if entry.next_path ~= nil then next_pattern = vim.split(entry.next_path, ",")[2] end

    local lines = vim.split(content, "\n")
    local filtered_lines = M.filter_doc(lines, pattern, next_pattern)

    callback(filtered_lines)
  end))
end

---if we have a pattern to search for, only consider lines after the pattern
---@param lines string[]
---@param pattern? string
---@param next_pattern? string
---@return string[]
M.filter_doc = function(lines, pattern, next_pattern)
  if not pattern then return lines end

  -- https://stackoverflow.com/a/34953646/516188
  local function create_pattern(text) return text:gsub("([^%w])", "%%%1") end

  local filtered_lines = {}
  local found = false
  local pattern_lines = vim.split(pattern, "\n")
  local search_pattern = create_pattern(pattern_lines[1]) -- only search the first line
  local next_search_pattern = nil

  if next_pattern then
    local next_pattern_lines = vim.split(next_pattern, "\n")
    next_search_pattern = create_pattern(next_pattern_lines[1]) -- only search the first line
  end

  for _, line in ipairs(lines) do
    if found and next_search_pattern then
      if line:match(next_search_pattern) then break end
    end
    if line:match(search_pattern) then found = true end
    if found then table.insert(filtered_lines, line) end
  end

  if not found then return lines end

  return filtered_lines
end

---@param bufnr number
---@param is_picker? boolean
M.render_cmd = function(bufnr, is_picker)
  vim.bo[bufnr].ft = config.options.previewer_cmd

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local chan = vim.api.nvim_open_term(bufnr, {})
  local args = is_picker and config.options.picker_cmd_args or config.options.cmd_args
  ---@diagnostic disable-next-line: missing-fields
  local previewer = job:new({
    command = config.options.previewer_cmd,
    args = args,
    on_stdout = vim.schedule_wrap(function(_, data)
      if not data then return end
      local output_lines = vim.split(data, "\n", {})
      for _, line in ipairs(output_lines) do
        pcall(function() vim.api.nvim_chan_send(chan, line .. "\r\n") end)
      end
    end),
    writer = lines,
  })

  previewer:start()
end

---@param entry DocEntry
---@param bufnr number
---@param mode string
M.open = function(entry, bufnr, mode)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_name(bufnr, "[DevDocs: " .. entry.name .. "]")

  if mode == "float" then
    local win = nil
    local last_win = state.get("last_win")
    local float_opts = config.get_float_options()

    if last_win and vim.api.nvim_win_is_valid(last_win) then
      win = last_win
      vim.api.nvim_win_set_buf(win, bufnr)
    else
      win = vim.api.nvim_open_win(bufnr, true, float_opts)
      state.set("last_win", win)
    end

    vim.wo[win].wrap = config.options.wrap
    vim.wo[win].linebreak = config.options.wrap
    vim.wo[win].nu = false
    vim.wo[win].relativenumber = false
    vim.wo[win].conceallevel = 3
  elseif mode == "replace" then
    -- TODO: this currently not in use
    vim.api.nvim_set_current_buf(bufnr)
  else
    -- TODO: add split configuration to plugin settings
    local last_win = state.get("last_win")

    if last_win and vim.api.nvim_win_is_valid(last_win) then
      vim.api.nvim_win_set_buf(last_win, bufnr)
    else
      local winnr = vim.api.nvim_open_win(bufnr, true, { split = "right", win = 0 })
      state.set("last_win", winnr)
    end
  end

  local ignore = vim.tbl_contains(config.options.cmd_ignore, entry.alias)

  if config.options.previewer_cmd and not ignore then
    M.render_cmd(bufnr)
  else
    vim.bo[bufnr].ft = "markdown"
  end

  vim.bo[bufnr].keywordprg = ":DevdocsKeywordprg"

  state.set("last_buf", bufnr)
  keymaps.set_keymaps(bufnr, entry)
  config.options.after_open(bufnr)
end

---@param keyword string
M.keywordprg = function(keyword)
  local alias = state.get("current_doc")
  local mode = state.get("last_mode")
  local bufnr = vim.api.nvim_create_buf(false, false)
  local entries = list.get_doc_entries({ alias })
  local entry

  local function callback(filtered_lines)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, filtered_lines)
    vim.bo[bufnr].modifiable = false

    M.open(entry, bufnr, mode)
  end

  for _, value in pairs(entries or {}) do
    if value.name == keyword or value.link == keyword then
      entry = value
      M.read_entry_async(entry, callback)
    end
  end

  if not entry then log.error("No documentation found for " .. keyword) end
end

return M
