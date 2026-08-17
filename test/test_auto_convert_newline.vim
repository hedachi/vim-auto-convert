" insert中の改行（行数変化）で即送信されるテスト
" TextChangedIを直接発火し、3秒タイマーを待たずに変換されることを時間で確認する
" 実行: vim -Nu NONE -n -es -S test/test_auto_convert_newline.vim
" 結果: test/results/test_auto_convert_newline_result.txt
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/auto_convert.vim
call mkdir(s:root . '/test/results', 'p')

enew
call setline(1, '* メモ')
AutoConvertNow
" 1行打って改行した直後の状態を再現（カーソルは新しい行）
call setline(1, ['* メモ', 'kyou ha ii tenki desune', ''])
call cursor(3, 1)
let s:t0 = reltime()
doautocmd TextChangedI
let s:waited = 0
while s:waited < 300 && getline(2) =~# 'kyou'
  sleep 100m
  let s:waited += 1
endwhile
let s:ms = float2nr(reltimefloat(reltime(s:t0)) * 1000)
let s:r = getline(1, '$')
call add(s:r, 'converted=' . (getline(2) =~# '今日' ? 'OK' : 'BAD'))
" 3秒タイマー到達前に変換されていれば即送信が効いている
call add(s:r, 'immediate=' . (s:ms < 2900 ? 'OK' : 'BAD') . ' (' . s:ms . 'ms)')
call writefile(s:r, s:root . '/test/results/test_auto_convert_newline_result.txt')
qall!
