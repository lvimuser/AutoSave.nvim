local M = {}

-- Waits until duration has elapsed since the last call
M.debounce = function(fn, duration)
	local timer = vim.loop.new_timer()
	local function inner()
		if timer then
			timer:stop()
			timer:start(duration, 0, vim.schedule_wrap(fn))
		end
	end

	local group = vim.api.nvim_create_augroup("AutoSaveCleanup", {})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		pattern = "*",
		callback = function()
			if timer and timer:has_ref() then
				if not timer:is_closing() then
					timer:close()
				end
				timer = nil
			end
		end,
	})

	return timer, inner
end

-- Waits for duration while blocking any subsequent calls
M.leading_debounce = function(fn, duration)
	local queued = false

	local function inner_debounce()
		if not queued then
			vim.defer_fn(function()
				queued = false
				fn()
			end, duration)
			queued = true
		end
	end

	return inner_debounce
end

return M
