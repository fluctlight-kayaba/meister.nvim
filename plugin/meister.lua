if vim.g.loaded_meister then
	return
end
vim.g.loaded_meister = true

require("meister.highlights").setup()

vim.keymap.set("x", "<Plug>(meister-annotate)", function()
	require("meister.annotate").add()
end, { desc = "Meister: annotate selection" })

vim.keymap.set("n", "<Plug>(meister-annotate)", function()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	require("meister.annotate").add({ line, line })
end, { desc = "Meister: annotate current line" })

vim.keymap.set("n", "<Plug>(meister-send)", function()
	require("meister.annotate").send()
end, { desc = "Meister: send annotations" })

vim.keymap.set("n", "<Plug>(meister-clear)", function()
	require("meister.annotate").clear()
end, { desc = "Meister: clear annotations" })

local subcommands = {
	annotate = function(a)
		require("meister.annotate").add(a.range > 0 and { a.line1, a.line2 } or nil)
	end,
	send = function()
		require("meister.annotate").send()
	end,
	clear = function()
		require("meister.annotate").clear()
	end,
	load = function()
		require("meister.annotate").load_buf()
	end,
}

vim.api.nvim_create_user_command("Meister", function(a)
	local fn = subcommands[a.fargs[1]]
	if not fn then
		vim.notify("Meister: unknown subcommand: " .. tostring(a.fargs[1]), vim.log.levels.ERROR)
		return
	end
	fn(a)
end, {
	nargs = 1,
	range = true,
	complete = function(lead)
		return vim.tbl_filter(function(k)
			return k:find(lead, 1, true) == 1
		end, vim.tbl_keys(subcommands))
	end,
	desc = "Meister annotations",
})

vim.api.nvim_create_autocmd("BufReadPost", {
	group = vim.api.nvim_create_augroup("meister_persist", { clear = true }),
	callback = function(a)
		require("meister.annotate").load_buf(a.buf)
	end,
})

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_is_loaded(buf) then
		require("meister.annotate").load_buf(buf)
	end
end
