local M = {}

M.active = false

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

---@param opts { win: integer, from_row: integer, to_row: integer, accent_hl?: string, border_hl?: string, bar?: string, margin?: integer, placeholder?: string, default_text?: string, on_close?: fun() }
---@param on_submit fun(text: string)
function M.open(opts, on_submit)
	M.active = true
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

	if opts.default_text and opts.default_text ~= "" then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.default_text, "\n", { plain = true }))
	end

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
		vim.schedule(function()
			M.active = false
			vim.cmd("stopinsert")
		end)
	end

	local finished = false
	local function finish(text)
		if finished then
			return
		end
		finished = true
		if text ~= nil then
			on_submit(text)
		end
		close()
		if opts.on_close then
			opts.on_close()
		end
	end

	local function submit()
		finish(vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")))
	end
	local function cancel()
		finish(nil)
	end

	local kopts = { buffer = buf, nowait = true, silent = true }
	vim.keymap.set({ "n", "i" }, "<CR>", submit, kopts)
	vim.keymap.set("n", "<Esc>", cancel, kopts)
	vim.keymap.set("n", "q", cancel, kopts)
	vim.api.nvim_create_autocmd("BufLeave", { buffer = buf, once = true, callback = cancel })

	vim.cmd("startinsert")
end

return M
