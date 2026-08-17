" Load the implementation from the matching autoload script so llm_ime# functions
" are valid when Vim discovers this plugin through 'runtimepath'.
if exists('g:loaded_llm_ime')
  finish
endif
runtime autoload/llm_ime.vim
