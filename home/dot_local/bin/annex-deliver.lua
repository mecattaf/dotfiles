-- annex-deliver.lua — Option 2 fast-return composer delivery (dotfiles#49
-- follow-up).
--
-- Runs inside the composer nvim that nvim-annex's ANNEX_FAST branch launches
-- (`-c "luafile ...annex-deliver.lua"` on a scratch file seeded with the
-- original draft — nvim-annex has ALREADY returned 0 and truncated the
-- harness's own tempfile by the time this composer is even mapped on screen).
--
-- On an EXPLICIT save (:w/:wq/:x, or the <C-s> convenience keymap below),
-- strips '#'-comment lines from the buffer and ships the remainder to the
-- ORIGINAL harness window via `kitten @ send-text`, wrapped in bracketed-paste
-- markers (ESC[200~ ... ESC[201~) so it lands in the harness's (now-emptied,
-- per nvim-annex's truncate) input box as ONE paste — no per-char
-- reinterpretation, no accidental Enter-submits from embedded newlines, and
-- critically no auto-submit. The composer then quits (:qa!) and its zmx
-- session self-reaps (annex_composer_watcher.py is the backstop for a
-- force-closed window).
--
-- Lives in ~/.local/bin (a live whole-dir symlink) and is `luafile`'d at
-- launch rather than added to ~/.config/nvim/lua — same zero-rebuild
-- convention as annex-pick.lua (that file's own header explains why).
--
-- DELIVERY GATE, mirroring nvim-annex's own mtime contract one layer up: only
-- an explicit write triggers delivery. A bare :q!/crash/interrupt leaves
-- `wrote` false -> nothing sent. There is nothing to "restore" on that path —
-- the harness's input box was already cleared by nvim-annex's truncate step,
-- so a dismissed compose just... stays empty. (A future enhancement could
-- have nvim-annex snapshot-and-restore the seed on a detected dismiss, but
-- that needs its own signal back to the harness and is out of scope here.)
--
-- ZMX-KITTY LOOSE ENDS THIS FILE HAS TO ROUTE AROUND (scout report §3):
--   * `send-text` "always succeeds, even if no text was sent to any window"
--     (kitten @ send-text --help) — it does NOT report failure. So this file
--     never trusts it blindly: it gates delivery on having both a listen_on
--     socket AND a window id threaded in, and additionally gates on the
--     HARNESS's host matching the composer's own host (see below).
--   * #72's abstract-socket-over-ssh gap: `unix:@kitty-{pid}` is host-local
--     and is NOT ssh-forwarded. On a thin client, annex-cmd's ssh branch runs
--     THIS composer nvim on the coordinator while the harness's kitty socket
--     lives on the originating host (zenbook/worker) — send-text physically
--     cannot reach it with today's tooling. The composer's OWN hostname() is
--     therefore useless as a discriminator (it is always "coordinator"); the
--     correct signal is the harness's host, threaded in as KITTY_HARNESS_HOST
--     by nvim-annex (which runs in-place on the harness host). When it differs
--     from the composer's host this file fails safe with a visible notice
--     instead of a silent drop (or a mis-delivery into a same-pid window).

local seed_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local wrote = false

vim.api.nvim_create_autocmd("BufWritePost", {
  buffer = 0,
  callback = function()
    wrote = true
  end,
})

local function strip_comments(lines)
  local out = {}
  for _, l in ipairs(lines) do
    if not l:match("^%s*#") then
      table.insert(out, l)
    end
  end
  return out
end

-- The ONE delivery decision point. VimLeavePre fires synchronously before
-- nvim actually exits, on EVERY quit path (:q, :wq, :x, ZZ, :qa!, the <C-s>
-- keymap below) — unlike BufWritePost+schedule, there is no race against the
-- process exiting before a deferred callback runs.
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    if not wrote then
      return  -- nothing ever saved -> nothing to deliver (dismiss/crash/:q!)
    end

    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local unchanged = table.concat(buf_lines, "\n") == table.concat(seed_lines, "\n")

    local body = strip_comments(buf_lines)
    local joined = table.concat(body, "\n"):gsub("^%s+", ""):gsub("%s+$", "")

    -- Task spec: empty/unchanged buffer -> deliver nothing.
    if unchanged or joined == "" then
      return
    end

    local listen_on = vim.env.KITTY_HARNESS_LISTEN_ON or ""
    local window_id = vim.env.KITTY_HARNESS_WINDOW_ID or ""
    if listen_on == "" or window_id == "" then
      -- No harness handle threaded in (e.g. ANNEX_FAST launched without the
      -- --env plumbing, or KITTY_WINDOW_ID/KITTY_LISTEN_ON were unset in the
      -- harness's own environment) -> fail safe: no-op, no corruption.
      return
    end

    -- Thin-client gate (#72): send-text can only reach the harness kitty when
    -- it lives on the SAME host as this composer nvim. The composer ALWAYS runs
    -- on the coordinator (annex-cmd's ssh branch), so its OWN hostname() can
    -- never distinguish a thin-client harness — we must compare against the
    -- HARNESS's host, threaded in as KITTY_HARNESS_HOST by nvim-annex (which
    -- runs in-place on the harness host). If they differ, the harness's
    -- `unix:@kitty-*` abstract socket is on another machine and is NOT
    -- ssh-forwarded, so send-text physically cannot reach it — fail safe with a
    -- visible notice rather than a silent drop (or, worse, a mis-delivery into
    -- a coincidentally same-pid coordinator window). send-text gives no failure
    -- signal of its own — see header.
    local harness_host = vim.env.KITTY_HARNESS_HOST or ""
    local composer_host = vim.fn.hostname()
    if harness_host == "" or harness_host ~= composer_host then
      pcall(
        vim.notify,
        "annex-deliver: harness on '"
          .. (harness_host == "" and "?" or harness_host)
          .. "', composer on '" .. composer_host
          .. "' — cross-host send-text gap (dotfiles#72), compose NOT delivered",
        vim.log.levels.WARN
      )
      return
    end

    -- Bracketed paste so the harness's input box receives the body as ONE
    -- paste (no per-char reinterpretation, no accidental Enter-submit from an
    -- embedded newline) without auto-submitting. vim.fn.system is
    -- intentionally SYNCHRONOUS/blocking here (not vim.fn.jobstart): we are
    -- inside VimLeavePre and about to exit, so the send-text call must
    -- complete before this process is gone, not be left running async.
    local payload = "\27[200~" .. joined .. "\27[201~"
    vim.fn.system({
      "kitten", "@", "--to", listen_on, "send-text",
      "--match", "id:" .. window_id, "--", payload,
    })
  end,
})

-- Convenience: <C-s> = write + quit in one keystroke (the "save keymap" the
-- design calls out alongside plain :wq). Both paths converge on the single
-- VimLeavePre gate above, so there is exactly one delivery decision.
vim.keymap.set({ "n", "i" }, "<C-s>", "<Esc>:wqa!<CR>", { buffer = 0, silent = true, noremap = true })
