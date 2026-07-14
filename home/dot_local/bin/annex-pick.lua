-- annex-pick.lua — Ctrl+B sidebar picker payload (dotfiles#50).
--
-- Runs inside the hidden annex nvim (zmx-backed, coordinator-resident). Opens
-- nvim-tree (Tom's own 25-col file bar) as the selector, filling the narrow
-- annex, and overrides <CR>/o in the tree buffer to:
--   * a directory -> expand/collapse (default),
--   * a file      -> write its absolute path to $ANNEX_PICK, then :qa!.
-- On :qa! the nvim exits, the zmx session self-reaps, the split collapses, and
-- the kitty window watcher (annex_watcher.py) reads $ANNEX_PICK and opens the
-- chosen file in a NEW niri window (durable edit = real window, ruling 4).
-- Pure filesystem signaling: no fifo, no polling. Plain :q leaves the pick file
-- absent/empty -> a dismiss (watcher reaps, opens nothing).
--
-- Lives in ~/.local/bin (a live whole-dir symlink) and is `luafile`'d at launch
-- rather than added to ~/.config/nvim/lua — the latter is an explicit
-- enumerated list in nvim.nix and would force a nixos-rebuild. This keeps the
-- whole feature zero-rebuild.

local ok, api = pcall(require, "nvim-tree.api")
if not ok then
  vim.cmd("qa!")
  return
end

local pick = vim.env.ANNEX_PICK or ""

local function choose()
  local node = api.tree.get_node_under_cursor()
  if not node then
    return
  end
  if node.type == "directory" then
    -- Expand/collapse the directory; do not signal.
    api.node.open.edit()
    return
  end
  -- File (or a symlink to one): signal the path and quit the annex.
  if pick ~= "" and node.absolute_path then
    pcall(vim.fn.writefile, { node.absolute_path }, pick)
  end
  vim.cmd("qa!")
end

-- Attach the overrides whenever the tree buffer materializes (register BEFORE
-- opening the tree so the FileType event is not missed). CRUCIAL: nvim-tree
-- applies its OWN default buffer-local <CR>/o mappings via on_attach when the
-- buffer is created, and that can run AFTER this FileType callback — clobbering
-- our override so <CR> falls back to nvim-tree's "open file in a window"
-- (the file opens INSIDE the annex instead of signaling + detaching, the exact
-- symptom seen 2026-07-15). vim.schedule defers our set() to the next tick, so it
-- lands AFTER nvim-tree's defaults and wins deterministically.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "NvimTree",
  callback = function(ev)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(ev.buf) then
        return
      end
      local o = { buffer = ev.buf, nowait = true, silent = true }
      vim.keymap.set("n", "<CR>", choose, o)
      vim.keymap.set("n", "o", choose, o)
      vim.keymap.set("n", "l", choose, o)
      vim.keymap.set("n", "<2-LeftMouse>", choose, o)
    end)
  end,
})

api.tree.open({ focus = true })

-- Make the tree fill the ~25-col annex: drop the initial empty scratch window
-- so only the tree remains. (nvim-tree no longer auto-closes when it is the
-- last window, so this is safe.)
vim.schedule(function()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype ~= "NvimTree" then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end)
