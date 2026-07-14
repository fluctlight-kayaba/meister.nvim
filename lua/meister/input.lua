local M = {}

local ns_placeholder = vim.api.nvim_create_namespace("meister_input_placeholder")

local function attach_placeholder(buf, text)
	local function draw()
		local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
		vim.api.nvim_buf_clear_namespace(buf, ns_placeholder, 0, -1)
		if line == "" then
			vim.api.nvim_buf_set_extmark(buf, ns_placeholder, 0, 0, {
				virt_text = { { text, "Comment" } },
				virt_text_pos = "overlay",
			})
		end
	end
	draw()
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, { buffer = buf, callback = draw })
end

---@param opts { win: integer, from_row: integer, to_row: integer, accent_hl?: string, border_hl?: string, bar?: string, margin?: integer, placeholder?: string }
---@param on_submit fun(text: string)
function M.open(opts, on_submit)
	local accent = opts.accent_hl or "MeisterInputAccent"
	local border_hl = opts.border_hl or accent
	local bar = opts.bar or "▌"
	local margin = opts.margin or 1

	local widget = require("meister.render").open_input({
		win = opts.win,
		from_row = opts.from_row,
		to_row = opts.to_row,
		bar = bar,
		accent_hl = accent,
		border_hl = border_hl,
		margin = margin,
		enter = true,
	})
	local buf = widget.box_buf

	attach_placeholder(buf, opts.placeholder or "message")

	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = buf,
		callback = function()
			widget.resize()
		end,
	})

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		widget.dispose()
	end

	local function submit()
		local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
		close()
		if text ~= "" then
			on_submit(text)
		end
	end

	local kopts = { buffer = buf, nowait = true, silent = true }
	vim.keymap.set({ "n", "i" }, "<CR>", submit, kopts)
	vim.keymap.set("n", "<Esc>", close, kopts)
	vim.keymap.set("n", "q", close, kopts)
	vim.api.nvim_create_autocmd("BufLeave", { buffer = buf, once = true, callback = close })

	vim.cmd("startinsert")
end

return M
