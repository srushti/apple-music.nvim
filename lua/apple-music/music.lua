local M = {}

if vim.fn.has("mac") == 0 and vim.fn.has("macunix") == 0 then
	local noop = function() end
	M._cache = {}
	M.nowplaying = function()
		return ""
	end
	M.state = function()
		return {}
	end
	M.refresh = noop
	M.play_pause = noop
	M.next_track = noop
	M.prev_track = noop
	M.start_timer = noop
	M.stop_timer = noop
	return M
end

M._cache = {
	status = "not_running", -- "playing" | "paused" | "stopped" | "not_running"
	title = "",
	artist = "",
	album = "",
	updated = 0,
}

local PLUGIN_ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)/lua/")
local WATCHER_BIN = PLUGIN_ROOT .. "/bin/music-watcher"
local WATCHER_SRC = PLUGIN_ROOT .. "/bin/music-watcher.swift"

local function bin_is_stale()
	local bin_stat = vim.uv.fs_stat(WATCHER_BIN)
	if not bin_stat then
		return true
	end
	local src_stat = vim.uv.fs_stat(WATCHER_SRC)
	if not src_stat then
		return false
	end
	return src_stat.mtime.sec > bin_stat.mtime.sec
		or (src_stat.mtime.sec == bin_stat.mtime.sec and src_stat.mtime.nsec > bin_stat.mtime.nsec)
end

local function recompile(on_done)
	vim.notify("apple-music.nvim: recompiling watcher…", vim.log.levels.INFO, { title = " Apple Music" })
	local stderr = vim.uv.new_pipe(false)
	local err_buf = ""
	vim.uv.spawn(
		"swiftc",
		{
			args = { WATCHER_SRC, "-o", WATCHER_BIN },
			env = nil,
			cwd = nil,
			uid = nil,
			gid = nil,
			verbatim = false,
			detached = false,
			hide = false,
			stdio = { nil, nil, stderr },
		},
		vim.schedule_wrap(function(code, _signal)
			stderr:read_stop()
			stderr:close()
			if code == 0 then
				vim.notify("apple-music.nvim: watcher compiled OK", vim.log.levels.INFO, { title = " Apple Music" })
				on_done(true)
			else
				vim.notify(
					"apple-music.nvim: compilation failed:\n" .. err_buf,
					vim.log.levels.ERROR,
					{ title = " Apple Music" }
				)
				on_done(false)
			end
		end)
	)
	stderr:read_start(function(_err, data)
		if data then
			err_buf = err_buf .. data
		end
	end)
end

local function applescript(script)
	local result = vim.fn.system({ "osascript", "-e", script })
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return vim.trim(result)
end

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
		return
	end

	local parts = vim.split(raw, "\t", { plain = true })
	M._cache.status = parts[1] or "stopped"
	M._cache.title = parts[2] or ""
	M._cache.artist = parts[3] or ""
	M._cache.album = parts[4] or ""
	M._cache.updated = vim.uv.now()
end

local function apply_event(obj)
	M._cache.status = obj.status or "stopped"
	M._cache.title = obj.title or ""
	M._cache.artist = obj.artist or ""
	M._cache.album = obj.album or ""
	M._cache.updated = vim.uv.now()
	vim.cmd("redrawstatus!")
end

local _proc = nil
local _stdout = nil
local _buf = "" -- accumulate partial lines

local function stop_watcher()
	if _stdout then
		_stdout:read_stop()
		_stdout:close()
		_stdout = nil
	end
	if _proc then
		_proc:kill("sigterm")
		_proc:close()
		_proc = nil
	end
	_buf = ""
end

local function start_watcher()
	if _proc then
		return
	end

	if vim.fn.executable("swiftc") == 0 then
		vim.notify(
			"apple-music.nvim: swiftc not found — install Xcode Command Line Tools:\n  xcode-select --install",
			vim.log.levels.WARN,
			{ title = " Apple Music" }
		)
		return
	end

	if bin_is_stale() then
		recompile(function(ok)
			if ok then
				start_watcher()
			end
		end)
		return
	end

	_stdout = vim.uv.new_pipe(false)

	local handle, err = vim.uv.spawn(WATCHER_BIN, {
		args = {},
		env = nil,
		cwd = nil,
		uid = nil,
		gid = nil,
		verbatim = false,
		detached = false,
		hide = false,
		stdio = { nil, _stdout, nil },
	}, function(_code, _signal)
		stop_watcher()
	end)

	if not handle then
		vim.notify(
			"apple-music.nvim: failed to spawn watcher: " .. (err or "unknown"),
			vim.log.levels.ERROR,
			{ title = " Apple Music" }
		)
		_stdout:close()
		_stdout = nil
		return
	end

	_proc = handle

	_stdout:read_start(vim.schedule_wrap(function(_read_err, data)
		if _read_err or not data then
			return
		end
		_buf = _buf .. data
		for line in _buf:gmatch("([^\n]+)\n") do
			local ok, obj = pcall(vim.json.decode, line)
			if ok and type(obj) == "table" then
				apply_event(obj)
			end
		end
		_buf = _buf:match("[^\n]*$") or ""
	end))
end

function M.nowplaying()
	local s = M._cache
	if s.status == "playing" and s.title ~= "" then
		local label = s.title
		if s.artist ~= "" then
			label = "♫ " .. label .. " - " .. s.artist
		end
		if #label > 48 then
			label = label:sub(1, 45) .. "…"
		end
		return " " .. label
	elseif s.status == "paused" and s.title ~= "" then
		local label = s.title
		if #label > 30 then
			label = label:sub(1, 27) .. "…"
		end
		return " " .. label
	end
	return ""
end

function M.state()
	return vim.deepcopy(M._cache)
end

function M.refresh()
	fetch()
	vim.cmd("redrawstatus!")
end

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

function M.start_timer()
	fetch()
	start_watcher()
end

function M.stop_timer()
	stop_watcher()
end

return M
