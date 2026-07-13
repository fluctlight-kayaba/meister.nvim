local M = {}

---@param text string
function M.send(text)
	require("opencode").prompt(text)
end

---@param path string
---@param from_line integer
---@param to_line integer
---@return string|nil
function M.format_ref(path, from_line, to_line)
	return require("opencode").format({
		path = path,
		from = { from_line },
		to = { to_line },
		rel = vim.fn.getcwd(),
	})
end

return M
