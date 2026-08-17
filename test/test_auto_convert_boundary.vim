" 日本語+ローマ字混在入力で、変換後に境界スペースが消えることのテスト
" 実行: vim -Nu NONE -n -es -S test/test_auto_convert_boundary.vim
" 結果: test/results/test_auto_convert_boundary_result.txt
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/auto_convert.vim
call mkdir(s:root . '/test/results', 'p')

enew
call setline(1, '* メモ')
AutoConvertNow
call setline(1, [
  \ '* メモ',
  \ '日本語を kouiu kanzi de ローマ字入力する',
  \ 'このエディタは vim de ugoku',
  \ ])
AutoConvertNow
let s:waited = 0
while s:waited < 300 && empty(g:auto_convert_last)
  sleep 100m
  let s:waited += 1
endwhile
let s:r = getline(1, '$')
call add(s:r, 'boundary_space=' . (getline(2) =~# 'を こういう\|感じ で' ? 'REMAINS(BAD)' : 'REMOVED(OK)'))
call writefile(s:r, s:root . '/test/results/test_auto_convert_boundary_result.txt')
qall!
