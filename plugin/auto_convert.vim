" Load the implementation from the matching autoload script so auto_convert# functions
" are valid when Vim discovers this plugin through 'runtimepath'.
if exists('g:loaded_auto_convert')
  finish
endif
runtime autoload/auto_convert.vim
