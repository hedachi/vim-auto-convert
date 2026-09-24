" 英字を含むのが正常な行を書き換えないことのテスト（要 OPENAI_API_KEY、TYPESAFE_API_KEY があれば一次判定も通す）
" 実行: vim -Nu NONE -n -es -S test/test_auto_convert_keep.vim
" 結果: test/results/test_auto_convert_keep_result.txt（keep=OK が合格。変わった行は CHANGED で列挙）
set nocompatible
let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
let g:auto_convert_gate = empty($TYPESAFE_API_KEY) ? '' : 'jev'
let g:auto_convert_logfile = s:root . '/test/results/test_auto_convert_keep.log'
call mkdir(s:root . '/test/results', 'p')
call delete(g:auto_convert_logfile)
runtime plugin/auto_convert.vim

let s:keep = [
      \ 'シミュレーションRPGを作りたい',
      \ '次はアクションRPGかSLGにしようかな',
      \ 'AIにAPIを叩かせてSNSに投稿する',
      \ 'iPhoneとiPadでGitHubを見る',
      \ 'Nintendo Switchの新作が出た',
      \ 'PDFをOCRしてCSVにする',
      \ 'ユーザーIDとパスワードでログインする',
      \ 'ClaudeとGPTを比べる',
      \ 'UIのUXが悪い',
      \ 'OKボタンを押す',
      \ 'Tokyo Game Showに行く',
      \ 'vimでgit commitする',
      \ 'README.mdを読む',
      \ 'Aランクの敵とボス戦',
      \ 'HP 100、MP 30、LV 5',
      \ '* HOW（How to provide benefit）',
      \ ]
let s:r = []
let s:bad = []
enew
call setline(1, '* ゲーム企画メモ')
AutoConvertNow
for s:i in range(len(s:keep))
  let s:prev = copy(g:auto_convert_last)
  call setline(2 + s:i, s:keep[s:i])
  AutoConvertNow
  let s:n = 0
  while s:n < 150 && g:auto_convert_last == s:prev
    sleep 100m
    let s:n += 1
  endwhile
  if getline(2 + s:i) !=# s:keep[s:i]
    call add(s:bad, 'CHANGED: ' . s:keep[s:i] . ' -> ' . getline(2 + s:i))
  endif
endfor
call add(s:r, 'keep=' . (empty(s:bad) ? 'OK' : 'BAD') . ' (' . (len(s:keep) - len(s:bad)) . '/' . len(s:keep) . ')')
call writefile(s:r + s:bad + ['--- log'] + readfile(g:auto_convert_logfile), s:root . '/test/results/test_auto_convert_keep_result.txt')
qall!
