" 空行を含む差分（今回エラーになった実ケース）のテスト
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/auto_convert.vim
call mkdir(s:root . '/test/results', 'p')
enew
call setline(1, '今日の日記')
AutoConvertNow
call setline(1, ['今日の日記', '', 'きょうははらかがってはなあ', '', '何くおうかな', '', '', 'アイムハングリー', '', ''])
AutoConvertNow
let s:waited = 0
while s:waited < 300
  if !empty(g:auto_convert_last)
    break
  endif
  sleep 100m
  let s:waited += 1
endwhile
let s:result = ['last=' . string(g:auto_convert_last)]
call extend(s:result, getline(1, '$'))
call writefile(s:result, s:root . '/test/results/test_auto_convert_blank_result.txt')
qall!
