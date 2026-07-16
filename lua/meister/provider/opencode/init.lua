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
		local range
		if ann.from_col then
			range = ("L%d:C%d"):format(ann.from, ann.from_col)
			if ann.to ~= ann.from then
				range = range .. ("-L%d"):format(ann.to)
			end
			if ann.to_col and ann.to_col ~= ann.from_col then
				range = range .. (":C%d"):format(ann.to_col)
			end
		elseif ann.from == ann.to then
			range = ("L%d"):format(ann.from)
		else
			range = ("L%d-L%d"):format(ann.from, ann.to)
		end
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

---@param servers meister.opencode.Server[]
---@param cb fun(items: { server: meister.opencode.Server, session: table }[])
local function gather_sessions(servers, cb)
	local items = {}
	local remaining = #servers
	if remaining == 0 then
		cb(items)
		return
	end
	for _, server in ipairs(servers) do
		client.get(server.url, "/session", function(sessions, _)
			if sessions then
				for _, s in ipairs(sessions) do
					if not s.parentID then
						items[#items + 1] = { server = server, session = s }
					end
				end
			end
			remaining = remaining - 1
			if remaining == 0 then
				cb(items)
			end
		end)
	end
end

---@param all boolean list sessions from every running server, not just the current project
function M.select_session(all)
	local finder = all and discovery.find_all or discovery.find
	finder(function(servers)
		if #servers == 0 then
			vim.schedule(function()
				util.notify("no OpenCode server found", vim.log.levels.WARN)
			end)
			return
		end
		gather_sessions(servers, function(items)
			vim.schedule(function()
				if all then
					local newest = {}
					for _, it in ipairs(items) do
						local cur = newest[it.server.url]
						if not cur or it.session.time.updated > cur.session.time.updated then
							newest[it.server.url] = it
						end
					end
					items = vim.tbl_values(newest)
				end
				if #items == 0 then
					util.notify("no sessions found", vim.log.levels.WARN)
					return
				end
				table.sort(items, function(a, b)
					return a.session.time.updated > b.session.time.updated
				end)
				vim.ui.select(items, {
					prompt = all and "OpenCode session (all projects):" or "OpenCode session:",
					format_item = function(it)
						local title = it.session.title or it.session.slug or it.session.id
						if all then
							return ("%s — %s"):format(
								vim.fn.fnamemodify(it.session.directory or it.server.cwd, ":t"),
								title
							)
						end
						return title
					end,
				}, function(choice)
					if not choice then
						return
					end
					client.post(
						choice.server.url,
						"/tui/select-session",
						{ sessionID = choice.session.id },
						function(ok, err)
							vim.schedule(function()
								if ok then
									active_server = choice.server
									util.notify("session: " .. (choice.session.title or choice.session.id))
								else
									util.notify("select-session failed: " .. (err or "unknown"), vim.log.levels.ERROR)
								end
							end)
						end
					)
				end)
			end)
		end)
	end)
end

return M
