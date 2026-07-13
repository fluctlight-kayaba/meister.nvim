local M = {}

local ns_placeholder = vim.api.nvim_create_namespace("meister_input_placeholder")
local ns_gap = vim.api.nvim_create_namespace("meister_input_gap")

local BOX_HEIGHT = 3
local Z_RAIL = 60
local Z_BOX = 61

local function scratch_buf()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	return buf
end

---@return fun() dispose
local function insert_gap(code_buf, row, height)
	local vlines = {}
	for _ = 1, height do
		vlines[#vlines + 1] = { { "", "NonText" } }
	end
	local mark = vim.api.nvim_buf_set_extmark(code_buf, ns_gap, row - 1, 0, { virt_lines = vlines })
	return function()
		pcall(vim.api.nvim_buf_del_extmark, code_buf, ns_gap, mark)
	end
end

local function open_rail(win, from_row, height, textoff, bar, accent)
	local buf = scratch_buf()
	local lines = {}
	for _ = 1, height do
		lines[#lines + 1] = bar
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	local rail = vim.api.nvim_open_win(buf, false, {
		relative = "win",
		win = win,
		bufpos = { from_row - 1, 0 },
		row = 0,
		col = -textoff,
		width = 1,
		height = height,
		style = "minimal",
		focusable = false,
		zindex = Z_RAIL,
	})
	vim.wo[rail].winhighlight = "Normal:" .. accent
	return rail
end

local function box_border(hl)
	return {
		{ "┌", hl },
		{ "─", hl },
		{ "┐", hl },
		{ "│", hl },
		{ "┘", hl },
		{ "─", hl },
		{ "└", hl },
		{ "│", hl },
	}
end

local function open_box(win, to_row, textoff, win_width, margin, border_hl)
	local buf = scratch_buf()
	local box = vim.api.nvim_open_win(buf, true, {
		relative = "win",
		win = win,
		bufpos = { to_row - 1, 0 },
		row = 1,
		col = -textoff + 1 + margin,
		width = math.max(win_width - margin - 3, 10),
		height = 1,
		style = "minimal",
		zindex = Z_BOX,
		border = box_border(border_hl),
	})
	vim.wo[box].signcolumn = "yes:1"
	return box, buf
end

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

	local info = vim.fn.getwininfo(opts.win)[1]
	local code_buf = vim.api.nvim_win_get_buf(opts.win)
	local rail_h = (opts.to_row - opts.from_row + 1) + BOX_HEIGHT

	local dispose_gap = insert_gap(code_buf, opts.to_row, BOX_HEIGHT)
	local rail = open_rail(opts.win, opts.from_row, rail_h, info.textoff, bar, accent)
	local box, buf = open_box(opts.win, opts.to_row, info.textoff, info.width, margin, border_hl)

	attach_placeholder(buf, opts.placeholder or "message")

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		dispose_gap()
		for _, w in ipairs({ rail, box }) do
			if vim.api.nvim_win_is_valid(w) then
				vim.api.nvim_win_close(w, true)
			end
		end
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
