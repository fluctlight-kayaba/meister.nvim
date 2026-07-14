local M = {}

M.glyphs = { tl = "┌", tr = "┐", bl = "└", br = "┘", h = "─", v = "│" }

local ns_gap = vim.api.nvim_create_namespace("meister_gap")
local Z_BOX = 61

---@param hl string
---@return table border spec for nvim_open_win (tl, top, tr, right, br, bottom, bl, left)
function M.win_border(hl)
	local g = M.glyphs
	return {
		{ g.tl, hl },
		{ g.h, hl },
		{ g.tr, hl },
		{ g.v, hl },
		{ g.br, hl },
		{ g.h, hl },
		{ g.bl, hl },
		{ g.v, hl },
	}
end

---@param text string
---@param opts { border_hl: string, text_hl: string, width?: integer }
---@return table[] virt_lines for a bordered box
function M.box_lines(text, opts)
	local g = M.glyphs
	local lines = vim.split(text, "\n", { plain = true })
	local maxw = 0
	for _, l in ipairs(lines) do
		maxw = math.max(maxw, vim.fn.strdisplaywidth(l))
	end
	local inner = math.max(opts.width or (maxw + 2), maxw + 2)
	local rule = string.rep(g.h, inner)
	local vlines = { { { g.tl .. rule .. g.tr, opts.border_hl } } }
	for _, l in ipairs(lines) do
		local pad = string.rep(" ", inner - 1 - vim.fn.strdisplaywidth(l))
		vlines[#vlines + 1] = { { g.v .. " ", opts.border_hl }, { l, opts.text_hl }, { pad .. g.v, opts.border_hl } }
	end
	vlines[#vlines + 1] = { { g.bl .. rule .. g.br, opts.border_hl } }
	return vlines
end

local function scratch_buf()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	return buf
end

---@return fun() dispose
local function insert_gap(code_buf, row, height, last_line)
	local vlines = {}
	for _ = 1, height - (last_line and 1 or 0) do
		vlines[#vlines + 1] = { { "", "NonText" } }
	end
	if last_line then
		vlines[#vlines + 1] = last_line
	end
	local mark = vim.api.nvim_buf_set_extmark(code_buf, ns_gap, row - 1, 0, { virt_lines = vlines })
	return function()
		pcall(vim.api.nvim_buf_del_extmark, code_buf, ns_gap, mark)
	end
end

---Open the interactive annotation input: gutter gap + accent rail + editable bordered float.
---@param opts { win: integer, from_row: integer, to_row: integer, bar: string, accent_hl: string, border_hl: string, margin: integer, zindex?: integer, enter?: boolean }
---@return { box_win: integer, rail_win: integer, box_buf: integer, dispose: fun(), reflow: fun(), resize: fun() }
function M.open_input(opts)
	local code_buf = vim.api.nvim_win_get_buf(opts.win)
	local box_z = opts.zindex or Z_BOX
	local codelines = opts.to_row - opts.from_row + 1
	local content_h = 3
	local dispose_gap

	local function geom()
		local info = vim.fn.getwininfo(opts.win)[1]
		local off_screen = not (opts.to_row >= info.topline and opts.from_row <= info.botline)
		local wrong_buf = vim.api.nvim_win_get_buf(opts.win) ~= code_buf
		return info.textoff, math.max(info.width - info.textoff - 2, 10), off_screen or wrong_buf
	end

	local function rail_config(textoff, hide)
		return {
			relative = "win",
			win = opts.win,
			bufpos = { opts.from_row - 1, 0 },
			row = 0,
			col = -textoff,
			width = 1,
			height = codelines + content_h + 2,
			style = "minimal",
			focusable = false,
			zindex = box_z - 1,
			hide = hide,
		}
	end

	local function box_config(width, hide)
		return {
			relative = "win",
			win = opts.win,
			bufpos = { opts.to_row - 1, 0 },
			row = 1,
			col = -1,
			width = width,
			height = content_h,
			style = "minimal",
			focusable = opts.enter or false,
			zindex = box_z,
			border = M.win_border(opts.border_hl),
			hide = hide,
		}
	end

	local textoff, width, hide = geom()

	local function build_hint(w)
		return {
			{ string.rep(" ", math.max(w - 23, 0)), "NonText" },
			{ "Enter ", opts.accent_hl },
			{ "save", "Comment" },
			{ " · ", "Comment" },
			{ "Esc ", opts.accent_hl },
			{ "cancel", "Comment" },
		}
	end
	dispose_gap = insert_gap(code_buf, opts.to_row, content_h + 3, build_hint(width))

	local rail_buf = scratch_buf()
	local function rail_lines()
		local rl = {}
		for _ = 1, codelines + content_h + 2 do
			rl[#rl + 1] = opts.bar
		end
		return rl
	end
	vim.api.nvim_buf_set_lines(rail_buf, 0, -1, false, rail_lines())
	local rail = vim.api.nvim_open_win(rail_buf, false, rail_config(textoff, hide))
	vim.wo[rail].winhighlight = "Normal:" .. opts.accent_hl

	local box_buf = scratch_buf()
	local box = vim.api.nvim_open_win(box_buf, opts.enter or false, box_config(width, hide))
	vim.wo[box].signcolumn = "yes:1"

	local disposed = false
	local function dispose()
		if disposed then
			return
		end
		disposed = true
		dispose_gap()
		for _, w in ipairs({ rail, box }) do
			if vim.api.nvim_win_is_valid(w) then
				pcall(vim.api.nvim_win_close, w, true)
			end
		end
	end

	local function reflow()
		if disposed or not vim.api.nvim_win_is_valid(opts.win) then
			return
		end
		local t, wd, h = geom()
		if vim.api.nvim_win_is_valid(rail) then
			pcall(vim.api.nvim_win_set_config, rail, rail_config(t, h))
		end
		if vim.api.nvim_win_is_valid(box) then
			pcall(vim.api.nvim_win_set_config, box, box_config(wd, h))
			vim.wo[box].signcolumn = "yes:1"
		end
	end

	local function resize()
		if disposed then
			return
		end
		local n = math.max(vim.api.nvim_buf_line_count(box_buf), 3)
		if n == content_h then
			return
		end
		content_h = n
		local t, wd, h = geom()
		if dispose_gap then
			dispose_gap()
		end
		dispose_gap = insert_gap(code_buf, opts.to_row, content_h + 3, build_hint(wd))
		if vim.api.nvim_buf_is_valid(rail_buf) then
			vim.api.nvim_buf_set_lines(rail_buf, 0, -1, false, rail_lines())
		end
		if vim.api.nvim_win_is_valid(rail) then
			pcall(vim.api.nvim_win_set_config, rail, rail_config(t, h))
		end
		if vim.api.nvim_win_is_valid(box) then
			pcall(vim.api.nvim_win_set_config, box, box_config(wd, h))
			vim.wo[box].signcolumn = "yes:1"
		end
	end

	return { box_win = box, rail_win = rail, box_buf = box_buf, dispose = dispose, reflow = reflow, resize = resize }
end

return M
