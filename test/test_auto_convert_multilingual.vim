" 日本語以外の音写入力を、明示した対象言語へ変換できることを確認する。
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
let g:auto_convert_target_language = 'Chinese'
runtime plugin/auto_convert.vim
call mkdir(s:root . '/test/results', 'p')

enew
call setline(1, '今天的记录')
AutoConvertNow
call append(1, 'wo jintian qu gongsi')
AutoConvertNow

let s:waited = 0
while s:waited < 300 && empty(g:auto_convert_last)
  sleep 100m
  let s:waited += 1
endwhile

let s:converted = getline(2)
call writefile(['converted=' . s:converted],
      \ s:root . '/test/results/test_auto_convert_multilingual_result.txt')
if s:converted =~# '[A-Za-z]'
  cquit 1
endif
qall!
