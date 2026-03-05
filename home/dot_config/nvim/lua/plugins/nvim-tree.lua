local present, nvim_tree = pcall(require, "nvim-tree")

if not present then
  return
end

nvim_tree.setup {
  view = {
    width = 25,
    side = "right",
  },
  disable_netrw = true,
  hijack_cursor = true,
  sync_root_with_cwd = true,
  filesystem_watchers = {
    enable = true,
    debounce_delay = 100,
    ignore_dirs = {},
  },
  renderer = {
    root_folder_label = false,
    indent_markers = {
      enable = true,
    },
    icons = {
      web_devicons = {
        file = { color = false },
      },
      show = {
        file = false,
        folder = true,
        folder_arrow = false,
        git = true,
      },
    },
  },
  hijack_directories = {
    enable = true,
    auto_open = true,
  },
  git = {
    enable = true,
    ignore = false,
    timeout = 400,
  },
}
