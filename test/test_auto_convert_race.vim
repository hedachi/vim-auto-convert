" 問い合わせ中に続けて実行しても、応答の取り違えやエラーが起きないことのテスト（要 OPENAI_API_KEY）
" 実行: vim -Nu NONE -n -es -S test/test_auto_convert_race.vim
" 結果: test/results/test_auto_convert_race_result.txt（converted=OK と no_mixup=OK が合格）
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
let g:auto_convert_logfile = s:root . '/test/results/test_auto_convert_race.log'
call mkdir(s:root . '/test/results', 'p')
call delete(g:auto_convert_logfile)
runtime plugin/auto_convert.vim

enew
call setline(1, '* メモ')
AutoConvertNow
call setline(2, 'kyou ha ii tenki desune')
AutoConvertNow
AutoConvertNow
AutoConvertNow
let s:n = 0
while s:n < 150 && empty(g:auto_convert_last)
  sleep 100m
  let s:n += 1
endwhile
sleep 1
let s:log = readfile(g:auto_convert_logfile)
let s:r = ['converted=' . (getline(2) =~# '今日' ? 'OK' : 'BAD') . ' ' . getline(2)]
call add(s:r, 'no_mixup=' . (len(filter(copy(s:log), 'v:val =~# "error"')) == 0 && len(filter(copy(s:log), 'v:val =~# "send:"')) == 1 ? 'OK' : 'BAD'))
call writefile(s:r + ['--- log'] + s:log, s:root . '/test/results/test_auto_convert_race_result.txt')
qall!
