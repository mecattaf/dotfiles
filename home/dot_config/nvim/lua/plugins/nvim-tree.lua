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
  update_cwd = true,
  filesystem_watchers = {
    enable = true,
    debounce_delay = 100,
    ignore_dirs = {},
  },
  modified = {
    enable = true,
    show_on_dirs = true,
    show_on_open_dirs = false,
  },
  renderer = {
    root_folder_label = false,
    highlight_git = "name",
    highlight_modified = "name",
    indent_markers = {
      enable = true,
    },
    icons = {
      webdev_colors = false,
      show = {
        file = false,
        folder = true,
        folder_arrow = false,
        git = true,
        modified = true,
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
