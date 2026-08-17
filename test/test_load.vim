set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/llm_ime.vim

let s:failures = []
if !exists(':LlmImeNow')
  call add(s:failures, 'LlmImeNow command is missing')
endif
if !exists('*llm_ime#Tick')
  call add(s:failures, 'llm_ime#Tick function is missing')
endif
if llm_ime#CharSpan('abc tpyo xyz', 'abc typo xyz') !=# [6, 2]
  call add(s:failures, 'CharSpan result is incorrect')
endif

if !empty(s:failures)
  echoerr join(s:failures, '; ')
  cquit 1
endif
qall!
