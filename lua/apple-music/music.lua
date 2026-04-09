--- apple-music/music.lua
--- AppleScript bridge: queries Apple Music state via osascript.

local M = {}

-- Cached state so the statusline never blocks on a slow system call.
M._cache = {
  status   = "stopped", -- "playing" | "paused" | "stopped"
  title    = "",
  artist   = "",
  album    = "",
  updated  = 0,
}

local TTL_MS = 5000 -- refresh every 5 seconds

-- ---------------------------------------------------------------------------
-- Internal: run an AppleScript snippet and return trimmed stdout.
-- ---------------------------------------------------------------------------
local function applescript(script)
  local result = vim.fn.system({ "osascript", "-e", script })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

-- ---------------------------------------------------------------------------
-- Internal: fetch fresh data from Apple Music.
-- Returns true on success, false if Music is not running / unavailable.
-- ---------------------------------------------------------------------------
local function fetch()
  -- Check if Music is running first (avoids launching it).
  local running = applescript(
    'tell application "System Events" to (name of processes) contains "Music"'
  )
  if running ~= "true" then
    M._cache.status = "stopped"
    M._cache.title  = ""
    M._cache.artist = ""
    M._cache.album  = ""
    return false
  end

  local state = applescript('tell application "Music" to get player state as string')
  if not state then
    M._cache.status = "stopped"
    return false
  end

  M._cache.status = state  -- "playing" | "paused" | "stopped"

  if state == "playing" or state == "paused" then
    M._cache.title  = applescript('tell application "Music" to get name  of current track') or ""
    M._cache.artist = applescript('tell application "Music" to get artist of current track') or ""
    M._cache.album  = applescript('tell application "Music" to get album  of current track') or ""
  else
    M._cache.title  = ""
    M._cache.artist = ""
    M._cache.album  = ""
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Internal: refresh cache if TTL has expired.
-- ---------------------------------------------------------------------------
local function maybe_refresh()
  local now = vim.uv.now()
  if (now - M._cache.updated) >= TTL_MS then
    fetch()
    M._cache.updated = vim.uv.now()
  end
end

-- ---------------------------------------------------------------------------
-- Public: return a compact "now playing" string for the statusline.
-- Returns "" when nothing is playing or Music is not running.
-- ---------------------------------------------------------------------------
function M.nowplaying()
  maybe_refresh()
  local s = M._cache
  if s.status == "playing" and s.title ~= "" then
    local icon = " "
    local label = s.title
    if s.artist ~= "" then
      label = label .. "  " .. s.artist
    end
    -- Truncate to keep the statusline tidy.
    if #label > 48 then
      label = label:sub(1, 45) .. "…"
    end
    return icon .. label
  elseif s.status == "paused" and s.title ~= "" then
    local icon = " "
    local label = s.title
    if #label > 30 then label = label:sub(1, 27) .. "…" end
    return icon .. label
  end
  return ""
end

-- ---------------------------------------------------------------------------
-- Public: return the raw cache table (title, artist, album, status).
-- ---------------------------------------------------------------------------
function M.state()
  maybe_refresh()
  return vim.deepcopy(M._cache)
end

-- ---------------------------------------------------------------------------
-- Public: force an immediate refresh (bypasses TTL).
-- ---------------------------------------------------------------------------
function M.refresh()
  fetch()
  M._cache.updated = vim.uv.now()
end

-- ---------------------------------------------------------------------------
-- Control commands
-- ---------------------------------------------------------------------------
function M.play_pause()
  applescript('tell application "Music" to playpause')
  vim.defer_fn(M.refresh, 300)
end

function M.next_track()
  applescript('tell application "Music" to next track')
  vim.defer_fn(M.refresh, 300)
end

function M.prev_track()
  applescript('tell application "Music" to previous track')
  vim.defer_fn(M.refresh, 300)
end

-- ---------------------------------------------------------------------------
-- Background timer: keeps the cache warm so statusline reads are instant.
-- ---------------------------------------------------------------------------
local _timer = nil

function M.start_timer()
  if _timer then return end
  _timer = vim.uv.new_timer()
  _timer:start(0, TTL_MS, vim.schedule_wrap(function()
    fetch()
    M._cache.updated = vim.uv.now()
    -- Redraw the statusline without moving the cursor.
    vim.cmd("redrawstatus!")
  end))
end

function M.stop_timer()
  if _timer then
    _timer:stop()
    _timer:close()
    _timer = nil
  end
end

return M
