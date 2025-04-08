---Represents an entry in the Devdocs registry
---@see https://devdocs.io/docs.json
---@class RegistryEntry
---@field name string
---@field slug string
---@field type string
---@field version string
---@field release string
---@field mtime number
---@field db_size number
---@field links? table<string, string>
---@field attribution string
---Extra fields
---@field installed boolean
---@field has_update boolean
---@field versions string
---@field all_versions table

---Represents an entry in the index.json file
---NOTE: alias and next_path are filled at runtime
---@see nvim_devdocs_path/index.json
---@class DocEntry
---@field name string
---@field path string
---@field link string
---@field alias? string
---@field next_path? string

---Represents a type in the index.json file
---@class DocType
---@field slug string
---@field name string
---@field count number

---Represents a doc in the index.json file
---@class DocIndex
---@field types DocType[]
---@field entries DocEntry[]

---Represents the index.json file
---@alias IndexTable table<string, DocIndex>

---Represents the docs-lock.json file
---@alias LockTable table<string, RegistryEntry>

---@class TSNode
---@field start function
---@field end_ function
---@field named_child function
---@field parent function
---@field type function
---@field equal function
---@field named_children function
---@field next_named_sibling function

---@class Picker
---@field find function
