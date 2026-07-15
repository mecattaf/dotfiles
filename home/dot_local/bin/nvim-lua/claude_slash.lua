-- claude_slash.lua — blink.cmp source: '/'-completion for Claude Code slash
-- commands & skills (Claude Code style, sibling of filemention's '@'-mention
-- source). Lives outside the Nix-rendered nvim/ tree so this LOGIC is
-- live-editable with no rebuild — the same whole-dir-symlink trick as
-- ~/.local/bin/annex-pick.lua (see home.nix's `home.file.".local/bin"` and
-- the one `package.path` line added in plugins.lua.in for require()
-- resolution). Only that one path line ever needs a rebuild; everything
-- below reloads on the next nvim launch, always.
--
-- Data source: ~/.cache/claude-slash/palette.json, produced by the
-- claude-slash-enum CLI (~/.local/bin/claude-slash-enum) — {"ts", "commands":
-- [{"name","kind","description"}, ...]}. Read fully asynchronously via
-- vim.uv (libuv), once in source.new() and again on every fs_event change to
-- the cache file, so get_completions() itself never touches disk and never
-- blocks the UI thread.
--
--- @module 'blink.cmp'
--- @class blink.cmp.Source
local source = {}

local CACHE_PATH = vim.env.HOME .. "/.cache/claude-slash/palette.json"
local ENUM_CMD = vim.env.HOME .. "/.local/bin/claude-slash-enum"

-- Same filetype gate as filemention.nvim's built-in default (config.lua:
-- markdown/text/gitcommit, minus gitrebase/mdx/norg — this source only needs
-- to match the gate the task specified).
local FILETYPES = { markdown = true, text = true, gitcommit = true }

function source.new(_)
  local self = setmetatable({}, { __index = source })
  self.items = {}
  self.kicked_refresh = false
  self:reload()
  self:watch()
  return self
end

function source:enabled()
  return FILETYPES[vim.bo.filetype] == true
end

function source:get_trigger_characters()
  return { "/" }
end

-- Trigger only at line-start or after whitespace — unlike '@' (where a
-- mid-word hit is rare/acceptable), '/' shows up constantly inside prose
-- ("and/or", dates, paths), so this guard is load-bearing, not cosmetic.
function source:get_completions(ctx, callback)
  local col = ctx.cursor[2]
  local before = ctx.line:sub(1, col)
  local at_pos = before:find("/[%w_-]*$")
  local ok = at_pos and (at_pos == 1 or before:sub(at_pos - 1, at_pos - 1):match("%s"))
  if not ok then
    return callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
  end
  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = self.items })
end

function source:execute(_, _, callback, default_implementation)
  default_implementation()
  callback()
end

-- Kick a one-shot background refresh (detached, fire-and-forget) the first
-- time this session finds no cache at all. Never blocks; never retried more
-- than once per nvim session (claude-slash-enum itself is TTL-guarded, so a
-- repeat kick would just no-op anyway, but there's no reason to spawn it
-- more than once here).
function source:kick_refresh()
  if self.kicked_refresh then
    return
  end
  self.kicked_refresh = true
  if vim.uv.fs_stat(ENUM_CMD) then
    vim.system({ ENUM_CMD, "--quiet" }, { detach = true }, function() end)
  end
end

function source:reload()
  vim.uv.fs_open(CACHE_PATH, "r", 438, function(open_err, fd)
    if open_err or not fd then
      vim.schedule(function() self:kick_refresh() end)
      return
    end
    vim.uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err or not stat then
        vim.uv.fs_close(fd, function() end)
        return
      end
      vim.uv.fs_read(fd, stat.size, 0, function(_, data)
        vim.uv.fs_close(fd, function() end)
        local ok, decoded = pcall(vim.json.decode, data or "")
        if not ok or type(decoded) ~= "table" or type(decoded.commands) ~= "table" then
          return
        end
        vim.schedule(function()
          local items = {}
          for i, entry in ipairs(decoded.commands) do
            if entry.name then
              local desc = entry.description
              if desc == "" then desc = nil end
              items[#items + 1] = {
                label = "/" .. entry.name,
                insertText = "/" .. entry.name .. " ",
                labelDetails = entry.kind and { description = entry.kind } or nil,
                documentation = desc and { kind = "markdown", value = desc } or nil,
                kind = vim.lsp.protocol.CompletionItemKind.Snippet,
                sortText = string.format("%06d", i),
              }
            end
          end
          self.items = items
        end)
      end)
    end)
  end)
end

-- Live-reload when the palette changes (e.g. after a manual `claude-slash-enum
-- --refresh`) without ever restarting nvim. Watching the parent dir (not the
-- file itself) survives the enum script's atomic tmp-then-rename write.
function source:watch()
  local dir = vim.env.HOME .. "/.cache/claude-slash"
  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end
  local ok = pcall(handle.start, handle, dir, {}, function(err, filename)
    if err then
      return
    end
    if filename == nil or filename == "palette.json" then
      vim.schedule(function() self:reload() end)
    end
  end)
  if not ok then
    pcall(handle.close, handle)
  end
end

return source
