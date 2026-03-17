local M = {}

M.options = {
	conceallevel = 3,
	key_bindings_disabled = false,
	key_bindings = {
		split = "<leader>hS",
		vsplit = "<leader>hV",
		split_remain_focused = "<leader>hs",
		vsplit_remain_focused = "<leader>hv",
	},
	target_height_ratio = 0.2, -- target height as a fraction of window height
	max_height = 16,          -- maximum height in lines for horizontal splits
	target_width_ratio = "auto", -- target width as a fraction of window width, or "auto" for textwidth-based sizing
	max_width = 80,           -- maximum width in columns for vertical splits
	stabilize_on_resize = true, -- prevent viewport jolt when hover window resizes
	split_position = "above", -- "above" or "below" for horizontal splits
}

return M
-- vim:ts=4:sts=4:noet:ai:si:sta:
