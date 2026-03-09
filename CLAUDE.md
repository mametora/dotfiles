# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a chezmoi-managed dotfiles repository for macOS. The source directory is `~/.local/share/chezmoi/` and files are applied to `~/`.

## Chezmoi Conventions

- **Naming prefixes**: `dot_` maps to `.`, `private_` sets restrictive permissions, `encrypted_` uses age encryption, `executable_` sets +x
- **Templates**: `.tmpl` files use Go text/template syntax with `{{ .chezmoi.homeDir }}` etc.
- **`.chezmoiignore`**: Lists files that exist in the repo but should NOT be applied to the home directory (e.g. this `CLAUDE.md`)

## Commands

```sh
chezmoi apply           # Apply source state to home directory
chezmoi diff            # Preview changes before applying
chezmoi add <file>      # Add a file from ~ to the source directory
chezmoi edit <file>     # Edit a managed file's source
chezmoi managed         # List all managed files
chezmoi cat <file>      # Show what chezmoi would write for a target file
```

## Repository Structure

- `dot_Brewfile` — Homebrew bundle (taps, brews, casks, mas, vscode extensions)
- `dot_claude/` — Claude Code global config (`~/.claude/`)
- `private_dot_config/` — XDG config (`~/.config/`): fish, gh, git ignore, ecsta
- `private_dot_ssh/` — SSH config (age-encrypted)
- `private_dot_gitconfig.tmpl` — Git config template (1Password SSH signing, LFS, aliases)
- `private_dot_gnupg/` — GPG agent config (pinentry-mac)
- `dot_editorconfig` — Global EditorConfig (`~/.editorconfig`); acts as fallback for projects without their own
- `.chezmoi.toml.tmpl` — chezmoi config template (generates `~/.config/chezmoi/chezmoi.toml` on `chezmoi init`)

## Key Details

- SSH config is encrypted with age (`encrypted_private_config.age`); do not attempt to read or edit directly
- Templates use custom data from `chezmoi.toml` `[data]` section (name, email, signingkey) in addition to `{{ .chezmoi.homeDir }}`
- Fish shell is the primary shell; `config.fish.tmpl` is a template
- Git config is a template (`private_dot_gitconfig.tmpl`); user info is injected from `[data]`
- Git commits are signed via 1Password SSH agent (`op-ssh-sign`)
- When adding new files, use the correct chezmoi prefix naming to match the target path and permissions
