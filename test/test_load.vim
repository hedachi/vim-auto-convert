set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/auto_convert.vim

let s:failures = []
if !exists(':AutoConvertNow')
  call add(s:failures, 'AutoConvertNow command is missing')
endif
if !exists('*auto_convert#Tick')
  call add(s:failures, 'auto_convert#Tick function is missing')
endif
if auto_convert#CharSpan('abc tpyo xyz', 'abc typo xyz') !=# [6, 2]
  call add(s:failures, 'CharSpan result is incorrect')
endif

if !empty(s:failures)
  echoerr join(s:failures, '; ')
  cquit 1
endif
qall!
