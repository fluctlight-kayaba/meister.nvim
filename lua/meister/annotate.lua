local M = {}

local util = require("meister.util")

local ns = vim.api.nvim_create_namespace("meister_annotate")

---@type table<integer, table<integer, { text: string, from_line: integer, from_col?: integer, to_line: integer, to_col?: integer }>>
M.notes = {}

local function visual_selection()
	local mode = vim.fn.mode()
	local start_pos = vim.fn.getpos("v")
	local end_pos = vim.fn.getpos(".")
	local start_line, start_col = start_pos[2], start_pos[3]
	local end_line, end_col = end_pos[2], end_pos[3]
	if start_line > end_line or (start_line == end_line and start_col > end_col) then
		start_line, end_line = end_line, start_line
		start_col, end_col = end_col, start_col
	end
	local kind = mode == "V" and "line" or mode == "\22" and "block" or "char"
	if kind == "line" then
		return { from_line = start_line, to_line = end_line }
	end
	return {
		from_line = start_line,
		from_col = start_col - 1,
		to_line = end_line,
		to_col = end_col,
	}
end

local function place_note(bufnr, sel, text)
	require("meister.card").place(bufnr, sel.from_line, sel.to_line, text)
	local extmark_opts = { end_row = sel.to_line - 1 }
	if sel.from_col then
		local line = vim.api.nvim_buf_get_lines(bufnr, sel.to_line - 1, sel.to_line, false)[1] or ""
		extmark_opts.end_col = math.min(sel.to_col, #line)
	end
	local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, sel.from_line - 1, sel.from_col or 0, extmark_opts)
	if not ok then
		return
	end
	M.notes[bufnr] = M.notes[bufnr] or {}
	M.notes[bufnr][id] = {
		text = text,
		from_line = sel.from_line,
		from_col = sel.from_col,
		to_line = sel.to_line,
		to_col = sel.to_col,
	}
end

local function persist(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return
	end
	local entries = {}
	for id, note in pairs(M.notes[bufnr] or {}) do
		local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, id, { details = true })
		if pos[1] then
			local entry = {
				from = note.from_line or (pos[1] + 1),
				to = note.to_line or ((pos[3] and pos[3].end_row) or pos[1]) + 1,
				text = note.text,
			}
			if note.from_col then
				entry.from_col = note.from_col
				entry.to_col = note.to_col
			end
			entries[#entries + 1] = entry
		end
	end
	require("meister.store").save(path, entries)
end

---@param bufnr? integer
function M.load_buf(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return
	end
	local saved = require("meister.store").load(path)
	require("meister.card").close(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	M.notes[bufnr] = nil
	for _, e in ipairs(saved) do
		local sel = { from_line = e.from, to_line = e.to }
		if e.from_col then
			sel.from_col = e.from_col
			sel.to_col = e.to_col
		end
		place_note(bufnr, sel, e.text)
	end

	if vim.api.nvim_buf_is_valid(bufnr) and next(M.notes[bufnr] or {}) then
		vim.keymap.set(
			"n",
			"<LeftMouse>",
			"<LeftMouse><Cmd>lua require('meister.annotate')._check_click()<CR>",
			{ buffer = bufnr, silent = true }
		)
	end
end

local function edit_note(bufnr, id, note)
	local cfg = require("meister.config").options.annotate.input
	local win = vim.fn.bufwinid(bufnr)
	if win == -1 then
		win = vim.api.nvim_get_current_win()
	end
	require("meister.card").hide(bufnr, note.from_line, note.to_line)
	require("meister.input").open({
		win = win,
		from_row = note.from_line,
		to_row = note.to_line,
		accent_hl = cfg.accent_hl,
		border_hl = cfg.border_hl,
		bar = cfg.bar,
		margin = cfg.margin,
		default_text = note.text,
		on_close = function()
			persist(bufnr)
			M.load_buf(bufnr)
		end,
	}, function(text)
		if text == "" then
			if M.notes[bufnr] then
				M.notes[bufnr][id] = nil
			end
			pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, id)
		else
			note.text = text
		end
	end)
end

function M._check_click()
	if require("meister.input").active then
		return
	end
	local mp = vim.fn.getmousepos()
	local win = mp.winid
	if not win or win == 0 then
		return
	end
	local bufnr = vim.api.nvim_win_get_buf(win)
	for id, note in pairs(M.notes[bufnr] or {}) do
		local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, id, { details = true })
		if pos[1] then
			local to = ((pos[3] and pos[3].end_row) or pos[1]) + 1
			local sp = vim.fn.screenpos(win, to, 1)
			if sp.row > 0 then
				local box_height = 2 + #vim.split(note.text, "\n", { plain = true })
				if mp.screenrow > sp.row and mp.screenrow <= sp.row + box_height then
					vim.schedule(function()
						edit_note(bufnr, id, note)
					end)
					return
				end
			end
		end
	end
end

function M.edit_at_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]

	local matches = {}
	for id, note in pairs(M.notes[bufnr] or {}) do
		if note.from_line <= row and note.to_line >= row then
			matches[#matches + 1] = { id = id, note = note }
		end
	end

	if #matches == 0 then
		return false
	end

	if #matches == 1 then
		vim.schedule(function()
			edit_note(bufnr, matches[1].id, matches[1].note)
		end)
	else
		vim.schedule(function()
			vim.ui.select(matches, {
				prompt = "Edit annotation:",
				format_item = function(m)
					return m.note.text
				end,
			}, function(choice)
				if choice then
					edit_note(bufnr, choice.id, choice.note)
				end
			end)
		end)
	end
	return true
end

---@param range? { [1]: integer, [2]: integer }
function M.add(range)
	local sel
	if range then
		sel = { from_line = range[1], to_line = range[2] }
	else
		sel = visual_selection()
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
	end
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.api.nvim_buf_get_name(bufnr) == "" then
		util.notify("buffer has no file path", vim.log.levels.WARN)
		return
	end
	local win = vim.api.nvim_get_current_win()
	vim.schedule(function()
		local input = require("meister.config").options.annotate.input
		require("meister.input").open({
			win = win,
			from_row = sel.from_line,
			to_row = sel.to_line,
			accent_hl = input.accent_hl,
			border_hl = input.border_hl,
			bar = input.bar,
			margin = input.margin,
			placeholder = input.placeholder,
		}, function(text)
			if text ~= "" then
				place_note(bufnr, sel, text)
				persist(bufnr)
			end
		end)
	end)
end

---@param bufnr? integer if given, only collect from this buffer
---@return meister.Annotation[]
local function collect_loaded(bufnr)
	local annotations = {}
	local buffers = bufnr and { bufnr } or vim.tbl_keys(M.notes)
	for _, b in ipairs(buffers) do
		if M.notes[b] and vim.api.nvim_buf_is_valid(b) then
			local file = vim.api.nvim_buf_get_name(b)
			for id, note in pairs(M.notes[b]) do
				local pos = vim.api.nvim_buf_get_extmark_by_id(b, ns, id, { details = true })
				local row = pos and pos[1]
				if row and row >= 0 then
					annotations[#annotations + 1] = {
						file = file,
						from = note.from_line or (row + 1),
						to = note.to_line or (((pos[3] and pos[3].end_row) or row) + 1),
						from_col = note.from_col,
						to_col = note.to_col,
						text = note.text,
					}
				end
			end
		end
	end
	return annotations
end

local function do_send(annotations)
	if #annotations == 0 then
		util.notify("no annotations to send", vim.log.levels.WARN)
		return
	end
	local cfg = require("meister.config").options.send
	local provider = require("meister.provider").get()
	provider.send(annotations, function(ok)
		if ok then
			vim.schedule(function()
				if cfg.clear_after_send then
					M.clear()
				end
				util.notify(("sent %d annotation(s)"):format(#annotations))
			end)
		end
	end)
end

function M.send_current()
	do_send(collect_loaded(vim.api.nvim_get_current_buf()))
end

function M.send_all()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		path = vim.fn.getcwd() .. "/."
	end
	if vim.api.nvim_buf_get_name(bufnr) ~= "" then
		persist(bufnr)
	end
	do_send(require("meister.store").load_all(path))
end

---@param all boolean list sessions across all projects, not just the current one
function M.select_session(all)
	local provider = require("meister.provider").get()
	if not provider.select_session then
		util.notify("provider does not support session picking", vim.log.levels.WARN)
		return
	end
	provider.select_session(all)
end

function M.clear()
	for bufnr in pairs(M.notes) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
			require("meister.card").close(bufnr)
			local path = vim.api.nvim_buf_get_name(bufnr)
			if path ~= "" then
				require("meister.store").save(path, {})
			end
		end
	end
	M.notes = {}
end

function M.list()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		path = vim.fn.getcwd() .. "/."
	end
	if vim.api.nvim_buf_get_name(bufnr) ~= "" then
		persist(bufnr)
	end
	local store = require("meister.store")
	local all = store.load_all(path)
	if #all == 0 then
		util.notify("no annotations", vim.log.levels.WARN)
		return
	end

	local loaded_files = {}
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		loaded_files[vim.api.nvim_buf_get_name(b)] = true
	end
	for _, ann in ipairs(all) do
		if not loaded_files[ann.file] then
			local b = vim.fn.bufadd(ann.file)
			vim.fn.bufload(b)
			M.load_buf(b)
		end
	end
	table.sort(all, function(a, b)
		if a.file ~= b.file then
			return a.file < b.file
		end
		return a.from < b.from
	end)

	local entries = {}
	for _, ann in ipairs(all) do
		entries[#entries + 1] = ("%s:%d:%s"):format(ann.file, ann.from, ann.text)
	end

	local function parse_entry(selected)
		local file, line = selected[1]:match("^(.-):(%d+):")
		return file, tonumber(line)
	end

	local function open_and_edit(selected)
		local file, line = parse_entry(selected)
		vim.cmd("edit " .. vim.fn.fnameescape(file))
		vim.api.nvim_win_set_cursor(0, { line, 0 })
		vim.schedule(function()
			M.edit_at_cursor()
		end)
	end

	local fzf_ok, fzf = pcall(require, "fzf-lua")
	if not fzf_ok then
		vim.ui.select(entries, {
			prompt = "Annotations:",
			format_item = function(e)
				return e:match(":%d+:(.*)$")
			end,
		}, function(choice)
			if not choice then
				return
			end
			open_and_edit({ choice })
		end)
		return
	end

	fzf.fzf_exec(entries, {
		prompt = " Annotations> ",
		previewer = "builtin",
		winopts = {
			title = " Annotations ",
			title_pos = "center",
		},
		fzf_opts = {
			["--delimiter"] = ":",
			["--with-nth"] = "3..",
			["--preview-window"] = "right:60%",
		},
		actions = {
			["default"] = function(selected)
				open_and_edit(selected)
			end,
		},
	})
end

return M
