local M = {}

---@class meister.Annotation
---@field file string absolute file path
---@field from integer 1-based start line
---@field to integer 1-based end line
---@field text string annotation text

---@class meister.Provider
---@field send fun(annotations: meister.Annotation[], cb?: fun(ok: boolean))

---@type table<string, meister.Provider>
local registry = {}

---@param name string
---@param impl meister.Provider
function M.register(name, impl)
	registry[name] = impl
end

---@Resolve the active provider from config: a registry name, or a table impl.
---@return meister.Provider
function M.get()
	local p = require("meister.config").options.provider
	if type(p) == "table" then
		return p
	end
	local impl = registry[p]
	if not impl then
		error("meister: unknown provider '" .. tostring(p) .. "'")
	end
	return impl
end

M.register("opencode", require("meister.provider.opencode"))

return M
