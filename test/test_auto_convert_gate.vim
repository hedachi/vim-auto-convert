" Jevによる一次判定のテスト（要 OPENAI_API_KEY と TYPESAFE_API_KEY）
" 1) 変換不要な行はLLMへ送らない 2) 変換が必要な行は変換される
" 3) 連続で問い合わせても応答の取り違えが起きない 4) Jevが失敗してもLLMで変換される
" 5) 日本語文中にローマ字が1語だけ混ざる行も見落とさない
" 実行: vim -Nu NONE -n -es -S test/test_auto_convert_gate.vim
" 結果: test/results/test_auto_convert_gate_result.txt
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
let g:auto_convert_gate = 'jev'
let g:auto_convert_logfile = s:root . '/test/results/test_auto_convert_gate.log'
call mkdir(s:root . '/test/results', 'p')
call delete(g:auto_convert_logfile)
runtime plugin/auto_convert.vim

function! s:Wait(cond) abort
  let n = 0
  while n < 150 && !eval(a:cond)
    sleep 100m
    let n += 1
  endwhile
endfunction
function! s:LogHas(pat) abort
  return len(filter(readfile(g:auto_convert_logfile), 'v:val =~# a:pat'))
endfunction
function! s:Idle() abort
  return g:auto_convert_last != s:prev
endfunction

let s:r = []
enew
call setline(1, '* メモ')
AutoConvertNow

" 1) 変換不要
let s:prev = copy(g:auto_convert_last)
call setline(2, '明日は会議がある。資料を作る。')
AutoConvertNow
call s:Wait('s:Idle()')
call add(s:r, 'skip=' . (s:LogHas('gate: skip') == 1 && s:LogHas('send:') == 0 && getline(2) ==# '明日は会議がある。資料を作る。' ? 'OK' : 'BAD'))

" 2) 変換が必要 + 3) 問い合わせ中の連続実行
let s:prev = copy(g:auto_convert_last)
call setline(3, 'kyou ha ii tenki desune')
AutoConvertNow
AutoConvertNow
AutoConvertNow
call s:Wait('s:Idle()')
call add(s:r, 'pass=' . (s:LogHas('gate: pass') == 1 && getline(3) =~# '今日' ? 'OK' : 'BAD') . ' ' . getline(3))
call add(s:r, 'no_mixup=' . (s:LogHas('error') == 0 && s:LogHas('send:') == 1 ? 'OK' : 'BAD'))

" 4) Jev失敗時のフォールバック
let s:key = $TYPESAFE_API_KEY
let $TYPESAFE_API_KEY = 'invalid'
let s:prev = copy(g:auto_convert_last)
call setline(4, 'asita mo hareru')
AutoConvertNow
call s:Wait('s:Idle()')
let $TYPESAFE_API_KEY = s:key
call add(s:r, 'fallback=' . (s:LogHas('gate error') == 1 && getline(4) !~# 'asita' ? 'OK' : 'BAD') . ' ' . getline(4))

" 5) 日本語文中にローマ字が1語だけ混ざる行も一次判定を通過する（見落とし防止）
let s:mixed = ['社会人の友情monogatari', 'これはsugoku大事な話', '明日のyoteiを確認する']
let s:ok = 0
for s:i in range(len(s:mixed))
  let s:prev = copy(g:auto_convert_last)
  call setline(5 + s:i, s:mixed[s:i])
  AutoConvertNow
  call s:Wait('s:Idle()')
  let s:ok += s:LogHas('gate: pass L' . (5 + s:i) . '-')
endfor
call add(s:r, 'mixed_pass=' . (s:ok == len(s:mixed) ? 'OK' : 'BAD') . ' (' . s:ok . '/' . len(s:mixed) . ')')

call writefile(s:r + ['--- log'] + readfile(g:auto_convert_logfile), s:root . '/test/results/test_auto_convert_gate_result.txt')
qall!
