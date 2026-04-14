--- apple-music/music.lua
--- AppleScript bridge: queries Apple Music state via osascript.

local M = {}

-- Cached state so the statusline never blocks on a slow system call.
M._cache = {
	status = "not_running", -- "playing" | "paused" | "stopped" | "not_running"
	title = "",
	artist = "",
	album = "",
	updated = 0,
}

local TTL_ACTIVE_MS = 20 * 1000 -- 20 s while Music is running
local TTL_IDLE_MS = 60 * 1000 -- 1 min while Music is not running

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
-- All info is retrieved in a single osascript call to minimise latency.
-- ---------------------------------------------------------------------------
local function fetch()
	local script = [[
		tell application "System Events"
			set isRunning to (name of processes) contains "Music"
		end tell
		if not isRunning then
			return "not_running\t\t\t"
		end if
		tell application "Music"
			set s to (get player state as string)
			if s is "playing" or s is "paused" then
				set t to name of current track
				set ar to artist of current track
				set al to album of current track
				return s & "\t" & t & "\t" & ar & "\t" & al
			else
				return s & "\t\t\t"
			end if
		end tell
	]]

	local raw = applescript(script)
	if not raw then
		M._cache.status = "stopped"
		M._cache.title = ""
		M._cache.artist = ""
		M._cache.album = ""
		return false
	end

	-- Parse the tab-delimited response: state\ttitle\tartist\talbum
	local parts = vim.split(raw, "\t", { plain = true })
	local state = parts[1] or "stopped"
	M._cache.status = state
	M._cache.title = parts[2] or ""
	M._cache.artist = parts[3] or ""
	M._cache.album = parts[4] or ""
	-- true = Music is running (even if stopped/paused), false = not running at all.
	return state ~= "not_running"
end

-- Returns the appropriate TTL based on whether Music is running.
local function current_ttl()
	local s = M._cache.status
	return (s == "playing" or s == "paused" or s == "stopped") and TTL_ACTIVE_MS or TTL_IDLE_MS
end

-- ---------------------------------------------------------------------------
-- Internal: refresh cache if TTL has expired.
-- ---------------------------------------------------------------------------
local function maybe_refresh()
	local now = vim.uv.now()
	if (now - M._cache.updated) >= current_ttl() then
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
		if #label > 30 then
			label = label:sub(1, 27) .. "…"
		end
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
-- Restarts itself with the correct interval when the running state changes.
-- ---------------------------------------------------------------------------
local _timer = nil
local _timer_interval = nil -- tracks the interval the timer was started with

function M.start_timer()
	if _timer then
		return
	end
	local interval = current_ttl()
	_timer_interval = interval
	_timer = vim.uv.new_timer()
	_timer:start(
		0,
		interval,
		vim.schedule_wrap(function()
			fetch()
			M._cache.updated = vim.uv.now()
			-- Restart the timer if the TTL bucket has changed (running ↔ not running).
			local new_interval = current_ttl()
			if new_interval ~= _timer_interval then
				_timer:stop()
				_timer_interval = new_interval
				_timer:start(
					new_interval,
					new_interval,
					vim.schedule_wrap(function()
						fetch()
						M._cache.updated = vim.uv.now()
						vim.cmd("redrawstatus!")
					end)
				)
			end
			-- Redraw the statusline without moving the cursor.
			vim.cmd("redrawstatus!")
		end)
	)
end

function M.stop_timer()
	if _timer then
		_timer:stop()
		_timer:close()
		_timer = nil
	end
end

return M
