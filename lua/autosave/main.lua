local autocmds = require("autosave.modules.autocmds")
local autosave = require("autosave")
local M = {}

local function on()
	if autosave.hook_before_on ~= nil then
		autosave.hook_before_on()
	end

	autocmds.load_autocommands()
	vim.g.autosave_state = true

	if autosave.hook_after_on ~= nil then
		autosave.hook_after_on()
	end
end

local function off()
	if autosave.hook_before_off ~= nil then
		autosave.hook_before_off()
	end

	autocmds.unload_autocommands()
	vim.g.autosave_state = false

	if autosave.hook_after_off ~= nil then
		autosave.hook_after_off()
	end
end

M.off = off
M.on = on
M.toggle = function()
	_ = vim.g.autosave_state == true and off() or on()
end

return M
