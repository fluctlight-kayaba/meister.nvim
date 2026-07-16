local M = {}

local util = require("meister.util")

local ns = vim.api.nvim_create_namespace("meister_annotate")

---@type table<integer, table<integer, { text: string }>>
M.notes = {}

local function visual_range()
	local l1 = vim.fn.getpos("v")[2]
	local l2 = vim.fn.getpos(".")[2]
	if l1 > l2 then
		l1, l2 = l2, l1
	end
	return l1, l2
end

local function place_note(bufnr, from, to, text)
	require("meister.card").place(bufnr, from, to, text)
	local id = vim.api.nvim_buf_set_extmark(bufnr, ns, from - 1, 0, { end_row = to - 1 })
	M.notes[bufnr] = M.notes[bufnr] or {}
	M.notes[bufnr][id] = { text = text }
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
			local from = pos[1] + 1
			local to = ((pos[3] and pos[3].end_row) or pos[1]) + 1
			entries[#entries + 1] = { from = from, to = to, text = note.text }
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
		place_note(bufnr, e.from, e.to, e.text)
	end
end

---@param range? { [1]: integer, [2]: integer }
function M.add(range)
	local from, to
	if range then
		from, to = range[1], range[2]
	else
		from, to = visual_range()
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
			from_row = from,
			to_row = to,
			accent_hl = input.accent_hl,
			border_hl = input.border_hl,
			bar = input.bar,
			margin = input.margin,
			placeholder = input.placeholder,
		}, function(text)
			place_note(bufnr, from, to, text)
			persist(bufnr)
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
					local from = row + 1
					local to = ((pos[3] and pos[3].end_row) or row) + 1
					annotations[#annotations + 1] = { file = file, from = from, to = to, text = note.text }
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

return M
