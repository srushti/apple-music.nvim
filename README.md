# 🎵 apple-music.nvim

A lightweight Neovim plugin that connects to **Apple Music** running locally on macOS and surfaces *now-playing* information in your statusline.

---

## Features

- **Statusline integration** — shows the current track + artist in your statusline with a play/pause icon
- **Background polling** — a `vim.uv` timer refreshes state every 5 s without blocking the editor
- **Graceful degradation** — shows nothing (no errors, no empty brackets) when Music is stopped or not running
- **Transport controls** — play/pause, next, previous track via commands and keymaps
- **Notification mode** — optional `vim.notify` popup whenever the track changes

---

## Requirements

| Requirement | Notes |
|---|---|
| macOS | Uses `NSDistributedNotificationCenter` + `osascript` to talk to Music.app |
| Neovim ≥ 0.10 | Uses `vim.uv` (libuv bindings) |
| Apple Music | Must be installed (comes with macOS) |
| Xcode Command Line Tools | Needed once to compile the watcher binary (`swiftc`) |

---

## Installation (lazy.nvim)

Add `lua/plugins/apple-music.lua` to your Neovim config:

```lua
return {
  {
    dir = vim.fn.stdpath("data") .. "/lazy/apple-music.nvim",
    name = "apple-music.nvim",
    opts = {
      auto_start   = true,   -- start background refresh timer on setup
      notify_track = false,  -- set true to get a popup on track change
    },
    keys = {
      { "<leader>m<space>", "<cmd>AppleMusicPlayPause<cr>",  desc = "Play / Pause" },
      { "<leader>mn",       "<cmd>AppleMusicNext<cr>",       desc = "Next track" },
      { "<leader>mp",       "<cmd>AppleMusicPrev<cr>",       desc = "Previous track" },
      { "<leader>mi",       "<cmd>AppleMusicInfo<cr>",       desc = "Now playing info" },
      { "<leader>mr",       "<cmd>AppleMusicRefresh<cr>",    desc = "Refresh statusline" },
    },
  },
}
```

---

## Statusline (staline.nvim)

Add the component function to the `right` section of **staline.nvim**:

```lua
require("staline").setup({
  sections = {
    right = {
      function() return require("apple-music.statusline").component() end,
      "right_sep_double",
      "-line_column",
    },
  },
})
```

---

## Commands

| Command | Description |
|---|---|
| `:AppleMusicPlayPause` | Toggle play / pause |
| `:AppleMusicNext` | Skip to next track |
| `:AppleMusicPrev` | Go to previous track |
| `:AppleMusicInfo` | Show now-playing popup (via `vim.notify`) |
| `:AppleMusicRefresh` | Force an immediate cache refresh |

---

## Public Lua API

```lua
local am = require("apple-music")

am.nowplaying()   -- → string  e.g. " Bloom  Beach House"
am.state()        -- → { title, artist, album, status }
am.refresh()      -- force refresh
am.play_pause()
am.next_track()
am.prev_track()
am.start_timer()  -- start background polling
am.stop_timer()   -- stop background polling
```

---

## How it works

On **macOS**, `setup()` / `start_timer()` does two things:

1. **Initial sync** — one `osascript` call fetches the current player state so the statusline is correct immediately on startup.
2. **Event-driven watcher** — a small compiled Swift binary (`bin/music-watcher`) is spawned as a background process. It subscribes to `NSDistributedNotificationCenter` for `com.apple.Music.playerInfo`, the notification Apple Music posts on every track change and play/pause toggle. Each event is written to the process's stdout as a JSON line; Neovim reads it via a `vim.uv` pipe and updates the cache instantly — no polling, no timer.

On **non-macOS** all public functions are no-ops and nothing is started.

### Building the watcher binary

The binary only needs to be compiled once (or after updating the plugin):

```sh
cd ~/.local/share/nvim/lazy/apple-music.nvim
swiftc bin/music-watcher.swift -o bin/music-watcher
```

If `swiftc` is not found, install the Xcode Command Line Tools:

```sh
xcode-select --install
```

> The compiled binary is intentionally `.gitignore`-d; each machine compiles it locally.

---

## License

MIT
