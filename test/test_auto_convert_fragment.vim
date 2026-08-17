" 短い断片・同音語の文脈変換テスト
" 実行: vim -Nu NONE -n -es -S test/test_auto_convert_fragment.vim
" 結果: test/results/test_auto_convert_fragment_result.txt
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/auto_convert.vim
call mkdir(s:root . '/test/results', 'p')

enew
call setline(1, '配達早く来ないかな')
AutoConvertNow
call setline(1, ['配達早く来ないかな', '', 'kutta', 'うまかった', 'kare wo kutta yo'])
AutoConvertNow
let s:waited = 0
while s:waited < 300 && empty(g:auto_convert_last)
  sleep 100m
  let s:waited += 1
endwhile
let s:r = getline(1, '$')
call add(s:r, 'fragment=' . (getline(3) ==# '食った' ? 'OK' : 'BAD'))
call add(s:r, 'homophone=' . (getline(5) =~# 'カレー' ? 'OK' : 'BAD'))
call writefile(s:r, s:root . '/test/results/test_auto_convert_fragment_result.txt')
qall!
