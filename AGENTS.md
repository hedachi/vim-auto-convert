# vim-auto-convert

ローマ字・音写入力を前後の文脈から判定し、意図した言語の自然な表記へ自動変換するVimプラグインの公開リポジトリ。日本語に限定せず、入力時に表記変換を要する言語を対象とする。

## 公開範囲

- 自動変換の本体は `autoload/auto_convert.vim`。
- Vim起動時の入口は `plugin/auto_convert.vim`。
- Vimのヘルプは `doc/auto_convert.txt`。
- 公開内容は、一般利用者に必要なコード、テスト、利用説明、ライセンスに限定する。
- 非公開の開発リポジトリから移す内容は、公開用途に一般化してから追加する。
- 公開前に、追加ファイルとGit差分を確認し、公開用途に必要な情報だけで構成されていることを確認する。

## 安全性

- APIキーは環境変数からのみ読み取る。
- 通常ログは、入力本文や通信内容を除いた動作状況と結果だけを記録する。
- エラーは、原因と利用者が取れる対応だけを表示する。

## 開発と確認

- 読み込み確認は `vim -Nu NONE -n -es -S test/test_load.vim` で実行する。
- 変更後は対象機能のE2Eテストと `git diff --check` を実行する。
- APIを使うE2Eテストは `vim -Nu NONE -n -es -S test/test_auto_convert.vim` など、`test/test_auto_convert*.vim` を個別に実行し、`test/results/` の結果を確認する。
- 混在入力の境界スペース削除は `test/test_auto_convert_boundary.vim` で確認する（`boundary_space=REMOVED(OK)` が合格）。
- 短い断片・同音語の文脈変換は `test/test_auto_convert_fragment.vim` で確認する（`fragment=OK` と `homophone=OK` が合格）。
- 改行時の即時送信は `test/test_auto_convert_newline.vim` で確認する（`converted=OK` と `immediate=OK` が合格）。
- テスト方法を追加・変更した場合は、このファイルへ実行コマンドと確認対象を追記する。
- 利用者への変更報告では、利用者にとって何が変わったか、どう確認したかを簡潔に説明する。

## Git運用

- ファイルを変更したら、日本語のコミットメッセージでコミットする。
- コミットしたら同じターンでpushする。
- pushできない場合は、理由と未pushのコミットIDを報告する。
