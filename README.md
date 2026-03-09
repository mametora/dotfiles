# dotfiles

[chezmoi](https://www.chezmoi.io/) で管理する macOS 用 dotfiles。

## セットアップ

```sh
# chezmoi のインストール
brew install chezmoi

# dotfiles の初期化・適用
# 初回実行時に Git ユーザー名、メールアドレス、SSH 署名鍵を聞かれる
chezmoi init --apply <github-username>
```

age の復号鍵（`key.txt`）を `~/.config/chezmoi/key.txt` に配置しておく必要がある。

## 管理対象

| ファイル/ディレクトリ | 説明 |
|---|---|
| `dot_Brewfile` | Homebrew Bundle（tap, brew, cask, mas, vscode extensions） |
| `dot_claude/` | Claude Code グローバル設定 |
| `private_dot_config/` | Fish shell, gh, git ignore, ecsta 等の XDG 設定 |
| `private_dot_gitconfig.tmpl` | Git 設定（1Password SSH 署名, LFS, エイリアス） |
| `private_dot_gnupg/` | GPG エージェント設定 |
| `private_dot_ssh/` | SSH 設定（age 暗号化） |
| `dot_editorconfig` | グローバル EditorConfig（`~/.editorconfig`） |

## 主な使い方

```sh
chezmoi add <file>    # ファイルを管理対象に追加
chezmoi edit <file>   # 管理対象ファイルを編集
chezmoi diff          # 変更差分を確認
chezmoi apply         # 変更を適用
```

## 備考

- SSH 設定は [age](https://github.com/FiloSottile/age) で暗号化されている
- `.chezmoi.toml.tmpl` により `chezmoi init` 時に設定ファイルが自動生成される
- Fish shell / Git の設定はテンプレート（`.tmpl`）を使用し、ユーザー情報を `chezmoi.toml` の `[data]` から注入する
- Git コミットは 1Password SSH エージェント経由で署名される
