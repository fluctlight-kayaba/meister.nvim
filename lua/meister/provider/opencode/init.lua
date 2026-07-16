local client = require("meister.provider.opencode.client")
local discovery = require("meister.provider.opencode.discovery")
local util = require("meister.util")

local M = {}

---@type meister.opencode.Server?
local active_server = nil

local function display_name(url)
	return url:gsub("^%w+://", "")
end

local function format_annotations(annotations)
	local lines = {}
	for _, ann in ipairs(annotations) do
		local rel = vim.fn.fnamemodify(ann.file, ":.")
		local range = ann.from == ann.to
			and ("L%d"):format(ann.from)
			or ("L%d-L%d"):format(ann.from, ann.to)
		lines[#lines + 1] = ("%s:%s — %s"):format(rel, range, ann.text)
	end
	return table.concat(lines, "\n") .. "\n"
end

local function resolve_server(cb)
	if active_server then
		cb(active_server)
		return
	end
	discovery.find(function(servers)
		vim.schedule(function()
			if #servers == 0 then
				util.notify("no OpenCode server found", vim.log.levels.WARN)
				cb(nil)
			elseif #servers == 1 then
				active_server = servers[1]
				cb(servers[1])
			else
				vim.ui.select(servers, {
					prompt = "Select OpenCode server:",
					format_item = function(s)
						return display_name(s.url) .. " — " .. s.title
					end,
				}, function(choice)
					if choice then
						active_server = choice
					end
					cb(choice)
				end)
			end
		end)
	end)
end

---@param annotations meister.Annotation[]
---@param cb? fun(ok: boolean)
function M.send(annotations, cb)
	cb = cb or function() end
	resolve_server(function(server)
		if not server then
			cb(false)
			return
		end
		local text = format_annotations(annotations)
		client.post(server.url, "/tui/append-prompt", { text = text }, function(ok, err)
			vim.schedule(function()
				if not ok then
					util.notify("failed to append: " .. (err or "unknown"), vim.log.levels.ERROR)
				end
				cb(ok)
			end)
		end)
	end)
end

function M.select_server()
	active_server = nil
	resolve_server(function(server)
		if server then
			util.notify("connected to " .. display_name(server.url))
		end
	end)
end

return M
