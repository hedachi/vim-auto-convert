# vim-auto-convert

Vimへローマ字や音写のまま入力した文章を、前後の文脈から判断して自然な表記へ自動変換するプラグインです。

日本語だけに限定していません。日本語のローマ字、中国語のピンイン、韓国語のローマ字表記など、入力時に文字・表記の変換を要する言語を対象にしています。

## 変換例

日本語の文章中で次のように入力すると、

```text
kouiu kanzi de kakitemo daijoubu
```

前後の文脈を踏まえて、次のような表記へ変換します。

```text
こういう感じで書いても大丈夫
```

対象言語を中国語に指定した場合は、次のような音写入力も変換できます。

```text
wo jintian qu gongsi
```

```text
我今天去公司
```

## 特徴

- 3秒ごとに、前回確認時から変わった行だけを変換します。
- インサートモードを抜けた時にも即座に確認します。
- 前後の文章を参照し、意図した言語と単語を文脈から判断します。
- 変換された文字だけを2秒間ハイライトします。
- APIへの問い合わせ中に編集した行には、古い変換結果を適用しません。
- Vimのバッファだけを変更し、ファイルの保存は行いません。
- `u` で変換を取り消せます。

## 必要なもの

- Vim 8.2以上（`+job` と `+channel` が有効なもの）。Neovimは未対応です
- `curl`
- OpenAIまたはDeepSeekのAPIキー

## インストール

pathogenを使用している場合:

```sh
git clone https://github.com/hedachi/vim-auto-convert.git ~/.vim/bundle/vim-auto-convert
```

vim-plugを使用している場合は、`.vimrc` に次を追加します。

```vim
Plug 'hedachi/vim-auto-convert'
```

OpenAIを使用する場合は、Vimを起動する環境へAPIキーを設定してください。

```sh
export OPENAI_API_KEY='your-api-key'
```

DeepSeekを使用する場合:

```sh
export DEEPSEEK_API_KEY='your-api-key'
```

## 使い方

インストール後は自動的に有効になります。普段どおり文章を書くだけで、変更された行が自動変換されます。

主なコマンド:

```vim
:AutoConvertToggle
:AutoConvertNow
:AutoConvertStatus
```

- `:AutoConvertToggle`: 自動変換のON/OFFを切り替えます。
- `:AutoConvertNow`: 変更部分をすぐに確認します。
- `:AutoConvertStatus`: 現在の状態と直近の結果を表示します。

## 対象言語

既定では、前後の文章から対象言語を自動判定します。特定言語へ固定したい場合は、Vimの設定へ追加します。

```vim
let g:auto_convert_target_language = 'Japanese'
```

```vim
let g:auto_convert_target_language = 'Chinese'
```

音写は複数の言語や単語として解釈できる場合があります。自動判定が安定しない文章では、対象言語を固定してください。

## APIとモデルの設定

既定ではOpenAIを使用します。

```vim
let g:auto_convert_provider = 'luna'
let g:auto_convert_model = 'gpt-5.6-luna'
```

DeepSeekを使う場合:

```vim
let g:auto_convert_provider = 'deepseek'
let g:auto_convert_deepseek_model = 'deepseek-v4-flash'
```

その他の設定は `:help auto_convert-settings` で確認できます。

## プライバシー

自動変換では、変更された行と前後の文脈を選択したAPI事業者へ送信します。

- APIキーは環境変数から読み取ります。
- ログには入力本文を記録しません。

外部へ送信できない文章では使用しないでください。API利用料金は、選択した事業者とモデルの料金に従って発生します。

## ライセンス

MIT License
