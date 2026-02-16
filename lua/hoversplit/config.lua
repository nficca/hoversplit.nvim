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
	max_hover_height = nil, -- nil = 50% of window, or set explicit line count
	stabilize_on_resize = true, -- prevent viewport jolt when hover window resizes
}

return M
-- vim:ts=4:sts=4:noet:ai:si:sta:
