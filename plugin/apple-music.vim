if exists('g:loaded_apple_music') | finish | endif
let g:loaded_apple_music = 1

if !has('mac') && !has('macunix')
  finish
endif
