local M = {}

local function setup_load(opts)
	if opts.enabled == true then
		vim.g.autosave_state = true
		require("autosave.main").on()
	else
		vim.g.autosave_state = false
	end
end

local function setup_commands(opts)
	if opts.on_off_commands == true then
		local m = require("autosave.main")

		vim.api.nvim_create_user_command("ASToggle", m.toggle, { force = true })
		vim.api.nvim_create_user_command("ASOn", m.on, { force = true })
		vim.api.nvim_create_user_command("ASOff", m.off, { force = true })
	end
end

function M.setup(custom_opts)
	local opts = require("autosave.config").set_options(custom_opts)

	setup_load(opts)
	setup_commands(opts)
end

return M
