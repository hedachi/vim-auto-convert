" CharSpan単体・[]回答・:Ai一括編集のテスト
set nocompatible
set hidden
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/llm_ime.vim
call mkdir(s:root . '/test/results', 'p')
let s:r = []

" --- CharSpan単体 ---
call add(s:r, 'CharSpan1=' . string(llm_ime#CharSpan('キホ的に', '基本的に')))
call add(s:r, 'CharSpan2=' . string(llm_ime#CharSpan('abc tpyo xyz', 'abc typo xyz')))
call add(s:r, 'CharSpan3=' . string(llm_ime#CharSpan('あいうう', 'あいう')))
call add(s:r, 'CharSpan4=' . string(llm_ime#CharSpan('', 'あたらしい行')))

" --- []回答（賢いモデル）と誤字修正（luna）の並行 ---
enew
call setline(1, 'メモ')
LlmImeNow
call setline(1, ['1たす1はいくつ？数字だけここに書いて[]', 'キホ的に適当にtpyoするから', 'おわり'])
LlmImeNow
let s:waited = 0
while s:waited < 600 && (getline(1) =~# '\[\]' || getline(2) =~# 'キホ')
  sleep 100m
  let s:waited += 1
endwhile
call add(s:r, 'ask_line=' . getline(1))
call add(s:r, 'typo_line=' . getline(2))

" --- :Ai 一括編集 ---
enew
call setline(1, ['今日の日記[16:39]', 'きのうは楽しかった', '[17:02]あしたもがんばる'])
Ai [16:39]みたいな時刻の角括弧表記を全部削除して
let s:waited = 0
let s:before_tick = b:changedtick
while s:waited < 600 && b:changedtick == s:before_tick
  sleep 100m
  let s:waited += 1
endwhile
call add(s:r, 'ai_lines=' . string(getline(1, '$')))

call writefile(s:r, s:root . '/test/results/test_llm_ime_v2_result.txt')
if getline(1) =~# '\[16:39\]' || getline(3) =~# '\[17:02\]'
  cquit 1
endif
qall!
