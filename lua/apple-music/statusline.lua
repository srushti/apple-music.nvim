--- apple-music/statusline.lua
--- Provides a ready-made component string for staline.nvim (and any other
--- statusline plugin that accepts a function or evaluated expression).

local M = {}
local music = require("apple-music.music")

-- ---------------------------------------------------------------------------
-- staline.nvim custom section function.
-- Register it by putting the function reference in your sections table:
--
--   require("apple-music.statusline").component
--
-- ---------------------------------------------------------------------------
function M.component()
  return music.nowplaying()
end

-- ---------------------------------------------------------------------------
-- Convenience: returns a %{} expression string suitable for use in
-- vim's built-in statusline (set statusline=...).
-- ---------------------------------------------------------------------------
function M.statusline_expr()
  return "%{%v:lua.require('apple-music.statusline').component()%}"
end

return M
