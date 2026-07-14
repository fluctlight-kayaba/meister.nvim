local M = {}

local groups = {
	MeisterInputAccent = { fg = "#e0af68" },
	MeisterCardBorder = { link = "Comment" },
	MeisterCardText = { link = "Comment" },
}

function M.setup()
	local function apply()
		for name, val in pairs(groups) do
			vim.api.nvim_set_hl(0, name, vim.tbl_extend("keep", { default = true }, val))
		end
		local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
		if normal.bg then
			vim.api.nvim_set_hl(0, "MeisterGhostNr", { fg = normal.bg })
		end
	end
	apply()
	vim.api.nvim_create_autocmd("ColorScheme", { callback = apply })
end

return M
