-- The file tree only chooses a path. Kitty owns the dock, window focus and
-- durable editor launch; the tree creates no sessions or multiplexed panes.
local M = {}

function M.emit(directory, path)
  for _, value in ipairs({ directory, path }) do
    assert(type(value) == 'string' and value:sub(1, 1) == '/' and #value <= 4096
      and not value:find('[%z\1-\31\127]') and value == vim.fs.normalize(value), 'invalid editor selection path')
  end
  assert(directory == vim.uv.fs_realpath(directory), 'editor root must be canonical')
  local json = vim.json.encode({ directory = directory, path = path })
  vim.api.nvim_ui_send('\027]1337;SetUserVar=agency_editor_pick=' .. vim.base64.encode(json) .. '\027\\')
end

function M.setup()
  local root = assert(vim.env.DSH_EDITOR_TREE_ROOT, 'DSH_EDITOR_TREE_ROOT is required')
  local ok, tree = pcall(require, 'nvim-tree')
  if not ok then
    vim.api.nvim_err_writeln('dsh-editor-tree: nvim-tree is not installed in this Nvim config')
    vim.cmd('cquit')
    return
  end
  local api = require('nvim-tree.api')
  local function choose()
    local node = api.tree.get_node_under_cursor()
    if not node or not node.absolute_path then return end
    local info = vim.uv.fs_stat(node.absolute_path)
    if info and info.type == 'directory' then
      api.node.open.edit()
      return
    end
    M.emit(root, node.absolute_path)
    vim.cmd('qall!')
  end
  tree.setup({
    view = { width = 28, side = 'left' },
    on_attach = function(buf)
      api.config.mappings.default_on_attach(buf)
      for _, key in ipairs({ '<CR>', 'o', 'l', '<2-LeftMouse>' }) do
        vim.keymap.set('n', key, choose, { buffer = buf, nowait = true, silent = true })
      end
      vim.keymap.set('n', 'q', '<cmd>qall!<cr>', { buffer = buf, nowait = true, silent = true })
    end,
  })
  api.tree.open({ path = root, focus = true })
  vim.schedule(function()
    -- The dock is already a narrow independent terminal window. Let the tree
    -- fill it instead of retaining Nvim's initial empty editor split.
    for _, window in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(window)].filetype ~= 'NvimTree' then
        pcall(vim.api.nvim_win_close, window, true)
      end
    end
  end)
end

return M
