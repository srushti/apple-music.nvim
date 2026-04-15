local M = {}

local music = require("apple-music.music")

M.config = {
	auto_start = true,
	notify_track = false,
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	vim.api.nvim_create_user_command("AppleMusicPlayPause", function()
		music.play_pause()
	end, { desc = "Apple Music: play / pause" })

	vim.api.nvim_create_user_command("AppleMusicNext", function()
		music.next_track()
	end, { desc = "Apple Music: next track" })

	vim.api.nvim_create_user_command("AppleMusicPrev", function()
		music.prev_track()
	end, { desc = "Apple Music: previous track" })

	vim.api.nvim_create_user_command("AppleMusicRefresh", function()
		music.refresh()
		vim.cmd("redrawstatus!")
	end, { desc = "Apple Music: force statusline refresh" })

	vim.api.nvim_create_user_command("AppleMusicInfo", function()
		music.refresh()
		local s = music.state()
		if s.title == "" then
			vim.notify("Apple Music: nothing playing", vim.log.levels.INFO, { title = " Apple Music" })
		else
			local status_icon = s.status == "playing" and " " or " "
			vim.notify(
				string.format("%s%s\n  %s  %s\n   %s", status_icon, s.title, s.artist, "·", s.album),
				vim.log.levels.INFO,
				{ title = " Apple Music" }
			)
		end
	end, { desc = "Apple Music: show now-playing info" })

	if M.config.notify_track then
		local last_title = ""
		local group = vim.api.nvim_create_augroup("AppleMusicNotify", { clear = true })
		vim.api.nvim_create_autocmd({ "FocusGained", "CursorHold" }, {
			group = group,
			callback = function()
				local s = music.state()
				if s.title ~= last_title and s.title ~= "" then
					last_title = s.title
					vim.notify(
						string.format(" %s  —  %s", s.title, s.artist),
						vim.log.levels.INFO,
						{ title = " Now Playing" }
					)
				end
			end,
		})
	end

	if M.config.auto_start then
		music.start_timer()
	end
end

M.nowplaying = music.nowplaying
M.state = music.state
M.refresh = music.refresh
M.play_pause = music.play_pause
M.next_track = music.next_track
M.prev_track = music.prev_track
M.start_timer = music.start_timer
M.stop_timer = music.stop_timer

return M
