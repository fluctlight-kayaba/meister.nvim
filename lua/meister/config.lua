local M = {}

---@class meister.InputConfig
---@field accent_hl string
---@field border_hl string
---@field bar string
---@field margin integer
---@field placeholder string

---@class meister.AnnotateConfig
---@field virt_text_prefix string
---@field highlight string
---@field virt_text_pos string
---@field input meister.InputConfig

---@class meister.SendConfig
---@field header string
---@field template? string|fun(parts: string[]): string
---@field clear_after_send boolean

---@class meister.Config
---@field provider string|meister.Provider
---@field annotate meister.AnnotateConfig
---@field send meister.SendConfig

---@type meister.Config
local defaults = {
	provider = "opencode",
	annotate = {
		virt_text_prefix = "  ",
		highlight = "Comment",
		virt_text_pos = "eol",
		input = {
			accent_hl = "MeisterInputAccent",
			border_hl = "MeisterInputAccent",
			bar = "▎",
			margin = 1,
			placeholder = "message",
		},
	},
	send = {
		header = "Review notes:",
		template = nil,
		clear_after_send = true,
	},
}

---@type meister.Config
M.options = vim.deepcopy(defaults)

local function validate()
	local o = M.options
	vim.validate("provider", o.provider, { "string", "table" })
	vim.validate("annotate", o.annotate, "table")
	vim.validate("send", o.send, "table")
end

---@param opts? meister.Config
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	validate()
end

return M
