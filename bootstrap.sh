#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$HOME/dotfiles"
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

backup_if_needed() {
  local dst="$1"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/"
    echo "  💾 Backed up: $dst"
  fi
}

link() {
  echo "🔧 Setting up symlinks..."
  local links=(
    "ghostty/config:$HOME/.config/ghostty/config"
    "opencode/opencode.jsonc:$HOME/.config/opencode/opencode.jsonc"
    "opencode/tui.json:$HOME/.config/opencode/tui.json"
    "opencode/AGENTS.md:$HOME/.config/opencode/AGENTS.md"
    "vscode/settings.jsonc:$HOME/Library/Application Support/Code/User/settings.json"
    "git/gitconfig:$HOME/.gitconfig"
    "git/gitignore_global:$HOME/.gitignore_global"
    "ssh/config:$HOME/.ssh/config"
    "zsh/zshrc:$HOME/.zshrc"
    "zsh/zprofile:$HOME/.zprofile"
    "bootstrap.sh:$HOME/.local/bin/dotfiles"
  )
  for entry in "${links[@]}"; do
    if [[ "$entry" != *:* ]]; then
      echo "❌ Error: invalid link entry: '$entry' (expected 'source:dest')" >&2
      exit 1
    fi
    src="${entry%%:*}"
    dst="${entry#*:}"
    if [ -z "$dst" ]; then
      echo "❌ Error: missing destination in: '$entry'" >&2
      exit 1
    fi
    if [ ! -e "$DOTFILES_DIR/$src" ]; then
      echo "❌ Error: source not found: $DOTFILES_DIR/$src" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$dst")"
    backup_if_needed "$dst"
    ln -sfn "$DOTFILES_DIR/$src" "$dst"
    echo "  ✓ $dst -> $DOTFILES_DIR/$src"
  done
  echo "✅ Done."
}

sync() {
  local snapshots=(
    "brew bundle dump --force --no-vscode --no-uv --no-describe --file=$DOTFILES_DIR/Brewfile"
    "code --list-extensions > $DOTFILES_DIR/vscode/extensions.txt"
  )
  for cmd in "${snapshots[@]}"; do
    echo "  📸 $cmd"
    if ! bash -c "$cmd"; then
      echo "❌ Error: snapshot failed: $cmd" >&2
      exit 1
    fi
  done
  echo "✅ Done."
}

setup() {
  # symlinks
  link

  # zsh
  echo "🔧 Setting up zsh..."
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    echo "  ✓ oh-my-zsh"
  fi
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
  while read -r repo; do
    [[ -z "$repo" ]] && continue
    local name="${repo##*/}"
    if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/$name" ]; then
      git clone --depth 1 "https://github.com/$repo" "$HOME/.oh-my-zsh/custom/plugins/$name"
      echo "  ✓ $name"
    fi
  done < "$DOTFILES_DIR/zsh/plugins.txt"

  # Homebrew
  if ! command -v brew >/dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  echo "📦 Installing packages from Brewfile..."
  brew bundle --file="$DOTFILES_DIR/Brewfile"

  # VS Code extensions
  if command -v code >/dev/null; then
    echo "🔌 Installing VS Code extensions..."
    while read -r ext; do
      [[ -n "$ext" ]] && code --install-extension "$ext"
    done < "$DOTFILES_DIR/vscode/extensions.txt"
  fi

  # macOS settings
  "$DOTFILES_DIR/macos/defaults"

  echo "✅ Done."
}

help() {
  echo "dotfiles — manage your configs"
  echo "  dotfiles link   setup symlinks"
  echo "  dotfiles sync   re-export config snapshots"
  echo "  dotfiles setup  full setup"
}

cmd="${1:-help}"
case "$cmd" in
  link) link ;;
  sync) sync ;;
  setup) setup ;;
  help|-h|--help) help ;;
  *) echo "Unknown command: $cmd"; help; exit 1 ;;
esac
