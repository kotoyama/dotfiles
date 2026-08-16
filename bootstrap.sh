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
    "zed/settings.json:$HOME/.config/zed/settings.json"
    "zed/themes/*.json:$HOME/.config/zed/themes/"
    "git/gitconfig:$HOME/.gitconfig"
    "git/gitignore:$HOME/.gitignore"
    "git/gitattributes:$HOME/.gitattributes"
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
    if [[ "$src" == *"*"* ]]; then
      mkdir -p "$dst"
      local glob="$DOTFILES_DIR/$src"
      local base="${dst%/}"
      for f in $glob; do
        [ -e "$f" ] || continue
        local target="$base/$(basename "$f")"
        backup_if_needed "$target"
        ln -sfn "$f" "$target"
        echo "  ✓ $target -> $f"
      done
      continue
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
  echo "✅ Symlinks ready."
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
  echo "✅ Snapshots saved."
}

setup() {
  # symlinks
  link

  # projects
  echo "🔧 Setting up projects..."
  PROJECTS_DIR="$HOME/projects"
  mkdir -p "$PROJECTS_DIR/personal" "$PROJECTS_DIR/work"
  if [ ! -e "$HOME/Desktop/projects" ] && [ ! -L "$HOME/Desktop/projects" ]; then
    ln -s "$PROJECTS_DIR" "$HOME/Desktop/projects"
    echo "  ✓ $HOME/Desktop/projects -> $PROJECTS_DIR"
  else
    echo "  ℹ️ $HOME/Desktop/projects already exists"
  fi
  echo "✅ Projects ready."

  # zsh
  echo "🔧 Setting up zsh..."
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    echo "  ✓ oh-my-zsh"
  fi
  ZSH_PLUGINS_DIR="$HOME/.oh-my-zsh/custom/plugins"
  mkdir -p "$ZSH_PLUGINS_DIR"
  while read -r repo; do
    [[ -z "$repo" ]] && continue
    local name="${repo##*/}"
    if [ ! -d "$ZSH_PLUGINS_DIR/$name" ]; then
      git clone --depth 1 "https://github.com/$repo" "$ZSH_PLUGINS_DIR/$name"
      echo "  ✓ $name"
    fi
  done < "$DOTFILES_DIR/zsh/plugins.txt"
  echo "✅ zsh ready."

  # Homebrew
  if ! command -v brew >/dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  echo "📦 Installing packages from Brewfile..."
  brew bundle --file="$DOTFILES_DIR/Brewfile"
  echo "✅ Homebrew ready."

  # VS Code extensions
  if command -v code >/dev/null; then
    echo "🔌 Installing VS Code extensions..."
    while read -r ext; do
      [[ -n "$ext" ]] && code --install-extension "$ext"
    done < "$DOTFILES_DIR/vscode/extensions.txt"
  fi
  echo "✅ VS Code extensions ready."

  # macOS settings
  "$DOTFILES_DIR/macos/defaults"

  echo "✅ Setup complete."
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
