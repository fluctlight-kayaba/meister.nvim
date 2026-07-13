local M = {}

---@param opts? meister.Config
function M.setup(opts)
	require("meister.config").setup(opts)
end

---@param range? { [1]: integer, [2]: integer }
function M.annotate(range)
	require("meister.annotate").add(range)
end

function M.send()
	require("meister.annotate").send()
end

function M.clear()
	require("meister.annotate").clear()
end

return M
