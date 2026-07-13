local M = {}

---@param msg string
---@param level? integer
function M.notify(msg, level)
	vim.notify("meister: " .. msg, level or vim.log.levels.INFO)
end

return M
