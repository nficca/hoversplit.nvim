local M = {}

local config = require("hoversplit.config")

M.hover_bufnr = nil ---@type integer|nil
M.hover_winid = nil ---@type integer|nil
M.orig_winid = nil ---@type integer|nil
M.orig_bufnr = nil ---@type integer|nil
M.orig_win_height = nil ---@type integer|nil
M.is_vertical = nil ---@type boolean|nil

---Resize a window while keeping the viewport stable (horizontal splits only)
---@param winid integer
---@param height integer
local function stabilized_resize(winid, height)
	if M.is_vertical then
		return
	end
	if not config.options.stabilize_on_resize then
		vim.api.nvim_win_set_height(winid, height)
		return
	end
	-- Save view state (cursor + scroll position) in the original window
	local view = nil
	if M.orig_winid and vim.api.nvim_win_is_valid(M.orig_winid) then
		view = vim.api.nvim_win_call(M.orig_winid, function()
			return vim.fn.winsaveview()
		end)
	end
	vim.api.nvim_win_set_height(winid, height)
	-- Restore view state
	if view and M.orig_winid and vim.api.nvim_win_is_valid(M.orig_winid) then
		vim.api.nvim_win_call(M.orig_winid, function()
			vim.fn.winrestview(view)
		end)
	end
end

---@param bufnr? integer
---@return boolean
function M.check_hover_support(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if bufnr == M.hover_bufnr then
		return false
	end

	-- Check if there are any available LSP clients that support hovering
	local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/hover" })
	return not vim.tbl_isempty(clients)
end

function M.update_hover_content()
	if not (M.hover_winid and vim.api.nvim_win_is_valid(M.hover_winid)) then
		return
	end

	-- Check the current buffer and cursor position
	local bufnr = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()
	local cursor_pos = vim.api.nvim_win_get_cursor(win)
	local row, col = cursor_pos[1], cursor_pos[2]
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local current_line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""

	-- Validate the cursor position
	if row < 1 or row > line_count or col < 0 or col > current_line:len() then
		vim.notify("Invalid cursor position detected. Skipping hover content update.", vim.log.levels.WARN)
		return
	end

	vim.lsp.buf_request(
		bufnr,
		"textDocument/hover",
		vim.lsp.util.make_position_params(win, "utf-16"),
		function(err, result)
			if err or not (result and result.contents) then
				return
			end

			local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
			vim.bo[M.hover_bufnr].modifiable = true
			vim.api.nvim_buf_set_lines(M.hover_bufnr, 0, -1, false, lines)

			local max_height = config.options.max_hover_height
			if not max_height and M.orig_win_height then
				max_height = math.floor(M.orig_win_height / 2)
			end
			local height = max_height and math.min(#lines, max_height) or #lines
			stabilized_resize(M.hover_winid, height)
			vim.bo[M.hover_bufnr].modifiable = false
		end
	)
end

---@param vertical boolean
---@param remain_focused boolean
function M.create_hover_split(vertical, remain_focused)
	if M.hover_winid and vim.api.nvim_win_is_valid(M.hover_winid) then
		M.close_hover_split()
		return
	end

	M.remain_focused = remain_focused
	M.is_vertical = vertical
	M.orig_bufnr = vim.api.nvim_get_current_buf()
	M.orig_winid = vim.api.nvim_get_current_win()
	M.orig_pos = vim.api.nvim_win_get_cursor(M.orig_winid)
	M.orig_win_height = vim.api.nvim_win_get_height(M.orig_winid)
	M.hover_bufnr = vim.api.nvim_create_buf(false, true)

	local augroup = vim.api.nvim_create_augroup("HoverSplit", { clear = true })
	vim.api.nvim_create_autocmd("BufEnter", {
		group = augroup,
		callback = function(ev)
			if ev.buf == M.hover_bufnr then
				vim.keymap.set("n", "q", M.close_hover_split, {
					noremap = true,
					silent = true,
					buffer = ev.buf,
				})
				return
			end

			if ev.buf ~= M.orig_bufnr then
				return
			end
			if not (M.orig_winid and vim.api.nvim_win_is_valid(M.orig_winid)) then
				M.orig_winid = nil
				return
			end

			if not M.remain_focused then
				vim.api.nvim_win_set_cursor(M.orig_winid, M.orig_pos)
			end
		end,
	})

	---@type vim.api.keyset.win_config
	local win_opts = { focusable = true, vertical = vertical, style = "minimal" }
	if vertical then
		local win_width = vim.api.nvim_win_get_width(M.orig_winid)
	  	local orig_textwidth = vim.api.nvim_get_option_value(
	  		"textwidth",
	  		{ buf = M.orig_bufnr }
	  	)
	  	local orig_textoff = vim.fn.getwininfo(M.orig_winid)[1].textoff
		local padding = 1
		local minimum = 12
		local maximum = win_width / 2
		local raw_width = win_width - (orig_textwidth + orig_textoff + padding)
		local width = math.min(math.max(raw_width, minimum), maximum)

		win_opts.split = "right"
		win_opts.width = math.floor(width)
	else
		local win_height = vim.api.nvim_win_get_height(M.orig_winid)

		win_opts.split = config.options.split_position
		win_opts.height = math.floor(win_height / 3)
	end

	local conceallevel = config.conceallevel or 3
	conceallevel = vim.list_contains({ 0, 1, 2, 3 }, conceallevel) and conceallevel or 3
	M.hover_winid = vim.api.nvim_open_win(M.hover_bufnr, M.remain_focused, win_opts)
	vim.api.nvim_win_set_buf(M.hover_winid, M.hover_bufnr)
	vim.api.nvim_buf_set_name(M.hover_bufnr, "hoversplit")
	vim.bo[M.hover_bufnr].bufhidden = "wipe"
	vim.bo[M.hover_bufnr].modifiable = false
	vim.bo[M.hover_bufnr].buftype = "nowrite"
	vim.bo[M.hover_bufnr].filetype = "markdown"
	vim.b[M.hover_bufnr].is_lsp_hover_split = true
	vim.wo[M.hover_winid].wrap = true
	vim.wo[M.hover_winid].conceallevel = conceallevel

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = augroup,
		callback = function(args)
			if args.buf ~= M.hover_bufnr then
				if M.check_hover_support(args.buf) then
					M.update_hover_content()
				end
			end
		end,
	})

	if vim.api.nvim_get_current_win() ~= M.hover_winid then
		M.update_hover_content()
	end
end

function M.split()
	M.create_hover_split(false, true) -- reversed the logic, now true
end

function M.vsplit()
	M.create_hover_split(true, true) -- reversed the logic, now true
end

function M.split_remain_focused()
	M.create_hover_split(false, false) -- reversed the logic, now false
end

function M.vsplit_remain_focused()
	M.create_hover_split(true, false) -- reversed the logic, now false
end

function M.close_hover_split()
	if M.hover_bufnr and vim.api.nvim_buf_is_valid(M.hover_bufnr) then
		vim.api.nvim_buf_delete(M.hover_bufnr, { force = true })
		M.hover_bufnr = nil
		M.hover_winid = nil
		M.orig_win_height = nil
		M.is_vertical = nil
	end
end

function M.setup(options)
	options = options or {}
	config.options = vim.tbl_deep_extend("force", config.options, options)

	if config.options.key_bindings_disabled then
		return
	end

	vim.keymap.set(
		"n",
		config.options.key_bindings.split_remain_focused,
		M.split_remain_focused,
		{ noremap = true, silent = true, desc = "HoverSplit split (Remain Focused)" }
	)

	vim.keymap.set(
		"n",
		config.options.key_bindings.vsplit_remain_focused,
		M.vsplit_remain_focused,
		{ noremap = true, silent = true, desc = "HoverSplit vsplit (Remain Focused)" }
	)

	vim.keymap.set(
		"n",
		config.options.key_bindings.split,
		M.split,
		{ noremap = true, silent = true, desc = "HoverSplit split" }
	)

	vim.keymap.set(
		"n",
		config.options.key_bindings.vsplit,
		M.vsplit,
		{ noremap = true, silent = true, desc = "HoverSplit vsplit" }
	)
end

return M
-- vim:ts=4:sts=4:noet:ai:si:sta:
