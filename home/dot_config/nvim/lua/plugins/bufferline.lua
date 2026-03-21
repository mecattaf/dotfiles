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
      fg = "#000000",
      bg = "#000000",
    },
    background = {
      fg = "#45475a",
      bg = "#000000",
    },

    -- buffers
    buffer_selected = {
      fg = "#EAECF0",
      bg = "#000000",
      italic = false,
    },
    buffer_visible = {
      fg = "#45475a",
      bg = "#000000",
    },

    -- close buttons
    close_button = {
      fg = "#45475a",
      bg = "#000000",
    },
    close_button_visible = {
      fg = "#45475a",
      bg = "#000000",
    },
    close_button_selected = {
      fg = "#F47B85",
      bg = "#000000",
    },

    indicator_selected = {
      fg = "#000000",
      bg = "#000000",
    },

    -- modified
    modified = {
      fg = "#45475a",
      bg = "#000000",
    },
    modified_visible = {
      fg = "#000000",
      bg = "#000000",
    },
    modified_selected = {
      fg = "#9BE963",
      bg = "#000000",
    },

    -- tabs
    tab_close = {
      fg = "#000000",
      bg = "#000000",
    },
  },
}
