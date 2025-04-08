local config = require("nvim-devdocs.config")
local list = require("nvim-devdocs.list")
local log = require("nvim-devdocs.log")
local pickers = require("nvim-devdocs.pickers")
local state = require("nvim-devdocs.state")

local M = {}

---@param keyword string
M.keywordprg = function(keyword)
  local alias = state.get("current_doc")
  local float = state.get("last_mode") == "float"
  local bufnr = vim.api.nvim_create_buf(false, false)
  local entries = list.get_doc_entries({ alias })
  local entry

  local function callback(filtered_lines)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, filtered_lines)
    vim.bo[bufnr].modifiable = false

    M.open(entry, bufnr, float)
  end

  for _, value in pairs(entries or {}) do
    if value.name == keyword or value.link == keyword then
      entry = value
      M.read_entry_async(entry, callback)
    end
  end

  if not entry then
    if config.options.keywordprg_search_fallback then
      M.open_search(keyword)
    else
      log.error(
        "No documentation found for " .. keyword .. " (searched " .. tonumber(#entries) .. ")"
      )
    end
  end
end

M.open_search = function(keyword, float)
  local installed = list.get_installed_alias()
  local entries = list.get_doc_entries(installed)
  pickers.open_picker(entries or {}, float, { default_text = keyword })
end

return M
