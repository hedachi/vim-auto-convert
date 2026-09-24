" test/cases_auto_convert.tsv の各行を1件ずつ変換させ、期待どおりか判定するテスト
" （要 OPENAI_API_KEY）
" 実行: vim -Nu NONE -n -es -S test/test_auto_convert_cases.vim
" 結果: test/results/test_auto_convert_cases_result.txt（cases=OK が合格。失敗は NG 行に入力と出力）
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
let g:auto_convert_logfile = s:root . '/test/results/test_auto_convert_cases' . get(g:, 'auto_convert_test_tag', '') . '.log'
call mkdir(s:root . '/test/results', 'p')
call delete(g:auto_convert_logfile)
runtime plugin/auto_convert.vim

let s:out = []
let s:ng = 0
let s:total = 0
for s:line in readfile(s:root . '/test/cases_auto_convert.tsv')
  if s:line =~# '^#' || s:line ==# ''
    continue
  endif
  let [s:kind, s:ctx, s:input, s:must, s:mustnot] = (split(s:line, "\t", 1) + ['', '', '', '', ''])[0:4]
  let s:total += 1
  enew!
  call setline(1, empty(s:ctx) ? '* メモ' : s:ctx)
  AutoConvertNow
  let g:auto_convert_last = {}
  call setline(2, s:input)
  AutoConvertNow
  let s:n = 0
  while s:n < 150 && empty(g:auto_convert_last)
    sleep 100m
    let s:n += 1
  endwhile
  let s:got = getline(2)
  if s:kind ==# 'safe'
    let s:ok = 1
    for s:w in split(s:must, '|')
      let s:ok = s:ok && stridx(s:got, s:w) >= 0
    endfor
    for s:w in split(s:mustnot, '|')
      let s:ok = s:ok && stridx(s:got, s:w) < 0
    endfor
  elseif s:kind ==# 'keep'
    let s:ok = s:got ==# s:input
  else
    let s:ok = s:got !=# s:input
    for s:w in split(s:must, '|')
      let s:ok = s:ok && stridx(s:got, s:w) >= 0
    endfor
    for s:w in split(s:mustnot, '|')
      let s:ok = s:ok && stridx(s:got, s:w) < 0
    endfor
  endif
  if !s:ok
    let s:ng += 1
  endif
  call add(s:out, printf('%s %-4s %s -> %s', s:ok ? 'ok' : 'NG', s:kind, s:input, s:got))
endfor
call writefile(['cases=' . (s:ng == 0 ? 'OK' : 'BAD') . printf(' (%d/%d)', s:total - s:ng, s:total)] + s:out,
      \ s:root . '/test/results/test_auto_convert_cases' . get(g:, 'auto_convert_test_tag', '') . '_result.txt')
qall!
