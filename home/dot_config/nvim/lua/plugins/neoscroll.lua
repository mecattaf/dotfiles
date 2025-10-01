local present, neoscroll = pcall(require, "neoscroll")

if not present then
  return
end

neoscroll.setup({
  -- Disable all default mappings - we'll handle them in mappings.lua
  mappings = {},
  hide_cursor = true,          -- Hide cursor while scrolling for clean look
  stop_eof = true,             -- Stop at end of file
  respect_scrolloff = false,   -- Don't stop at scrolloff margin
  cursor_scrolls_alone = true, -- Cursor keeps scrolling even if window can't
  duration_multiplier = 0.7,   -- Slightly faster than default
  easing = 'sine',             -- Smooth easing for natural feel
  performance_mode = false,    -- Keep syntax highlighting
})
