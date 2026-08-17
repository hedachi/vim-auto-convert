" auto_convert.vim - LLMによる文脈依存の入力変換
" 3秒ごと（+ insertモードを抜けた瞬間）に、前回チェック時とのバッファ差分を見て、
" 変わった行だけをAIに送り、ローマ字・音写入力を意図した言語の表記へ変換する。
" ファイルには一切書き込まない（バッファ内のみ書き換え）。
" 問い合わせ中に内容が変わった行への結果は破棄する（バッティング防止）。

if exists('g:loaded_auto_convert')
  finish
endif
let g:loaded_auto_convert = 1

if !has('job') || !has('channel')
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
" []への回答に使う賢いモデル（誤字修正とは別ジョブで並行実行）
let g:auto_convert_ask_model  = get(g:, 'auto_convert_ask_model', 'gpt-5.6-sol')
let g:auto_convert_ask_effort = get(g:, 'auto_convert_ask_effort', 'none')

" AX用: 直近の実行結果 {'time':..., 'status':..., 'detail':...}
let g:auto_convert_last = {}

highlight default link AutoConvertHl DiffText

let s:snap = {}
let s:job = v:null
let s:req = {}
let s:out = []
let s:err = []
" []回答用の別ジョブ（誤字修正と並行して動く）
let s:ajob = v:null
let s:areq = {}
let s:aout = []
let s:aerr = []
let s:ask_backoff = 0

let s:prompt = "あなたはテキストエディタの入力変換エンジン。ユーザーが書きかけのテキストの一部（target、行番号つき）を、前後の文脈（context_before / context_after）から意図した言語と表記を判断して変換する。\n\n変換対象:\n- ローマ字・ラテン文字による音写入力を、文脈に合う言語の自然な文字・単語・文へ変換する。日本語なら仮名と漢字、中国語なら漢字、韓国語ならハングルなど、言語を限定しない\n- target_language が auto 以外なら、その言語を優先する\n- 明らかなタイプミス、誤変換、文字の入れ替わり・抜け・重複も修正する\n- 例: 日本語文脈の「kouiu kanzi de」→「こういう感じで」、「kontekisuto」→「コンテキスト」\n\n守ること:\n- すでに自然な表記の部分は変更しない\n- 意味の言い換え、文体・敬語の変更、内容の追加・削除、句読点やスペースの好み変更をしない\n- 英語の技術用語・コマンド・固有名詞・URL・コードはそのまま残す\n- 意図した言語や変換内容を確信できない部分はそのまま残す\n- 行の分割・結合・並べ替えをしない\n- 中身の入った角括弧 [〜] はAIアシスタントの回答なので、中身も括弧も変更しない\n\n出力: JSONのみ。{\"fixes\": {\"行番号\": \"その行全体の変換後テキスト\"}}。変換が必要な行だけ入れる。変換が1行もなければ {\"fixes\": {}}。"

let s:askprompt = "あなたはテキストエディタ内のAIアシスタント。ユーザーは自分のメモを書いていて、targetの行に [] （空の角括弧）を置いて回答を求めている。[] の中に回答を書く。\n\n依頼の読み取り方:\n- 依頼・質問は[]と同じ行にあるとは限らない。直前の行と文脈全体（context_before / context_after）から読み取る\n- 文脈はユーザー自身のメモであり、メモに書かれた話題をあなたへの作業依頼と誤解しない\n- 文脈から意図した言語を判定し、その言語で回答する。target_language が auto 以外ならその言語を優先する\n- ローマ字・ラテン文字の音写入力は、文脈に合う言語の自然な表記として読む\n- 依頼が曖昧でも、文脈から最も可能性の高い解釈で中身のある回答を書く\n\n書き方:\n- 回答は角括弧の中に書く。簡潔に、ただし具体的に\n- 角括弧の外は原文を保つ。ただし明らかな誤字と音写入力は自然な表記に変換してよい。意味の言い換え・内容の追加削除はしない\n\n出力: JSONのみ。{\"fixes\": {\"行番号\": \"その行全体（[]に回答が入った状態）\"}}"

function! s:Log(msg) abort
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
  return {'url': 'https://api.openai.com/v1/chat/completions',
        \ 'keyenv': 'OPENAI_API_KEY',
        \ 'extra': {'model': g:auto_convert_model, 'reasoning_effort': g:auto_convert_effort, 'temperature': 0}}
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

function! auto_convert#Tick(...) abort
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
  " [] を含む行は賢いモデルの別ジョブへ（誤字修正と並行）
  let askset = {}
  for i in range(len(target))
    if target[i] =~# '\[\]'
      let askset[lstart + i] = 1
    endif
  endfor
  if !empty(askset) && localtime() >= s:ask_backoff
        \ && !(s:ajob isnot v:null && job_status(s:ajob) ==# 'run')
    call s:SendAsk(buf, cur, lstart, lend, target, askset)
  endif
  call s:Send(buf, cur, lstart, lend, target, partial, askset)
endfunction

function! s:Send(buf, cur, lstart, lend, target, partial, askset) abort
  let prov = s:Provider()
  if empty(getenv(prov.keyenv))
    call s:Log('error: env ' . prov.keyenv . ' not set')
    return
  endif
  let numbered = {}
  for i in range(len(a:target))
    " []行は賢いモデル担当なので誤字修正には渡さない
    if !has_key(a:askset, a:lstart + i)
      let numbered[string(a:lstart + i)] = a:target[i]
    endif
  endfor
  if empty(numbered)
    return
  endif
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
        \ 'partial': a:partial, 'curlen': len(a:cur), 'kind': 'typo'}
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

" []行だけを賢いモデルに送って回答させる
function! s:SendAsk(buf, cur, lstart, lend, target, askset) abort
  if empty(getenv('OPENAI_API_KEY'))
    call s:Log('ask-error: env OPENAI_API_KEY not set')
    return
  endif
  let numbered = {}
  let asklnums = []
  for i in range(len(a:target))
    if has_key(a:askset, a:lstart + i)
      let numbered[string(a:lstart + i)] = a:target[i]
      call add(asklnums, a:lstart + i)
    endif
  endfor
  " 文脈は差分範囲でなく[]の行を基準に前後40行取る
  " （差分範囲内の誤字修正担当行も文脈に含めるため）
  let nctx = 40
  let afirst = min(asklnums)
  let alast = max(asklnums)
  let before = afirst - 1 - nctx > 0 ? a:cur[afirst - 1 - nctx : afirst - 2]
        \ : (afirst >= 2 ? a:cur[0 : afirst - 2] : [])
  let after = a:cur[alast : alast - 1 + nctx]
  let body = {
        \ 'model': g:auto_convert_ask_model,
        \ 'reasoning_effort': g:auto_convert_ask_effort,
        \ 'response_format': {'type': 'json_object'},
        \ 'messages': [
        \   {'role': 'system', 'content': s:askprompt},
        \   {'role': 'user', 'content': json_encode({
        \      'target_language': g:auto_convert_target_language,
        \      'context_before': before, 'target': numbered, 'context_after': after})},
        \ ]}
  let s:areq = {'buf': a:buf, 'tick': getbufvar(a:buf, 'changedtick'),
        \ 'start': a:lstart, 'end': a:lend, 'target': a:target, 'sent': reltime(),
        \ 'kind': 'ask'}
  let s:aout = []
  let s:aerr = []
  let cmd = ['/bin/sh', '-c',
        \ 'curl -sS --max-time 90 https://api.openai.com/v1/chat/completions' .
        \ ' -H "Content-Type: application/json"' .
        \ ' -H "Authorization: Bearer $OPENAI_API_KEY" -d @-']
  let s:ajob = job_start(cmd, {
        \ 'out_cb': {ch, msg -> add(s:aout, msg)},
        \ 'err_cb': {ch, msg -> add(s:aerr, msg)},
        \ 'close_cb': function('s:AOnClose'),
        \ })
  let ch = job_getchannel(s:ajob)
  call ch_sendraw(ch, json_encode(body))
  call ch_close_in(ch)
  call s:Log(printf('ask-send: buf=%d lines=%s model=%s/%s', a:buf, join(keys(numbered), ','), g:auto_convert_ask_model, g:auto_convert_ask_effort))
endfunction

function! s:AOnClose(ch) abort
  let raw = join(s:aout, "\n")
  let elapsed = printf('%.1fs', reltimefloat(reltime(s:areq.sent)))
  try
    let resp = json_decode(raw)
    let fixes = json_decode(resp.choices[0].message.content).fixes
  catch
    let detail = raw ==# '' ? join(s:aerr, ' ') : strpart(raw, 0, 200)
    let s:ask_backoff = localtime() + 60
    call s:Log('ask-error: ' . detail)
    echohl WarningMsg | echo 'Ai []回答エラー: ' . strpart(detail, 0, &columns - 30) . '（60秒後に再試行）' | echohl None
    return
  endtry
  call s:ApplyFixes(s:areq, fixes, elapsed)
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
    call s:Fail('bad json: ' . strpart(raw, 0, 200))
    return
  endtry
  if type(resp) != v:t_dict || !has_key(resp, 'choices')
    call s:Fail('api: ' . strpart(raw, 0, 200))
    return
  endif
  try
    let fixes = json_decode(resp.choices[0].message.content).fixes
  catch
    call s:Fail('bad content: ' . strpart(resp.choices[0].message.content, 0, 200))
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
    if r.kind ==# 'ask' && has_key(s:snap, r.buf)
      " 回答を書いた行はsnapshotにも反映し、誤字修正側が
      " 「新しい差分」として再処理して回答を壊すのを防ぐ
      let sidx = index(s:snap[r.buf], old)
      if sidx >= 0
        let s:snap[r.buf][sidx] = text
      endif
    endif
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
  if r.kind !=# 'typo'
    " []回答はsnapshotを触らない。書き込んだ回答は次のtickの誤字チェックで
    " cleanと判定されてsnapshotに取り込まれる
  elseif !strict
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
  let g:auto_convert_last = {'time': strftime('%H:%M:%S'), 'status': 'ok', 'kind': r.kind,
        \ 'detail': printf('%d lines fixed (%s)', len(changed), a:elapsed), 'lines': changed}
  if !empty(changed)
    call s:Log(printf('%s: buf=%d lines=%s (%s)', r.kind ==# 'ask' ? 'answered' : 'fixed', r.buf, join(changed, ','), a:elapsed))
    call s:Highlight(r.buf, spans)
    if r.kind ==# 'ask'
      echo printf('Ai回答: L%s (%s)', join(changed, ',L'), a:elapsed)
    else
      echo printf('AutoConvert: %d行修正 (L%s)', len(changed), join(changed, ',L'))
    endif
  elseif r.kind ==# 'typo'
    call s:Log('clean: no typo (' . a:elapsed . ')')
  else
    call s:Log('ask: no answer returned (' . a:elapsed . ')')
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

" ========== :Ai <指示> — バッファ全体をLLMに指示して編集させる ==========

let s:iprompt = "あなたはテキストエディタの一括編集エンジン。userから編集指示（instruction）とテキスト全文（text）が渡される。指示に従ってtextを編集し、編集後の全文を返す。\n\nルール:\n- 指示に該当する箇所だけを変更し、それ以外は一字も変えない\n- 指示されていない誤字修正・整形・要約・言い換えはしない\n- 出力: JSONのみ。{\"text\": \"編集後の全文\"}"

let s:ijob = v:null
let s:ireq = {}
let s:iout = []
let s:ierr = []

function! auto_convert#Instruct(instruction) abort
  if s:ijob isnot v:null && job_status(s:ijob) ==# 'run'
    echo 'Ai: 前の指示を実行中です'
    return
  endif
  let prov = s:Provider()
  if empty(getenv(prov.keyenv))
    echohl WarningMsg | echo 'Ai: 環境変数 ' . prov.keyenv . ' がありません' | echohl None
    return
  endif
  let buf = bufnr('%')
  let cur = getline(1, '$')
  let extra = copy(prov.extra)
  if has_key(extra, 'reasoning_effort')
    let extra.reasoning_effort = 'low'
    if has_key(extra, 'temperature')
      call remove(extra, 'temperature')
    endif
  endif
  let body = extend(extra, {
        \ 'response_format': {'type': 'json_object'},
        \ 'messages': [
        \   {'role': 'system', 'content': s:iprompt},
        \   {'role': 'user', 'content': json_encode({
        \      'instruction': a:instruction, 'text': join(cur, "\n")})},
        \ ]})
  let s:ireq = {'buf': buf, 'tick': getbufvar(buf, 'changedtick'), 'sent': reltime(),
        \ 'instruction': a:instruction}
  let s:iout = []
  let s:ierr = []
  let cmd = ['/bin/sh', '-c',
        \ 'curl -sS --max-time 90 ' . prov.url .
        \ ' -H "Content-Type: application/json"' .
        \ ' -H "Authorization: Bearer $' . prov.keyenv . '" -d @-']
  let s:ijob = job_start(cmd, {
        \ 'out_cb': {ch, msg -> add(s:iout, msg)},
        \ 'err_cb': {ch, msg -> add(s:ierr, msg)},
        \ 'close_cb': function('s:IOnClose'),
        \ })
  let ch = job_getchannel(s:ijob)
  call ch_sendraw(ch, json_encode(body))
  call ch_close_in(ch)
  call s:Log(printf('ai-send: buf=%d %d lines', buf, len(cur)))
  echo 'Ai: 実行中... (' . a:instruction . ')'
endfunction

function! s:IOnClose(ch) abort
  let raw = join(s:iout, "\n")
  let elapsed = printf('%.1fs', reltimefloat(reltime(s:ireq.sent)))
  try
    let resp = json_decode(raw)
    let text = json_decode(resp.choices[0].message.content).text
  catch
    let detail = raw ==# '' ? join(s:ierr, ' ') : strpart(raw, 0, 200)
    call s:Log('ai-error: ' . detail)
    echohl WarningMsg | echo 'Ai error: ' . strpart(detail, 0, &columns - 12) | echohl None
    return
  endtry
  let r = s:ireq
  if !bufexists(r.buf)
    return
  endif
  if getbufvar(r.buf, 'changedtick') != r.tick
    call s:Log('ai-discard: buffer changed during request')
    echohl WarningMsg | echo 'Ai: 実行中に編集があったため中止しました。もう一度 :Ai してください' | echohl None
    return
  endif
  let lines = split(text, "\n", 1)
  if len(lines) > 1 && lines[-1] ==# ''
    call remove(lines, -1)
  endif
  let view = bufnr('%') == r.buf ? winsaveview() : {}
  call setbufline(r.buf, 1, lines)
  let total = len(getbufline(r.buf, 1, '$'))
  if total > len(lines)
    silent call deletebufline(r.buf, len(lines) + 1, total)
  endif
  if !empty(view)
    call winrestview(view)
  endif
  let s:snap[r.buf] = getbufline(r.buf, 1, '$')
  call s:Log(printf('ai-done: buf=%d -> %d lines (%s)', r.buf, len(lines), elapsed))
  echo printf('Ai: 完了 (%s)。undoはu一回', elapsed)
endfunction

command! -nargs=1 Ai call auto_convert#Instruct(<q-args>)

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

let s:timer = timer_start(g:auto_convert_interval, function('auto_convert#Tick'), {'repeat': -1})

augroup AutoConvert
  autocmd!
  " insertを抜けた瞬間にも即チェック（入力直後にすぐ直す）
  autocmd InsertLeave * call auto_convert#Tick()
augroup END
