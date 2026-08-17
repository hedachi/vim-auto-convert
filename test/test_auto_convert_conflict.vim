" 競合ガードのテスト（行単位判定）
" a) 問い合わせ中に別の行を編集 → typo行の修正は適用され、編集した行は無傷
" b) 問い合わせ中に対象行自体を編集 → その行への修正は破棄される
set nocompatible
set hidden
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/auto_convert.vim
call mkdir(s:root . '/test/results', 'p')
let s:r = []

" --- a) 別の行を編集 ---
enew
call setline(1, ['メモ', '', 'おわり'])
AutoConvertNow
call setline(2, 'キホ的に適当にtpyoするから')
AutoConvertNow
sleep 200m
call setline(3, 'ユーザーが割り込みで書いた行')
let s:waited = 0
while s:waited < 300 && empty(g:auto_convert_last)
  sleep 100m
  let s:waited += 1
endwhile
call add(s:r, 'a_last=' . string(g:auto_convert_last))
call extend(s:r, map(getline(1, '$'), '"a: " . v:val'))

" --- b) 対象行自体を編集 ---
enew
let g:auto_convert_last = {}
call setline(1, ['メモ2', '', 'おわり'])
AutoConvertNow
call setline(2, 'キホ的に適当にtpyoするから')
AutoConvertNow
sleep 200m
call setline(2, '対象行をユーザーが書き換えた')
let s:waited = 0
while s:waited < 300 && empty(g:auto_convert_last)
  sleep 100m
  let s:waited += 1
endwhile
call add(s:r, 'b_last=' . string(g:auto_convert_last))
call extend(s:r, map(getline(1, '$'), '"b: " . v:val'))

call writefile(s:r, s:root . '/test/results/test_auto_convert_conflict_result.txt')
qall!
