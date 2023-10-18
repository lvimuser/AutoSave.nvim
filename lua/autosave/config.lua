local config = {}

config.options = {
	enabled = true,
	on_focus_change = true,
	execution_message = "AutoSave: saved at " .. vim.fn.strftime("%H:%M:%S"),
	events = { "InsertLeave", "TextChanged" },
	abort_events = { "InsertEnter" },
	conditions = {
		exists = true,
		modifiable = true,
		restrict_to_home_dirs = true,
		filename_is_not = {},
		filetype_is_not = {
			"neo-tree",
			"help",
			"list",
			"Trouble",
			"terminal",
			"scratch",
			"telescope",
			"log",
			"git",
			"gitcommit",
			"gitrebase",
			"svn",
			"hgcommit",
			"markdown",
			"TelescopePrompt",
			"undotree",
			"neogitstatus",
			"lspinfo",
			"DressingInput",
			"nofile",
			"", -- for all buffers without a file type
		},
	},
	write_all_buffers = false,
	on_off_commands = false,
	clean_command_line_interval = 0,
	debounce_delay = 135,
}

function config.set_options(opts)
	config.options = vim.tbl_deep_extend("force", config.options, opts or {})
	return config.options
end

return config
