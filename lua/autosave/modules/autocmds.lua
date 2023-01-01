---@diagnostic disable: undefined-field
local fn = vim.fn

local opts = require("autosave.config").options
local autosave = require("autosave")
local utils = require("autosave/utils.utils")

local default_events = { "InsertLeave", "TextChanged" }
local default_abort_events = { "TextChanged", "InsertEnter" }
local on_focus_change_events = { "FocusLost", "TabLeave", "WinLeave" }

local modified

local M = {}

local function actual_save()
	local first_char_pos = fn.getpos("'[")
	local last_char_pos = fn.getpos("']")

	if opts["write_all_buffers"] then
		vim.cmd("silent! write all")
	else
		vim.cmd("silent! write")
	end

	fn.setpos("'[", first_char_pos)
	fn.setpos("']", last_char_pos)

	if not modified then
		modified = true
	end

	M.message_and_interval()
end

local function assert_user_conditions()
	local conditions = opts.conditions
	if conditions.exists then
		if fn.filereadable(fn.expand("%:p")) == 0 then
			return false
		end
	end

	if conditions.modifiable then
		if vim.api.nvim_eval([[&modifiable]]) == 0 then
			return false
		end
	end

	if conditions.filename_is_not and #conditions.filename_is_not > 0 then
		local filename = fn.expand("%:t")
		if vim.tbl_contains(conditions.filename_is_not, filename) then
			return false
		end
	end

	if conditions.filetype_is_not and #conditions.filetype_is_not > 0 then
		local filetype = vim.api.nvim_eval([[&filetype]])
		if vim.tbl_contains(conditions.filetype_is_not, filetype) then
			return false
		end
	end

	if opts.conditions.restrict_to_home_dirs then
		local path = fn.expand("%:p")
		local home_dir = fn.expand("$HOME")
		if not path:find(home_dir, 1, true) then
			return false
		end
	end

	return true
end

function M.message_and_interval()
	if modified then
		modified = false
		local execution_message = opts["execution_message"]
		if execution_message ~= "" then
			print(
				type(execution_message) == "function" and execution_message() or execution_message
			)
		end

		if opts["clean_command_line_interval"] > 0 then
			vim.cmd(
				[[call timer_start(]]
					.. opts["clean_command_line_interval"]
					.. [[, funcref('g:AutoSaveClearCommandLine'))]]
			)
		end
	end
end

local changedtick = vim.api.nvim_buf_get_changedtick(0)
function M.save()
	local cur_tick = vim.api.nvim_buf_get_changedtick(0)
	if changedtick == cur_tick then
		return
	end

	if vim.bo.readonly or not (vim.bo.modified and assert_user_conditions()) then
		return
	end

	if autosave.hook_before_saving then
		autosave.hook_before_saving()
	end

	if vim.g.auto_save_abort then
		vim.g.auto_save_abort = false
		return
	end

	actual_save()

	if autosave.hook_after_saving then
		autosave.hook_after_saving()
	end

	changedtick = vim.api.nvim_buf_get_changedtick(0)
end

local function get_events(events)
	events = events or "events"
	if not opts[events] or vim.tbl_isempty(opts[events]) then
		return events == "events" and default_events
			or events == "abort_events" and default_abort_events
	end
	return opts[events]
end

local timer
function M.load_autocommands()
	if opts["debounce_delay"] == 0 then
		M.debounced_save = M.save
		M.abort = function() end
	else
		timer, M.debounced_save = utils.debounce(M.save, opts["debounce_delay"])
		M.abort = function()
			timer:stop()
		end
	end

	if opts.debounce_delay ~= 0 then
		vim.api.nvim_create_autocmd(get_events("abort_events"), {
			group = vim.api.nvim_create_augroup("autosave_abort", {}),
			pattern = "*",
			callback = M.abort,
			desc = "autosave_abort",
		})
	end

	if opts.on_focus_change then
		local focus_save = utils.leading_debounce(function()
			M.save()
		end, 100)

		vim.api.nvim_create_autocmd(on_focus_change_events, {
			group = vim.api.nvim_create_augroup("autosave_focus_change", {}),
			pattern = "*",
			callback = focus_save,
			desc = "autosave_focus_save",
		})
	end

	vim.api.nvim_create_autocmd(get_events(), {
		group = vim.api.nvim_create_augroup("autosave_save", {}),
		pattern = "*",
		callback = M.debounced_save,
		desc = "autosave_save",
	})
end

function M.unload_autocommands()
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end

	local augroups = { "autosave_abort", "autosave_focus_change", "autosave_save" }
	for _, augroup in ipairs(augroups) do
		pcall(vim.api.nvim_del_augroup_by_name, augroup)
	end
end

return M
