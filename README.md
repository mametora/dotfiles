# dotfiles

[chezmoi](https://www.chezmoi.io/) で管理する macOS 用 dotfiles。

## セットアップ

```sh
# chezmoi のインストール
brew install chezmoi

# dotfiles の初期化・適用
chezmoi init --apply <github-username>
```

## 管理対象

| ファイル/ディレクトリ | 説明 |
|---|---|
| `dot_Brewfile` | Homebrew Bundle（tap, brew, cask, mas, vscode extensions） |
| `dot_claude/` | Claude Code グローバル設定 |
| `private_dot_config/` | Fish shell, gh, git ignore, ecsta 等の XDG 設定 |
| `private_dot_gitconfig` | Git 設定（1Password SSH 署名, LFS, エイリアス） |
| `private_dot_gnupg/` | GPG エージェント設定 |
| `private_dot_ssh/` | SSH 設定（age 暗号化） |

## 主な使い方

```sh
chezmoi add <file>    # ファイルを管理対象に追加
chezmoi edit <file>   # 管理対象ファイルを編集
chezmoi diff          # 変更差分を確認
chezmoi apply         # 変更を適用
```

## 備考

- SSH 設定は [age](https://github.com/FiloSottile/age) で暗号化されている
- Fish shell の設定はテンプレート（`.tmpl`）を使用
- Git コミットは 1Password SSH エージェント経由で署名される
