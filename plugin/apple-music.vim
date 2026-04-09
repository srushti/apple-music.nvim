" plugin/apple-music.vim
" Neovim entry-point guard — prevents loading the plugin twice.

if exists('g:loaded_apple_music') | finish | endif
let g:loaded_apple_music = 1

" Only makes sense on macOS.
if !has('mac') && !has('macunix')
  finish
endif
