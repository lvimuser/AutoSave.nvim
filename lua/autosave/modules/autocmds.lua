local fn = vim.fn

local opts = require("autosave.config").options
local autosave = require("autosave")
local utils = require("autosave/utils.utils")

-- TODO Remove after nvim 0.10 release
local get_clients = vim.lsp.get_active_clients or vim.lsp.get_clients

local M = {}

local function clear_cmdline()
	if vim.api.nvim_get_mode().mode ~= "c" then
		vim.cmd.echon()
	end
end

local message = function()
	local msg = opts.execution_message
	msg = type(msg) == "function" and msg() or msg

	if msg then
		print(msg)

		_ = opts.clean_command_line_interval > 0
			and vim.defer_fn(clear_cmdline, opts.clean_command_line_interval)
	end
end

local function actual_save()
	local first_char_pos = fn.getpos("'[")
	local last_char_pos = fn.getpos("']")

	if opts.write_all_buffers then
		vim.cmd("silent! write all")
	else
		vim.cmd("silent! write")
	end

	fn.setpos("'[", first_char_pos)
	fn.setpos("']", last_char_pos)

	message()
end

local function assert_user_conditions()
	local conditions = opts.conditions
	if conditions.exists then
		if fn.filereadable(fn.expand("%:p")) == 0 then
			return false
		end
	end

	if conditions.modifiable and not vim.bo.modifiable then
		return false
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
		local path = fn.expand("%:p") --[[@as string]]
		local home_dir = fn.expand("$HOME") --[[@as string]]
		if not path:find(home_dir, 1, true) then
			return false
		end
	end

	return true
end

---@param client lsp.Client
local pending_request = function(client, bufnr)
	local ms = vim.lsp.protocol.Methods
	for _, request in pairs(client.requests or {}) do
		if
			request.type == "pending"
			and request.bufnr == bufnr
			and (
				request.method:match(ms.workspace_executeCommand)
				or request.method:match(ms.textDocument_formatting)
				or request.method:match(ms.textDocument_rangeFormatting)
				or request.method:match(ms.textDocument_rename)
			)
		then
			return request.method
		end
	end
end

local changedtick
function M.save()
	local cur_tick = vim.api.nvim_buf_get_changedtick(0)
	if changedtick == cur_tick then
		return
	end

	if vim.bo.readonly or not vim.bo.modified then
		return
	end

	if not assert_user_conditions() then
		return
	end

	if autosave.hook_before_saving then
		autosave.hook_before_saving()
	end

	if vim.api.nvim_get_mode()["mode"] ~= "n" then
		-- do not save on insert mode
		vim.g.auto_save_abort = true
	elseif vim.b.visual_multi then
		vim.g.auto_save_abort = true
	elseif
		package.loaded["luasnip"]
		and require("luasnip.session").current_nodes[vim.api.nvim_get_current_buf()]
	then
		-- do not save when we have an active snippet; messes up extmarks and breaks jumps
		vim.g.auto_save_abort = true
	else
		local bufnr = vim.api.nvim_get_current_buf()
		-- pending lsp requests
		for _, client in pairs(get_clients({ bufrn = bufnr })) do
			local r = pending_request(client, bufnr)
			if r then
				vim.notify(string.format("Aborted autosave due to pending LSP request: %s ", r))
				vim.g.auto_save_abort = true
				break
			end
		end
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

local timer
function M.load_autocommands()
	if opts.debounce_delay == 0 then
		M.debounced_save = M.save
		M.abort = function() end
	else
		timer, M.debounced_save = utils.debounce(M.save, opts.debounce_delay)
		M.abort = function()
			_ = timer and timer:stop()
		end
	end

	if opts.debounce_delay ~= 0 then
		vim.api.nvim_create_autocmd(opts.abort_events, {
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

		vim.api.nvim_create_autocmd({ "FocusLost", "TabLeave", "WinLeave", "BufLeave" }, {
			group = vim.api.nvim_create_augroup("autosave_focus_change", {}),
			pattern = "*",
			callback = focus_save,
			desc = "autosave_focus_save",
		})
	end

	vim.api.nvim_create_autocmd(opts.events, {
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
