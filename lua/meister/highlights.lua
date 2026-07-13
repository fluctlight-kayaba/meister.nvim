local M = {}

local groups = {
	MeisterInputAccent = { fg = "#e0af68" },
}

function M.setup()
	local function apply()
		for name, val in pairs(groups) do
			vim.api.nvim_set_hl(0, name, vim.tbl_extend("keep", { default = true }, val))
		end
	end
	apply()
	vim.api.nvim_create_autocmd("ColorScheme", { callback = apply })
end

return M
