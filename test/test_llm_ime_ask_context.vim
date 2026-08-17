" []単独行+前の行に質問、のケースで文脈を踏まえた回答が返るかのテスト
" （2026/08/17 19:28 「変換したい文章を教えてください」と聞き返した事故の再現）
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/llm_ime.vim
call mkdir(s:root . '/test/results', 'p')
enew
call setline(1, '* 変換について')
LlmImeNow
call setline(1, ['* 変換について', '日本語の変換ってだるいよね', '思考の速度で打てない', '変換候補見て決定しても間違えたりするし', 'それを直すのが時間かかりすぎ', 'ローマ字の人は楽なんだろうなあもっと', 'douomou?', '[]'])
LlmImeNow
let s:waited = 0
while s:waited < 600 && getline(8) =~# '\[\]'
  sleep 100m
  let s:waited += 1
endwhile
let s:r = ['l7=' . getline(7), 'l8=' . getline(8)]
call add(s:r, 'counter_question=' . (getline(8) =~# '教えてください' ? 'BAD' : 'OK'))
call writefile(s:r, s:root . '/test/results/test_llm_ime_ask_context_result.txt')
qall!
