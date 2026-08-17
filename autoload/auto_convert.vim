" auto_convert.vim - LLMによる文脈依存の入力変換
" 3秒ごと（+ insertモードを抜けた瞬間）に、前回チェック時とのバッファ差分を見て、
" 変わった行だけをAIに送り、ローマ字・音写入力を意図した言語の表記へ変換する。
" ファイルには一切書き込まない（バッファ内のみ書き換え）。
" 問い合わせ中に内容が変わった行への結果は破棄する（バッティング防止）。

if exists('g:loaded_auto_convert')
  finish
endif
let g:loaded_auto_convert = 1

" Vim 8.2+ 専用（job/channel/setbufline/getenv等を使用）。Neovim非対応。curl必須
if !has('job') || !has('channel') || v:version < 802 || !executable('curl')
  finish
endif

let g:auto_convert_enabled   = get(g:, 'auto_convert_enabled', 1)
let g:auto_convert_interval  = get(g:, 'auto_convert_interval', 3000)
" provider: 'luna' (gpt-5.6-luna, 約1.5秒) / 'deepseek' (deepseek-v4-flash, 約7秒)
let g:auto_convert_provider  = get(g:, 'auto_convert_provider', 'luna')
let g:auto_convert_context   = get(g:, 'auto_convert_context', 8)
let g:auto_convert_max_lines = get(g:, 'auto_convert_max_lines', 40)
let g:auto_convert_target_language = get(g:, 'auto_convert_target_language', 'auto')
let g:auto_convert_logfile   = get(g:, 'auto_convert_logfile', expand('~/.vim/auto_convert.log'))
let g:auto_convert_model     = get(g:, 'auto_convert_model', 'gpt-5.6-luna')
let g:auto_convert_effort    = get(g:, 'auto_convert_effort', 'none')
let g:auto_convert_deepseek_model = get(g:, 'auto_convert_deepseek_model', 'deepseek-v4-flash')
" プラグインファイル更新時の自動リロード（開発者向け。既定OFF）
let g:auto_convert_autoreload = get(g:, 'auto_convert_autoreload', 0)

" AX用: 直近の実行結果 {'time':..., 'status':..., 'detail':...}
let g:auto_convert_last = {}

highlight default link AutoConvertHl DiffText

let s:snap = {}
let s:job = v:null
let s:req = {}
let s:out = []
let s:err = []

let s:prompt = "あなたはテキストエディタの入力変換エンジン。ユーザーはIME等を使わず、音写（日本語のローマ字、中国語のピンイン等）のまま文章を打つ。書きかけのテキストの一部（target、行番号つき）を、前後の文脈（context_before / context_after）から意図した言語と表記を判断して変換する。\n\n変換対象:\n- 音写入力を、文脈に合う言語の自然な文字・単語・文へ変換する。日本語なら漢字かな交じり、中国語なら漢字、韓国語ならハングルなど、言語を限定しない\n- 文中に音写が混ざる形（例:「日本語を kouiu kanzi de ローマ字入力する」→「日本語をこういう感じでローマ字入力する」）も、行全体が音写だけの形（例:「kouyatte henkan sinaide kaitemo iiyounisite」→「こうやって変換しないで書いてもいいようにして」）も変換する\n- 1語だけの短い断片も、前後の文脈から意図を読んで変換する（例: 食事の話の後の「kutta」→「食った」）\n- 同音・同綴りで複数の解釈がある場合は、前後の文脈で意味が通る方を選ぶ（例: 食べ物の話題の「kare」→「カレー」であり「彼」ではない）\n- 長音は「-」で書かれることがある（例:「kare-」→「カレー」、「ro-maji」→「ローマ字」）\n- 音写自体の打ち間違いも文脈から意図を読んで正しく変換する（例:「kettei siteom machigatteta」→「決定しても間違ってた」）\n- 明らかなタイプミス、誤変換、文字の入れ替わり・抜け・重複も修正する（例:「キホ的に」→「基本的に」）\n- 日本語文中の記号も直す: ? → ？、! → ！、, → 、、文末の . → 。\n- 音写の単語区切りスペースと、音写と変換先言語の文字との境界のスペースは、変換先言語で不自然なら変換時に削除する（例: 日本語の「を kouiu」→「をこういう」）。英単語・技術用語の前後の自然なスペースは残す\n- target_language が auto 以外なら、その言語を優先する\n\n守ること:\n- すでに自然な表記の部分は変更しない\n- 意味の言い換え、文体・敬語の変更、内容の追加・削除をしない。変換していない箇所の句読点やスペースを変えない\n- 英語の技術用語・コマンド・製品名・URL・コード、および文脈から英文として書かれた文はそのまま残す\n- 行の分割・結合・並べ替えをしない\n\n出力: JSONのみ。{\"fixes\": {\"行番号\": \"その行全体の変換後テキスト\"}}。変換が必要な行だけ入れる。変換が1行もなければ {\"fixes\": {}}。"


" APIキー未設定の警告は1回だけ出す（3秒ごとのログスパム防止）
let s:keywarned = {}
function! s:KeyOk(env) abort
  if !empty(getenv(a:env))
    return 1
  endif
  if !has_key(s:keywarned, a:env)
    let s:keywarned[a:env] = 1
    call s:Log('error: env ' . a:env . ' not set')
    echohl WarningMsg
    echo 'AutoConvert: 環境変数 ' . a:env . ' が未設定です'
    echohl None
  endif
  return 0
endfunction

function! s:Log(msg) abort
  " g:auto_convert_logfile = '' でログ無効化
  if empty(g:auto_convert_logfile)
    return
  endif
  try
    call mkdir(fnamemodify(g:auto_convert_logfile, ':h'), 'p')
    call writefile([strftime('%Y/%m/%d %H:%M:%S') . ' ' . a:msg], g:auto_convert_logfile, 'a')
  catch
  endtry
endfunction

function! s:Provider() abort
  if g:auto_convert_provider ==# 'deepseek'
    return {'url': 'https://api.deepseek.com/chat/completions',
          \ 'keyenv': 'DEEPSEEK_API_KEY',
          \ 'extra': {'model': g:auto_convert_deepseek_model, 'temperature': 0}}
  endif
  " reasoning_effortがnone以外だとtemperature指定はAPIエラーになるため付けない
  let extra = {'model': g:auto_convert_model, 'reasoning_effort': g:auto_convert_effort}
  if g:auto_convert_effort ==# 'none'
    let extra.temperature = 0
  endif
  return {'url': 'https://api.openai.com/v1/chat/completions',
        \ 'keyenv': 'OPENAI_API_KEY', 'extra': extra}
endfunction

" old/newの共通prefix/suffixを除いた変更範囲を返す（newでの1-indexed閉区間）
function! s:DiffRange(old, new) abort
  let no = len(a:old)
  let nn = len(a:new)
  let p = 0
  while p < no && p < nn && a:old[p] ==# a:new[p]
    let p += 1
  endwhile
  let sfx = 0
  while sfx < no - p && sfx < nn - p && a:old[no - 1 - sfx] ==# a:new[nn - 1 - sfx]
    let sfx += 1
  endwhile
  return [p + 1, nn - sfx]
endfunction

" 自動リロード用: このファイルのパスと読み込み時のmtime
let s:selfpath = expand('<sfile>:p')
let s:selfmtime = getftime(s:selfpath)

function! auto_convert#Tick(...) abort
  if g:auto_convert_autoreload && getftime(s:selfpath) > s:selfmtime
    call timer_stop(s:timer)
    call s:Log('plugin file updated -> reloading')
    call timer_start(50, {-> execute('unlet! g:loaded_auto_convert | source ' . fnameescape(s:selfpath), '')})
    return
  endif
  if !g:auto_convert_enabled
    return
  endif
  if s:job isnot v:null && job_status(s:job) ==# 'run'
    return
  endif
  if !&modifiable || &buftype !=# '' || &readonly
    return
  endif
  let buf = bufnr('%')
  let cur = getline(1, '$')
  if !has_key(s:snap, buf)
    let s:snap[buf] = cur
    return
  endif
  let old = s:snap[buf]
  if cur ==# old
    return
  endif
  let [lstart, lend] = s:DiffRange(old, cur)
  if lstart > lend
    " 削除のみ
    let s:snap[buf] = cur
    return
  endif
  " insertモード中はカーソル行（書きかけ）だけ除外し、その上の書き終わった部分は直す
  let partial = 0
  if mode() =~# '^[iR]' && line('.') >= lstart && line('.') <= lend
    if line('.') - 1 < lstart
      return
    endif
    let lend = line('.') - 1
    let partial = 1
  endif
  if lend - lstart + 1 > g:auto_convert_max_lines
    " 大きな貼り付け等は対象外
    let s:snap[buf] = cur
    call s:Log(printf('skip: %d lines changed (> max %d)', lend - lstart + 1, g:auto_convert_max_lines))
    return
  endif
  let target = cur[lstart - 1 : lend - 1]
  if match(target, '\S') < 0
    " 空白のみの変更
    if !partial
      let s:snap[buf] = cur
    endif
    return
  endif
  call s:Send(buf, cur, lstart, lend, target, partial)
endfunction

function! s:Send(buf, cur, lstart, lend, target, partial) abort
  let prov = s:Provider()
  if !s:KeyOk(prov.keyenv)
    return
  endif
  let numbered = {}
  for i in range(len(a:target))
    let numbered[string(a:lstart + i)] = a:target[i]
  endfor
  let nctx = g:auto_convert_context
  let before = a:lstart - 1 - nctx > 0 ? a:cur[a:lstart - 1 - nctx : a:lstart - 2]
        \ : (a:lstart >= 2 ? a:cur[0 : a:lstart - 2] : [])
  let after = a:cur[a:lend : a:lend - 1 + nctx]
  let body = extend(copy(prov.extra), {
        \ 'response_format': {'type': 'json_object'},
        \ 'messages': [
        \   {'role': 'system', 'content': s:prompt},
        \   {'role': 'user', 'content': json_encode({
        \      'target_language': g:auto_convert_target_language,
        \      'context_before': before, 'target': numbered, 'context_after': after})},
        \ ]})
  let s:req = {'buf': a:buf, 'tick': getbufvar(a:buf, 'changedtick'),
        \ 'start': a:lstart, 'end': a:lend, 'target': a:target, 'sent': reltime(),
        \ 'partial': a:partial, 'curlen': len(a:cur)}
  let s:out = []
  let s:err = []
  let cmd = ['/bin/sh', '-c',
        \ 'curl -sS --max-time 25 ' . prov.url .
        \ ' -H "Content-Type: application/json"' .
        \ ' -H "Authorization: Bearer $' . prov.keyenv . '" -d @-']
  let s:job = job_start(cmd, {
        \ 'out_cb': function('s:OnOut'),
        \ 'err_cb': function('s:OnErr'),
        \ 'close_cb': function('s:OnClose'),
        \ })
  let ch = job_getchannel(s:job)
  call ch_sendraw(ch, json_encode(body))
  call ch_close_in(ch)
  call s:Log(printf('send: buf=%d L%d-%d (%d lines) provider=%s', a:buf, a:lstart, a:lend, len(a:target), g:auto_convert_provider))
endfunction

function! s:OnOut(ch, msg) abort
  call add(s:out, a:msg)
endfunction

function! s:OnErr(ch, msg) abort
  call add(s:err, a:msg)
endfunction

function! s:Fail(msg) abort
  let g:auto_convert_last = {'time': strftime('%H:%M:%S'), 'status': 'error', 'detail': a:msg}
  call s:Log('error: ' . a:msg)
  echohl WarningMsg
  echo 'AutoConvert error: ' . strpart(a:msg, 0, &columns - 20)
  echohl None
endfunction

function! s:OnClose(ch) abort
  let raw = join(s:out, "\n")
  let elapsed = printf('%.1fs', reltimefloat(reltime(s:req.sent)))
  if raw ==# ''
    call s:Fail('empty response (' . join(s:err, ' ') . ')')
    return
  endif
  try
    let resp = json_decode(raw)
  catch
    " 本文はログに残さない方針のため長さだけ記録し、画面にだけ内容を出す
    call s:Fail('bad json (len=' . strlen(raw) . ')')
    return
  endtry
  if type(resp) != v:t_dict || !has_key(resp, 'choices')
    call s:Fail('api error: ' . strpart(get(get(resp, 'error', {}), 'message', 'unknown'), 0, 200))
    return
  endif
  try
    let fixes = json_decode(resp.choices[0].message.content).fixes
  catch
    call s:Fail('bad content (len=' . strlen(resp.choices[0].message.content) . ')')
    return
  endtry
  call s:ApplyFixes(s:req, fixes, elapsed)
endfunction

function! s:ApplyFixes(r, fixes, elapsed) abort
  let r = a:r
  if !bufexists(r.buf)
    return
  endif
  if type(a:fixes) != v:t_dict
    call s:Fail('fixes is not a dict')
    return
  endif
  " strict: 問い合わせ中にバッファが一切変わっていない
  " 変わっていた場合も全破棄はせず、「その行が送信時と同じ内容のまま」の行だけ適用する
  let strict = getbufvar(r.buf, 'changedtick') == r.tick
  let changed = []
  let spans = []
  let dropped = 0
  for [key, text] in items(a:fixes)
    let lnum = str2nr(key)
    " 送った範囲外の行番号や文字列以外は無視（AIの暴走ガード）
    if lnum < r.start || lnum > r.end || type(text) != v:t_string
      call s:Log(printf('ignore fix out of range: %s', string(key)))
      continue
    endif
    let old = r.target[lnum - r.start]
    if text ==# old
      continue
    endif
    if !strict
      " 編集で行がズレた/変わった可能性 → 内容が送信時と完全一致する行にだけ適用
      " （空白行は偶然一致しやすいので対象外）
      if match(old, '\S') < 0 || getbufline(r.buf, lnum, lnum) !=# [old]
        let dropped += 1
        continue
      endif
    endif
    " 書きかけのカーソル行には適用しない
    if bufnr('%') == r.buf && mode() =~# '^[iR]' && line('.') == lnum
      let dropped += 1
      continue
    endif
    call setbufline(r.buf, lnum, text)
    call add(changed, lnum)
    call s:Log(printf('fix L%d', lnum))
    let span = auto_convert#CharSpan(old, text)
    if span[1] > 0
      call add(spans, [lnum, span[0], span[1]])
    endif
  endfor
  call sort(changed, 'n')
  if dropped > 0
    call s:Log(printf('dropped %d fixes (line changed during request)', dropped))
  endif
  if !strict
    " 問い合わせ中に編集があった場合はsnapshotを進めず、次のtickで全体を再チェック
  elseif r.partial
    " カーソル行以降は未処理なので、snapshotは処理済み部分だけ進める
    " （未処理部分は旧snapshotのまま残し、次のtickで再チェックさせる）
    let old = get(s:snap, r.buf, [])
    let tailstart = max([len(old) - (r.curlen - r.end), r.start - 1])
    let tail = tailstart < len(old) ? old[tailstart :] : []
    let s:snap[r.buf] = getbufline(r.buf, 1, r.end) + tail
  else
    let s:snap[r.buf] = getbufline(r.buf, 1, '$')
  endif
  let g:auto_convert_last = {'time': strftime('%H:%M:%S'), 'status': 'ok',
        \ 'detail': printf('%d lines fixed (%s)', len(changed), a:elapsed), 'lines': changed}
  if !empty(changed)
    call s:Log(printf('fixed: buf=%d lines=%s (%s)', r.buf, join(changed, ','), a:elapsed))
    call s:Highlight(r.buf, spans)
    echo printf('AutoConvert: %d行修正 (L%s)', len(changed), join(changed, ',L'))
  else
    call s:Log('clean: no change (' . a:elapsed . ')')
  endif
endfunction

" 変わった文字だけを光らせるため、行内の変更範囲（1-indexedバイト位置と長さ）を返す
function! auto_convert#CharSpan(old, new) abort
  let oc = split(a:old, '\zs')
  let nc = split(a:new, '\zs')
  let p = 0
  while p < len(oc) && p < len(nc) && oc[p] ==# nc[p]
    let p += 1
  endwhile
  let sfx = 0
  while sfx < len(oc) - p && sfx < len(nc) - p && oc[len(oc) - 1 - sfx] ==# nc[len(nc) - 1 - sfx]
    let sfx += 1
  endwhile
  let nmid = len(nc) - p - sfx
  if nmid <= 0
    " 削除のみ: 削除位置の隣の1文字を目印に光らせる
    if empty(nc)
      return [0, 0]
    endif
    let idx = p < len(nc) ? p : len(nc) - 1
    let sb = idx == 0 ? 0 : strlen(join(nc[0 : idx - 1], ''))
    return [sb + 1, strlen(nc[idx])]
  endif
  let startbyte = p == 0 ? 0 : strlen(join(nc[0 : p - 1], ''))
  return [startbyte + 1, strlen(join(nc[p : p + nmid - 1], ''))]
endfunction

" items: [[lnum, col, len], ...] の変更文字範囲だけを光らせる
function! s:Highlight(buf, items) abort
  if bufnr('%') != a:buf
    return
  endif
  let ids = []
  let chunk = []
  for item in a:items
    call add(chunk, item)
    if len(chunk) == 8
      call add(ids, matchaddpos('AutoConvertHl', chunk))
      let chunk = []
    endif
  endfor
  if !empty(chunk)
    call add(ids, matchaddpos('AutoConvertHl', chunk))
  endif
  let winid = win_getid()
  call timer_start(2000, {-> map(ids, {_, id -> s:SafeMatchDelete(id, winid)})})
endfunction

function! s:SafeMatchDelete(id, winid) abort
  try
    call matchdelete(a:id, a:winid)
  catch
  endtry
endfunction

function! auto_convert#Toggle() abort
  let g:auto_convert_enabled = !g:auto_convert_enabled
  echo 'AutoConvert: ' . (g:auto_convert_enabled ? 'ON' : 'OFF')
endfunction

function! auto_convert#Status() abort
  echo printf('AutoConvert: %s / provider=%s / last=%s',
        \ g:auto_convert_enabled ? 'ON' : 'OFF', g:auto_convert_provider, string(g:auto_convert_last))
endfunction

command! AutoConvertToggle call auto_convert#Toggle()
command! AutoConvertNow call auto_convert#Tick()
command! AutoConvertStatus call auto_convert#Status()

" 自動リロード時に旧タイマーが残らないように止めてから張り直す
if exists('s:timer')
  silent! call timer_stop(s:timer)
endif
let s:timer = timer_start(g:auto_convert_interval, function('auto_convert#Tick'), {'repeat': -1})

" 閉じたバッファのsnapshotを掃除（メモリリーク防止）
function! s:Forget(buf) abort
  if has_key(s:snap, a:buf)
    call remove(s:snap, a:buf)
  endif
endfunction

" insert中の改行（行数の変化）を検知して即チェック。
" 3秒周期を待たずに、改行で書き終えた行がすぐ変換される
function! s:OnTextChangedI() abort
  let n = line('$')
  if get(b:, 'auto_convert_lastcount', -1) != n
    let b:auto_convert_lastcount = n
    call auto_convert#Tick()
  endif
endfunction

augroup AutoConvert
  autocmd!
  " insertを抜けた瞬間にも即チェック（入力直後にすぐ直す）
  autocmd InsertLeave * call auto_convert#Tick()
  autocmd TextChangedI,TextChangedP * call s:OnTextChangedI()
  autocmd BufWipeout * call s:Forget(str2nr(expand('<abuf>')))
augroup END
