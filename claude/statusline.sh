#!/usr/bin/env bash
# Claude Code statusline renderer (macOS / Linux).
# Reads JSON payload from stdin, exports CLAUDE_STATUS_* env vars,
# then asks Oh My Posh to render the matching pill theme.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/statusline.omp.json"

# Locate oh-my-posh: PATH first, then user-local, then Homebrew.
OMP_BIN=""
for cand in \
    "$(command -v oh-my-posh 2>/dev/null || true)" \
    "$HOME/.local/bin/oh-my-posh" \
    "/opt/homebrew/bin/oh-my-posh" \
    "/usr/local/bin/oh-my-posh"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then
        OMP_BIN="$cand"
        break
    fi
done

# Slurp Claude's JSON payload.
PAYLOAD="$(cat)"

EVAL_BLOCK="$(
    PAYLOAD="$PAYLOAD" python3 - <<'PY' 2>/dev/null || true
import json, os, time

def fmt_duration(ms):
    try:
        ms = float(ms)
    except Exception:
        return "00:00:00"
    if ms <= 0:
        return "00:00:00"
    s = int(ms // 1000)
    h, rem = divmod(s, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"

def fmt_count(n):
    n = int(n)
    if n >= 1000:
        return f"{n/1000:.1f}k"
    return str(n)

def shq(s):
    return "'" + str(s).replace("'", "'\\''") + "'"

raw = os.environ.get("PAYLOAD", "")
try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}

# --- core fields (Claude Code payload schema) ---
workspace = data.get("workspace") or {}
cwd = (
    workspace.get("current_dir")
    or data.get("cwd")
    or os.environ.get("CLAUDE_PROJECT_DIR")
    or os.getcwd()
)

model_raw = data.get("model") or {}
if isinstance(model_raw, dict):
    model = model_raw.get("display_name") or model_raw.get("id") or ""
else:
    model = str(model_raw)

cost = data.get("cost") or {}
added = int(cost.get("total_lines_added") or 0)
removed = int(cost.get("total_lines_removed") or 0)
duration_str = fmt_duration(cost.get("total_duration_ms"))
changes_str = f"+{added}/-{removed}" if (added or removed) else ""

# --- per-session tracking (cost, files edited, tool calls) ---
sid = data.get("session_id") or os.environ.get("CLAUDE_SESSION_ID") or cwd
sid_safe = "".join(c if c.isalnum() else "_" for c in str(sid))[:80]
state_file = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"claude_session_{sid_safe}.json")

try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {}

now = time.time()
start_ts = state.get("start_ts") or now
elapsed_min = max((now - start_ts) / 60.0, 1/60.0)

cost_usd = (
    cost.get("total_cost_usd")
    or cost.get("total_cost")
    or data.get("total_cost_usd")
    or data.get("total_cost")
)
if cost_usd is None:
    cost_usd = state.get("cost_usd")
try:
    cost_str = f"${float(cost_usd):.2f}" if cost_usd is not None else ""
except Exception:
    cost_str = ""

# tool calls: proxy = +1 per statusline tick (Claude doesn't expose this directly)
tool_count = int(state.get("tool_count", 0)) + 1

# files edited: increment when added/removed deltas grow
file_count = int(state.get("file_count", 0))
last_added = int(state.get("last_added", 0))
last_removed = int(state.get("last_removed", 0))
if added > last_added or removed > last_removed:
    file_count += 1

state.update({
    "start_ts": start_ts,
    "cost_usd": cost_usd,
    "tool_count": tool_count,
    "file_count": file_count,
    "last_added": added,
    "last_removed": removed,
})
try:
    with open(state_file, "w") as f:
        json.dump(state, f)
except Exception:
    pass

print(f"export CLAUDE_STATUS_MODEL={shq(model)}")
print(f"export CLAUDE_STATUS_CWD={shq(cwd)}")
print(f"export CLAUDE_STATUS_DURATION={shq(duration_str)}")
print(f"export CLAUDE_STATUS_CHANGES={shq(changes_str)}")
print(f"export CLAUDE_STATUS_COST={shq(cost_str)}")
print(f"export CLAUDE_STATUS_TOOLS={shq(fmt_count(tool_count))}")
print(f"export CLAUDE_STATUS_FILES={shq(fmt_count(file_count))}")
PY
)"

if [ -n "$EVAL_BLOCK" ]; then
    eval "$EVAL_BLOCK"
else
    export CLAUDE_STATUS_MODEL=""
    export CLAUDE_STATUS_CWD="$PWD"
    export CLAUDE_STATUS_DURATION="00:00:00"
    export CLAUDE_STATUS_CHANGES=""
    export CLAUDE_STATUS_COST=""
    export CLAUDE_STATUS_TOOLS="0"
    export CLAUDE_STATUS_FILES="0"
fi

CWD="${CLAUDE_STATUS_CWD:-$PWD}"

# Pull cached system stats (RAM/CPU/disk) written by the zsh precmd hook.
_OMP_SYSINFO_FILE="${TMPDIR:-/tmp}/omp_sysinfo_$UID"
if [ -r "$_OMP_SYSINFO_FILE" ]; then
    # shellcheck disable=SC1090
    . "$_OMP_SYSINFO_FILE"
    export OMP_RAM OMP_CPU OMP_DISK OMP_LOAD
fi

if [ -n "$OMP_BIN" ] && [ -f "$THEME" ]; then
    OUTPUT="$("$OMP_BIN" print primary --config "$THEME" --pwd "$CWD" --shell uni 2>/dev/null || true)"
    if [ -n "$OUTPUT" ]; then
        printf '%s' "$OUTPUT"
        exit 0
    fi
fi

# Fallback plain text.
printf 'claude %s | %s | %s%s' \
    "${CLAUDE_STATUS_MODEL:-?}" \
    "${CLAUDE_STATUS_DURATION}" \
    "${CLAUDE_STATUS_COST:-\$0.00}" \
    "${CLAUDE_STATUS_CHANGES:+ ${CLAUDE_STATUS_CHANGES}}"
