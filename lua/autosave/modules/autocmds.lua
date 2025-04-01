local opts = require("autosave.config").options
local autosave = require("autosave")
local utils = require("autosave/utils.utils")

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

---@param bufnr integer
local function actual_save(bufnr)
	vim._with({ buf = bufnr }, function()
		if opts.write_all_buffers then
			vim.cmd("lockmarks silent! write all")
		else
			vim.cmd("lockmarks silent! write")
		end

		message()
	end)
end

local function assert_user_conditions(bufnr)
	local conditions = opts.conditions

	if conditions.modifiable and not vim.bo[bufnr].modifiable then
		return false
	end

	if conditions.exists then
		if
			vim._with({ buf = bufnr }, function()
				return vim.fn.filereadable(vim.fn.expand("%:p"))
			end) == 0
		then
			return false
		end
	end

	if conditions.filename_is_not and #conditions.filename_is_not > 0 then
		local filename = vim._with({ buf = bufnr }, function()
			return vim.fn.expand("%:t")
		end)

		if vim.tbl_contains(conditions.filename_is_not, filename) then
			return false
		end
	end

	if conditions.filetype_is_not and #conditions.filetype_is_not > 0 then
		local filetype = vim.bo[bufnr].filetype
		if vim.tbl_contains(conditions.filetype_is_not, filetype) then
			return false
		end
	end

	if opts.conditions.restrict_to_home_dirs then
		local found = vim._with({ buf = bufnr }, function()
			local path = vim.fn.expand("%:p") --[[@as string]]
			local home_dir = vim.fn.expand("$HOME") --[[@as string]]
			return path:find(home_dir, 1, true)
		end)

		if not found then
			return false
		end
	end

	return true
end

---@param client vim.lsp.Client
local pending_request = function(client, bufnr)
	local ms = vim.lsp.protocol.Methods
	for _, request in pairs(client.requests or {}) do
		if
			request.type == "pending"
			and request.bufnr == bufnr
			and (
				request.method:match(ms.workspace_executeCommand)
				or request.method:match(ms.workspace_applyEdit)
				or request.method:match(ms.textDocument_formatting)
				or request.method:match(ms.textDocument_rangeFormatting)
				or request.method:match(ms.textDocument_rename)
			)
		then
			return request.method
		end
	end
end

local changedtick = {}

function M.save(bufnr)
	bufnr = vim._resolve_bufnr(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local cur_tick = vim.api.nvim_buf_get_changedtick(bufnr)
	if changedtick[bufnr] == cur_tick then
		return
	end

	if vim.bo[bufnr].readonly or not vim.bo[bufnr].modified then
		return
	end

	if vim.bo[bufnr].buftype ~= "" then
		return
	end

	if not assert_user_conditions(bufnr) then
		return
	end

	if autosave.hook_before_saving then
		autosave.hook_before_saving()
	end

	-- TODO scope auto_save_abort per buffer
	if vim.api.nvim_get_mode()["mode"] ~= "n" then
		-- do not save on insert mode
		vim.g.auto_save_abort = true
	elseif vim.fn.state("oS") ~= "" then
		-- do not save when in operator pending mode or not SafeState
		vim.g.auto_save_abort = true
	elseif vim.b.visual_multi then
		vim.g.auto_save_abort = true
	elseif package.loaded["luasnip"] and require("luasnip.session").current_nodes[bufnr] then
		-- do not save when we have an active snippet; messes up extmarks and breaks jumps
		vim.g.auto_save_abort = true
	else
		-- pending lsp requests
		for _, client in pairs(vim.lsp.get_clients({ bufrn = bufnr })) do
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

	actual_save(bufnr)

	if autosave.hook_after_saving then
		autosave.hook_after_saving()
	end

	changedtick[bufnr] = vim.api.nvim_buf_get_changedtick(bufnr)
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
		local group = vim.api.nvim_create_augroup("autosave_abort", {})
		vim.api.nvim_create_autocmd(opts.abort_events, {
			group = group,
			pattern = "*",
			callback = M.abort,
			desc = "autosave_abort",
		})

		vim.api.nvim_create_autocmd("FileType", {
			group = group,
			pattern = { "TelescopePrompt", "DressingInput" },
			callback = function()
				M.abort()
			end,
			desc = "autosave_abort",
		})
	end

	if opts.on_focus_change then
		local focus_save = utils.leading_debounce(M.save, 100)

		-- vim.api.nvim_create_autocmd({ "FocusLost", "TabLeave", "WinLeave" }, {
		-- we should save all open buffers in curernt tabpage on FocusLost
		vim.api.nvim_create_autocmd({ "FocusLost" }, {
			group = vim.api.nvim_create_augroup("autosave_focus_change", {}),
			pattern = "*",
			callback = function(args)
				focus_save(args.buf)
			end,
			desc = "autosave_focus_save",
		})
	end

	vim.api.nvim_create_autocmd(opts.events, {
		group = vim.api.nvim_create_augroup("autosave_save", {}),
		pattern = "*",
		callback = function(args)
			M.debounced_save(args.buf)
		end,
		desc = "autosave_save",
	})
end

-- TODO scope timer per buffer?
-- BufDelete or BufUnload
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
