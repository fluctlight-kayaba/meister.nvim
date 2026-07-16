local M = {}

local uv = vim.uv or vim.loop

local function resolve(path)
	local found = vim.fs.find(".git", { upward = true, path = vim.fs.dirname(path) })[1]
	if not found then
		return nil
	end
	local root = vim.fs.dirname(found)
	local gitdir
	local st = uv.fs_stat(found)
	if st and st.type == "directory" then
		gitdir = found
	else
		local fd = io.open(found, "r")
		if not fd then
			return nil
		end
		local first = fd:read("*l") or ""
		fd:close()
		local g = first:match("^gitdir:%s*(.+)$")
		if not g then
			return nil
		end
		if not g:match("^/") then
			g = root .. "/" .. g
		end
		gitdir = vim.fs.normalize(g)
	end
	return { root = root, dir = gitdir .. "/meister" }
end

local function relkey(root, path)
	if vim.fs.relpath then
		return vim.fs.relpath(root, path) or path
	end
	local prefix = root .. "/"
	if path:sub(1, #prefix) == prefix then
		return path:sub(#prefix + 1)
	end
	return path
end

local function store_file(ctx)
	return ctx.dir .. "/annotations.json"
end

local function read_all(ctx)
	local fd = io.open(store_file(ctx), "r")
	if not fd then
		return {}
	end
	local raw = fd:read("*a")
	fd:close()
	if not raw or raw == "" then
		return {}
	end
	local ok, data = pcall(vim.json.decode, raw)
	if not ok or type(data) ~= "table" then
		return {}
	end
	return data
end

local function write_all(ctx, data)
	vim.fn.mkdir(ctx.dir, "p")
	local fd = io.open(store_file(ctx), "w")
	if not fd then
		return false
	end
	fd:write(vim.json.encode(data))
	fd:close()
	return true
end

---@param path string
---@return { from: integer, to: integer, text: string }[]
function M.load(path)
	if not path or path == "" then
		return {}
	end
	local ctx = resolve(path)
	if not ctx then
		return {}
	end
	return read_all(ctx)[relkey(ctx.root, path)] or {}
end

---@param path string
---@param entries { from: integer, to: integer, text: string }[]
function M.save(path, entries)
	if not path or path == "" then
		return
	end
	local ctx = resolve(path)
	if not ctx then
		return
	end
	local data = read_all(ctx)
	local key = relkey(ctx.root, path)
	if entries and #entries > 0 then
		data[key] = entries
	else
		data[key] = nil
	end
	write_all(ctx, data)
end

---@param path string any path within the repo to resolve git dir
---@return meister.Annotation[]
function M.load_all(path)
	if not path or path == "" then
		return {}
	end
	local ctx = resolve(path)
	if not ctx then
		return {}
	end
	local data = read_all(ctx)
	local annotations = {}
	for relpath, entries in pairs(data) do
		local abs = ctx.root .. "/" .. relpath
		for _, e in ipairs(entries) do
			annotations[#annotations + 1] = { file = abs, from = e.from, to = e.to, text = e.text }
		end
	end
	return annotations
end

---@param path string
---@param from_line integer
function M.delete_entry(path, from_line)
	local ctx = resolve(path)
	if not ctx then
		return
	end
	local data = read_all(ctx)
	local key = relkey(ctx.root, path)
	if not data[key] then
		return
	end
	for i, e in ipairs(data[key]) do
		if e.from == from_line then
			table.remove(data[key], i)
			break
		end
	end
	if #data[key] == 0 then
		data[key] = nil
	end
	write_all(ctx, data)
end

---@param path string
---@param from_line integer
---@param new_text string
function M.update_entry(path, from_line, new_text)
	local ctx = resolve(path)
	if not ctx then
		return
	end
	local data = read_all(ctx)
	local key = relkey(ctx.root, path)
	if not data[key] then
		return
	end
	for _, e in ipairs(data[key]) do
		if e.from == from_line then
			e.text = new_text
			break
		end
	end
	write_all(ctx, data)
end

return M
