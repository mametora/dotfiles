set -Ux VISUAL "code --wait --new-window"
set -Ux EDITOR "code --wait --new-window"
eval (/opt/homebrew/bin/brew shellenv)

# ASDF configuration code
if test -z $ASDF_DATA_DIR
    set _asdf_shims "$HOME/.asdf/shims"
else
    set _asdf_shims "$ASDF_DATA_DIR/shims"
end

# Do not use fish_add_path (added in Fish 3.2) because it
# potentially changes the order of items in PATH
if not contains $_asdf_shims $PATH
    set -gx --prepend PATH $_asdf_shims
end
set --erase _asdf_shims

# pnpm
set -gx PNPM_HOME "/Users/mametora/Library/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end

# Added by LM Studio CLI (lms)
set -gx PATH $PATH /Users/mametora/.lmstudio/bin
# End of LM Studio CLI section

set -gx PATH $PATH "$HOME/Library/Application Support/JetBrains/Toolbox/scripts"

if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Created by `pipx` on 2025-10-01 12:08:11
set PATH $PATH /Users/mametora/.local/bin
