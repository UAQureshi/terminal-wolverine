#!/usr/bin/env bash
# install.sh — copy the terminal-wolverine config files into your home dir.
# Idempotent. Backs up any existing target with a .bak.<timestamp> suffix.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

backup_and_copy() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ]; then
        cp "$dst" "$dst.bak.$TS"
        echo "  backed up $dst -> $dst.bak.$TS"
    fi
    cp "$src" "$dst"
    echo "  installed $dst"
}

echo "==> Installing oh-my-posh helpers"
backup_and_copy "$REPO_DIR/oh-my-posh/zsh.omp.json" "$HOME/.config/oh-my-posh/zsh.omp.json"
backup_and_copy "$REPO_DIR/oh-my-posh/mem.sh"       "$HOME/.config/oh-my-posh/mem.sh"
backup_and_copy "$REPO_DIR/oh-my-posh/load.sh"      "$HOME/.config/oh-my-posh/load.sh"
backup_and_copy "$REPO_DIR/oh-my-posh/disk.sh"      "$HOME/.config/oh-my-posh/disk.sh"
backup_and_copy "$REPO_DIR/oh-my-posh/cpu.sh"       "$HOME/.config/oh-my-posh/cpu.sh"
chmod +x "$HOME/.config/oh-my-posh"/{mem,load,disk,cpu}.sh

echo "==> Installing Copilot CLI statusline"
backup_and_copy "$REPO_DIR/copilot/statusline.sh"        "$HOME/.copilot/statusline.sh"
backup_and_copy "$REPO_DIR/copilot/statusline.omp.json"  "$HOME/.copilot/statusline.omp.json"
chmod +x "$HOME/.copilot/statusline.sh"

echo "==> Installing Claude Code statusline"
backup_and_copy "$REPO_DIR/claude/statusline.sh"         "$HOME/.claude/statusline.sh"
backup_and_copy "$REPO_DIR/claude/statusline.omp.json"   "$HOME/.claude/statusline.omp.json"
chmod +x "$HOME/.claude/statusline.sh"

# Register Claude statusline in ~/.claude/settings.json (merge, with backup)
python3 - <<'PY'
import json, os, shutil, time
p = os.path.expanduser("~/.claude/settings.json")
data = {}
if os.path.exists(p):
    shutil.copy(p, p + ".bak." + time.strftime("%Y%m%d-%H%M%S"))
    try:
        with open(p) as f:
            data = json.load(f)
    except Exception:
        data = {}
data["statusLine"] = {
    "type": "command",
    "command": os.path.expanduser("~/.claude/statusline.sh"),
    "padding": 1,
}
with open(p, "w") as f:
    json.dump(data, f, indent=2)
print("  wrote", p)
PY

echo
echo "==> Manual step: append the snippet at zsh/zshrc-omp-snippet.sh to ~/.zshrc"
echo "    (or run:  cat $REPO_DIR/zsh/zshrc-omp-snippet.sh >> ~/.zshrc)"
echo
echo "==> Manual step: enable statusLine in ~/.copilot/settings.json"
echo "    See README.md section 'Copilot CLI settings'."
echo
echo "Done. Run 'exec zsh' to reload."
