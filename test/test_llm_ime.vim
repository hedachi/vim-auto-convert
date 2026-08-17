" llm_imeのE2Eテスト: vim -N -u NONE -es -S test/test_llm_ime.vim で実行
" 結果は test/results/test_llm_ime_result.txt に出力される
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/llm_ime.vim
call mkdir(s:root . '/test/results', 'p')

" テストバッファ準備
enew
call setline(1, ['vimプラグインのメモ', '', 'ここに追記していく'])
" 1回目のTickでベースラインsnapshot採取
LlmImeNow

" 誤字入りの追記をシミュレート
call setline(2, 'キホ的に適当にtpyoするから')
call append(2, 'kouyatte henkan sinaide kaitemo iiyounisite')

" 2回目のTickでAIに送信
LlmImeNow

" ジョブ完了待ち（最大30秒）
let s:waited = 0
while s:waited < 300
  if !empty(g:llm_ime_last)
    break
  endif
  sleep 100m
  let s:waited += 1
endwhile

let s:result = ['last=' . string(g:llm_ime_last)]
call extend(s:result, getline(1, '$'))
call writefile(s:result, s:root . '/test/results/test_llm_ime_result.txt')
qall!
