" 動画で起きた「[]回答が誤字修正に消される」バグの再現テスト
" ローマ字行+[]に回答が入った後、続けて誤字修正のtickが走っても回答が残ること
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/llm_ime.vim
call mkdir(s:root . '/test/results', 'p')
enew
call setline(1, '最近のvimについて')
LlmImeNow
call setline(1, ['最近のvimについて', 'saikin ha neovim ttenoga hayatteru?[]'])
LlmImeNow
" 回答が入るまで待つ
let s:waited = 0
while s:waited < 600 && getline(2) =~# '\[\]'
  sleep 100m
  let s:waited += 1
endwhile
let s:answered = getline(2)
" その後、別の行を追記して誤字修正tickを何度も回す（動画の状況を再現）
call append(2, 'naniga chigaundesuka?')
LlmImeNow
sleep 3000m
LlmImeNow
sleep 3000m
LlmImeNow
sleep 3000m
let s:r = ['answered=' . s:answered]
call add(s:r, 'final_l2=' . getline(2))
call add(s:r, 'final_l3=' . getline(3))
call add(s:r, 'preserved=' . (getline(2) =~# '\[..*\]' ? 'YES' : 'NO'))
call writefile(s:r, s:root . '/test/results/test_llm_ime_ask_preserve_result.txt')
qall!
