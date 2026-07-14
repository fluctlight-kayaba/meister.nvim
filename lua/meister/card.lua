local M = {}

local ns = vim.api.nvim_create_namespace("meister_card")

---@param bufnr integer
---@return integer widest text area across windows showing the buffer
local function full_width(bufnr)
	local max = 0
	for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
		if vim.api.nvim_win_is_valid(win) then
			local info = vim.fn.getwininfo(win)[1]
			local w = info.width - info.textoff
			if w > max then
				max = w
			end
		end
	end
	return max > 0 and max or vim.o.columns
end

---@param bufnr integer
---@param from integer
---@param to integer
---@param text string
function M.place(bufnr, from, to, text)
	local cfg = require("meister.config").options.annotate
	for row = from, to do
		vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, 0, {
			sign_text = cfg.input.bar,
			sign_hl_group = cfg.input.accent_hl,
		})
	end
	vim.api.nvim_buf_set_extmark(bufnr, ns, to - 1, 0, {
		virt_lines = require("meister.render").box_lines(text, {
			width = full_width(bufnr) - 3,
			border_hl = cfg.card.border_hl,
			text_hl = cfg.card.text_hl,
		}),
	})
end

---@param bufnr integer
function M.close(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

return M
