local client = require("meister.provider.opencode.client")

local M = {}

---@class meister.opencode.Server
---@field url string
---@field cwd string
---@field title string

---@return { pid: integer, port: integer }[]
function M.scan_processes()
	local ps = vim.system({ "ps", "-eo", "pid=,command=" }):wait()
	if not ps or ps.code ~= 0 then
		return {}
	end
	local pids = {}
	for line in ps.stdout:gmatch("[^\n]+") do
		if line:find("opencode", 1, true) and line:find("--port", 1, true) then
			local pid = tonumber(line:match("^%s*(%d+)"))
			if pid then
				pids[#pids + 1] = pid
			end
		end
	end
	if #pids == 0 then
		return {}
	end

	local lsof = vim.system({
		"lsof",
		"-Fpn",
		"-w",
		"-iTCP",
		"-sTCP:LISTEN",
		"-p",
		table.concat(pids, ","),
		"-a",
		"-P",
		"-n",
	}):wait()
	if not lsof or lsof.code ~= 0 then
		return {}
	end

	local processes = {}
	local pid
	for line in lsof.stdout:gmatch("[^\n]+") do
		local prefix = line:sub(1, 1)
		local value = line:sub(2)
		if prefix == "p" then
			pid = tonumber(value)
		elseif prefix == "n" then
			local port = tonumber(value:match(":(%d+)$"))
			if port and pid then
				table.insert(processes, { pid = pid, port = port })
			end
		end
	end
	return processes
end

local function probe(port, cb)
	local url = "http://localhost:" .. port
	client.get(url, "/global/health", function(_, err)
		if err then
			cb(nil)
			return
		end
		client.get(url, "/path", function(path_data, path_err)
			if path_err then
				cb(nil)
				return
			end
			client.get(url, "/session", function(sessions, _)
				local title = (sessions and sessions[1] and sessions[1].title) or "<No sessions>"
				cb({
					url = url,
					cwd = path_data.directory or path_data.worktree,
					title = title,
				})
			end)
		end)
	end)
end

---@param cb fun(servers: meister.opencode.Server[])
local function probe_all(cb)
	local processes = M.scan_processes()
	if #processes == 0 then
		cb({})
		return
	end
	local remaining = #processes
	local servers = {}
	for _, proc in ipairs(processes) do
		probe(proc.port, function(server)
			if server then
				table.insert(servers, server)
			end
			remaining = remaining - 1
			if remaining == 0 then
				cb(servers)
			end
		end)
	end
end

---@param cb fun(servers: meister.opencode.Server[])
function M.find(cb)
	local nvim_cwd = vim.fn.getcwd()
	probe_all(function(servers)
		local matched = {}
		for _, s in ipairs(servers) do
			if s.cwd:find(nvim_cwd, 0, true) == 1 or nvim_cwd:find(s.cwd, 0, true) == 1 then
				matched[#matched + 1] = s
			end
		end
		cb(matched)
	end)
end

---@param cb fun(servers: meister.opencode.Server[])
function M.find_all(cb)
	probe_all(cb)
end

return M
