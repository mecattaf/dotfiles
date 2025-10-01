local ok, bufferline = pcall(require, "bufferline")
if not ok then
  return
end

bufferline.setup {
  options = {
    offsets = { { filetype = "NvimTree", text = "Explorer", highlight = "Normal"  } },
    separator_style = { "", ""},
    show_tab_indicators = false,
  },
  highlights = {
    fill = {
      fg = "#1e1e2e",
      bg = "#1e1e2e",
    },
    background = {
      fg = "#45475a",
      bg = "#1e1e2e",
    },

    -- buffers
    buffer_selected = {
      fg = "#cdd6f4",
      bg = "#1e1e2e",
      italic = false,
    },
    buffer_visible = {
      fg = "#45475a",
      bg = "#1e1e2e",
    },

    -- close buttons
    close_button = {
      fg = "#45475a",
      bg = "#1e1e2e",
    },
    close_button_visible = {
      fg = "#45475a",
      bg = "#1e1e2e",
    },
    close_button_selected = {
      fg = "#f38ba8",
      bg = "#1e1e2e",
    },

    indicator_selected = {
      fg = "#1e1e2e",
      bg = "#1e1e2e",
    },

    -- modified
    modified = {
      fg = "#45475a",
      bg = "#1e1e2e",
    },
    modified_visible = {
      fg = "#1e1e2e",
      bg = "#1e1e2e",
    },
    modified_selected = {
      fg = "#a6e3a1",
      bg = "#1e1e2e",
    },

    -- tabs
    tab_close = {
      fg = "#1e1e2e",
      bg = "#1e1e2e",
    },
  },
}
