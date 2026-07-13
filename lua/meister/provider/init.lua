local M = {}

---@class meister.Provider
---@field send fun(text: string)
---@field format_ref fun(path: string, from: integer, to: integer): string?

---@type table<string, meister.Provider>
local registry = {}

---@param name string
---@param impl meister.Provider
function M.register(name, impl)
	registry[name] = impl
end

---Resolve the active provider from config: a registry name, or a table impl.
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
