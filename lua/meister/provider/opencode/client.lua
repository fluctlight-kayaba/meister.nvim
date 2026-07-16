local M = {}

---@param url string
---@param path string
---@param method "GET" | "POST"
---@param body? table
---@param cb fun(obj: vim.SystemCompleted)
function M.request(url, path, method, body, cb)
	local args = {
		"curl",
		"-s",
		"-S",
		"--fail-with-body",
		"--max-time",
		"3",
		"-X",
		method,
		"-H",
		"Content-Type: application/json",
		"-H",
		"Accept: application/json",
	}
	if body then
		args[#args + 1] = "-d"
		args[#args + 1] = vim.json.encode(body)
	end
	args[#args + 1] = url .. path
	vim.system(args, { text = true }, cb)
end

---@param url string
---@param path string
---@param cb fun(data: table?, err: string?)
function M.get(url, path, cb)
	M.request(url, path, "GET", nil, function(obj)
		if obj.code ~= 0 then
			cb(nil, obj.stderr)
			return
		end
		local ok, data = pcall(vim.json.decode, obj.stdout)
		if not ok then
			cb(nil, "failed to decode JSON")
			return
		end
		cb(data, nil)
	end)
end

---@param url string
---@param path string
---@param body table
---@param cb fun(ok: boolean, err: string?)
function M.post(url, path, body, cb)
	M.request(url, path, "POST", body, function(obj)
		if obj.code ~= 0 then
			cb(false, obj.stderr)
			return
		end
		cb(true, nil)
	end)
end

return M
