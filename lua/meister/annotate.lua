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
	local cfg = require("meister.config").options.annotate
	local id = vim.api.nvim_buf_set_extmark(bufnr, ns, from - 1, 0, {
		end_row = to - 1,
		virt_text = { { cfg.virt_text_prefix .. text, cfg.highlight } },
		virt_text_pos = cfg.virt_text_pos,
	})
	M.notes[bufnr] = M.notes[bufnr] or {}
	M.notes[bufnr][id] = { text = text }
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
		end)
	end)
end

---@param provider meister.Provider
---@return string[]
local function collect(provider)
	local parts = {}
	for bufnr, marks in pairs(M.notes) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local file = vim.api.nvim_buf_get_name(bufnr)
			for id, note in pairs(marks) do
				local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, id, { details = true })
				local from = pos[1] + 1
				local to = ((pos[3] and pos[3].end_row) or pos[1]) + 1
				parts[#parts + 1] = ("%s: %s"):format(provider.format_ref(file, from, to) or file, note.text)
			end
		end
	end
	return parts
end

function M.send()
	local provider = require("meister.provider").get()
	local parts = collect(provider)
	if #parts == 0 then
		util.notify("no annotations to send", vim.log.levels.WARN)
		return
	end
	local cfg = require("meister.config").options.send
	local prompt = (type(cfg.template) == "function" and cfg.template(parts))
		or (cfg.header .. "\n" .. table.concat(parts, "\n"))
	provider.send(prompt)
	if cfg.clear_after_send then
		M.clear()
	end
	util.notify(("sent %d annotation(s)"):format(#parts))
end

function M.clear()
	for bufnr in pairs(M.notes) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
		end
	end
	M.notes = {}
end

return M
