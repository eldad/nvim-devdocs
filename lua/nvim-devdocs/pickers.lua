local M = {}

local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local config = require("telescope.config").values
local entry_display = require("telescope.pickers.entry_display")

local log = require("nvim-devdocs.log")
local list = require("nvim-devdocs.list")
local operations = require("nvim-devdocs.operations")
local transpiler = require("nvim-devdocs.transpiler")
local plugin_state = require("nvim-devdocs.state")
local plugin_config = require("nvim-devdocs.config")
local semver = require("nvim-devdocs.semver")

local metadata_previewer = previewers.new_buffer_previewer({
  title = "Metadata",
  define_preview = function(self, entry)
    local bufnr = self.state.bufnr
    local transpiled = transpiler.to_yaml(entry.value)
    local lines = vim.split(transpiled, "\n")

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].ft = "yaml"
  end,
})

---@param prompt string
---@param entries RegistryEntry[]
---@param on_select function
---@return Picker
local function new_registry_picker(prompt, entries, on_select)
  return pickers.new(plugin_config.options.telescope, {
    prompt_title = "DevDocs " .. prompt,
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        local entry_name = entry.name .. " [" .. entry.slug .. "]"
        local display_name
        if entry.installed then
          if entry.has_update then
            display_name = entry_name .. " <Update Available>"
          else
            display_name = entry_name .. " <Installed>"
          end
        else
          display_name = entry_name
        end
        return {
          value = entry,
          display = display_name,
          ordinal = entry_name,
        }
      end,
    }),
    sorter = config.generic_sorter(plugin_config.options.telescope),
    previewer = metadata_previewer,
    attach_mappings = function()
      actions.select_default:replace(function(prompt_bufnr)
        local selection = action_state.get_selected_entry()

        actions.close(prompt_bufnr)
        on_select(selection.value)
      end)
      return true
    end,
  })
end

local doc_previewer = previewers.new_buffer_previewer({
  title = "Preview",
  --
  -- This is buggy. When true this causes an invalid winoow ID with telescope, when a previous preview had content but current does not.
  -- keep_last_buf = true,
  --
  define_preview = function(self, entry)
    local bufnr = self.state.bufnr

    operations.read_entry_async(entry.value, function(filtered_lines)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, filtered_lines)

      if plugin_config.options.previewer_cmd and plugin_config.options.picker_cmd then
        plugin_state.set("preview_lines", filtered_lines)
        operations.render_cmd(bufnr, true)
      else
        vim.bo[bufnr].ft = "markdown"
      end
    end)
  end,
})

local function open_doc(selection, float)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local lines = plugin_state.get("preview_lines") or operations.read_entry(selection.value)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  plugin_state.set("last_mode", float and "float" or "normal")
  operations.open(selection.value, bufnr, float)
end

M.installation_picker = function()
  local registry = list.get_registry()

  if not registry then
    log.error("Registry is nil")
    return
  end

  local picker = new_registry_picker("Install documentation", registry, function(entry)
    if entry.installed and not entry.has_update then
      log.warn(entry.slug .. ": documentation is already installed and up to date")
    else
      operations.install(entry)
    end
  end)

  picker:find()
end

M.installation_latest_picker = function()
  local registry = list.get_registry()

  if not registry then
    log.error("Registry is nil")
    return
  end

  local filtered_registry = {}
  for _, entry in ipairs(registry) do
    local current = vim.tbl_get(filtered_registry, entry.name)
    if not current then
      entry.versions = { entry.version }
      filtered_registry[entry.name] = entry
    else
      local versions = current.versions
      table.insert(versions, entry.version)
      -- nil version usually means the unified dataset
      if entry.version ~= nil and semver.gt(entry.version, current.version) then
        --
        entry.versions = versions
        filtered_registry[entry.name] = entry
      end
    end
  end

  -- picker uses ipair to iterate, covert to array
  local iregistry = {}
  for _, entry in pairs(filtered_registry) do
    local versions = vim.tbl_filter(
      function(v) return v ~= nil and v ~= entry.version end,
      entry.versions
    )
    entry.versions = table.concat(versions, ", ")
    table.insert(iregistry, entry)
  end

  local picker = new_registry_picker("Install documentation", iregistry, function(entry)
    if entry.installed and not entry.has_update then
      log.warn(entry.slug .. ": documentation is already installed and up to date")
    else
      operations.install(entry)
    end
  end)

  picker:find()
end

M.uninstallation_picker = function()
  local installed = list.get_installed_registry()

  if not installed then
    log.warn("No installed datasets, nothing to uninstall")
    return
  end

  local picker = new_registry_picker(
    "Uninstall documentation",
    installed,
    function(entry) operations.uninstall(entry.slug) end
  )

  picker:find()
end

---@param entries DocEntry[]
---@param float? boolean
---@param opts? table
M.open_picker = function(entries, float, opts)
  opts = opts or {}

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { remaining = true },
      { remaining = true },
    },
  })

  -- keywordprg provides an "escaped" string where space or tabs are converted to '\ '.
  local default_text = opts.default_text
  if default_text then
    default_text = string.gsub(default_text or "", "\\ ", " ")
    default_text = string.gsub(default_text, " +", " ")
  end

  local prompt_title = opts.prompt_title or "DevDocs Search"

  local picker = pickers.new(plugin_config.options.telescope or {}, {
    default_text = default_text,
    prompt_title = prompt_title,
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = function()
            return displayer({
              { string.format("[%s]", entry.alias), "markdownH1" },
              { entry.name, "markdownH2" },
            })
          end,
          ordinal = string.format("[%s] %s", entry.alias, entry.name),
        }
      end,
    }),
    sorter = config.generic_sorter(plugin_config.options.telescope),
    previewer = doc_previewer,
    attach_mappings = function()
      actions.select_default:replace(function(prompt_bufnr)
        actions.close(prompt_bufnr)

        local selection = action_state.get_selected_entry()

        if selection then
          plugin_state.set("current_doc", selection.value.alias)
          open_doc(selection, float)
        end
      end)

      return true
    end,
  })

  picker:find()
end

---@param alias string
---@param float? boolean
M.open_picker_alias = function(alias, float)
  local entries = list.get_doc_entries({ alias })

  if not entries then return end

  if vim.tbl_isempty(entries) then
    log.error(alias .. " documentation is not installed")
  else
    plugin_state.set("current_doc", alias)
    M.open_picker(entries, float, { prompt_title = "DevDocs Search (" .. alias .. ")" })
  end
end

return M
