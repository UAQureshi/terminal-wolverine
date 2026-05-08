#!/usr/bin/env bash
# GitHub Copilot CLI statusline renderer (macOS / Linux).
# Reads JSON payload from stdin, exports COPILOT_STATUS_* env vars,
# then asks Oh My Posh to render the statusline theme next to it.
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

# Slurp Copilot's JSON payload.
PAYLOAD="$(cat)"

# Parse JSON with python3 (always available on macOS) and emit shell assignments.
EVAL_BLOCK="$(
    PAYLOAD="$PAYLOAD" python3 - <<'PY' 2>/dev/null || true
import json, os, sys, time

def fmt_tokens(v):
    if v is None:
        return "?"
    try:
        v = float(v)
    except Exception:
        return "?"
    if v >= 1_000_000:
        return f"{v/1_000_000:.1f}m"
    if v >= 1_000:
        return f"{v/1_000:.1f}k"
    return str(int(v))

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

def gauge(pct):
    if pct is None:
        return ".........."
    try:
        pct = float(pct)
    except Exception:
        return ".........."
    pct = max(0, min(100, round(pct)))
    filled = int(pct // 10)
    return "#" * filled + "." * (10 - filled)

def shq(s):
    return "'" + str(s).replace("'", "'\\''") + "'"

raw = os.environ.get("PAYLOAD", "")
try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}

ctx = data.get("context_window") or {}
cost = data.get("cost") or {}

current = ctx.get("current_context_tokens")
limit = ctx.get("displayed_context_limit")
pct = ctx.get("current_context_used_percentage")
if pct is None:
    pct = ctx.get("used_percentage")

added = cost.get("total_lines_added") or 0
removed = cost.get("total_lines_removed") or 0
try:
    added = int(added); removed = int(removed)
except Exception:
    added = removed = 0

cwd = data.get("cwd") or os.getcwd()
model_raw = data.get("model") or data.get("current_model") or ""
if isinstance(model_raw, dict):
    model = model_raw.get("display_name") or model_raw.get("id") or ""
else:
    model = str(model_raw)

# ---- per-session tracking (cost, tokens/min, file edits, tool calls) ----
sid = (
    data.get("session_id")
    or data.get("sessionId")
    or os.environ.get("COPILOT_SESSION_ID")
    or cwd
)
sid_safe = "".join(c if c.isalnum() else "_" for c in str(sid))[:80]
state_file = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"copilot_session_{sid_safe}.json")

try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {}

now = time.time()
start_ts = state.get("start_ts") or now
elapsed_min = max((now - start_ts) / 60.0, 1/60.0)  # min 1s to avoid div/0

try:
    cur_tokens = int(current or 0)
except Exception:
    cur_tokens = 0
peak_tokens = max(int(state.get("peak_tokens", 0)), cur_tokens)
tpm = int(peak_tokens / elapsed_min) if peak_tokens > 0 else 0

# cost: prefer Copilot-provided fields, else carry-over
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

# tool calls: prefer real list/count, else increment per status-line invocation as proxy
tool_count = int(state.get("tool_count", 0))
tools = data.get("tool_calls") or cost.get("tool_calls") or data.get("tools_used")
if isinstance(tools, list):
    tool_count = max(tool_count, len(tools))
elif isinstance(tools, (int, float)):
    tool_count = max(tool_count, int(tools))
else:
    tool_count += 1

# files edited: prefer real list, else increment when added/removed deltas grow
file_set = set(state.get("file_set", []))
files = (
    data.get("files_edited")
    or cost.get("files_edited")
    or data.get("edited_files")
    or cost.get("edited_files")
)
if isinstance(files, list):
    for f_ in files:
        if isinstance(f_, str):
            file_set.add(f_)
        elif isinstance(f_, dict):
            p = f_.get("path") or f_.get("file") or f_.get("name")
            if p:
                file_set.add(p)
    file_count = len(file_set)
else:
    file_count = int(state.get("file_count", 0))
    last_added = int(state.get("last_added", 0))
    last_removed = int(state.get("last_removed", 0))
    if added > last_added or removed > last_removed:
        file_count += 1

state.update({
    "start_ts": start_ts,
    "peak_tokens": peak_tokens,
    "cost_usd": cost_usd,
    "tool_count": tool_count,
    "file_count": file_count,
    "file_set": sorted(file_set),
    "last_added": added,
    "last_removed": removed,
})
try:
    with open(state_file, "w") as f:
        json.dump(state, f)
except Exception:
    pass

def fmt_count(n):
    n = int(n)
    if n >= 1000:
        return f"{n/1000:.1f}k"
    return str(n)

tpm_str = f"{fmt_count(tpm)}/m" if tpm > 0 else ""

context_str = f"{fmt_tokens(current)}/{fmt_tokens(limit)}"
gauge_str = gauge(pct)
duration_str = fmt_duration(cost.get("total_duration_ms"))
changes_str = f"+{added}/-{removed}" if (added or removed) else ""

print(f"export COPILOT_STATUS_CONTEXT={shq(context_str)}")
print(f"export COPILOT_STATUS_GAUGE={shq(gauge_str)}")
print(f"export COPILOT_STATUS_DURATION={shq(duration_str)}")
print(f"export COPILOT_STATUS_CHANGES={shq(changes_str)}")
print(f"export COPILOT_STATUS_MODEL={shq(model)}")
print(f"export COPILOT_STATUS_CWD={shq(cwd)}")
print(f"export COPILOT_STATUS_COST={shq(cost_str)}")
print(f"export COPILOT_STATUS_TPM={shq(tpm_str)}")
print(f"export COPILOT_STATUS_TOOLS={shq(fmt_count(tool_count))}")
print(f"export COPILOT_STATUS_FILES={shq(fmt_count(file_count))}")
PY
)"

if [ -n "$EVAL_BLOCK" ]; then
    eval "$EVAL_BLOCK"
else
    export COPILOT_STATUS_CONTEXT="?/?"
    export COPILOT_STATUS_GAUGE=".........."
    export COPILOT_STATUS_DURATION="00:00:00"
    export COPILOT_STATUS_CHANGES=""
    export COPILOT_STATUS_MODEL=""
    export COPILOT_STATUS_CWD="$PWD"
    export COPILOT_STATUS_COST=""
    export COPILOT_STATUS_TPM=""
    export COPILOT_STATUS_TOOLS="0"
    export COPILOT_STATUS_FILES="0"
fi

CWD="${COPILOT_STATUS_CWD:-$PWD}"

# Pull cached system stats (RAM/CPU/disk/load) written by the zsh precmd hook.
_OMP_SYSINFO_FILE="${TMPDIR:-/tmp}/omp_sysinfo_$UID"
if [ -r "$_OMP_SYSINFO_FILE" ]; then
    # shellcheck disable=SC1090
    . "$_OMP_SYSINFO_FILE"
    export OMP_RAM OMP_CPU OMP_DISK OMP_LOAD
fi

if [ -n "$OMP_BIN" ] && [ -f "$THEME" ]; then
    # --shell uni → no shell-specific prompt-escape wrappers (Copilot prints raw ANSI)
    OUTPUT="$("$OMP_BIN" print primary --config "$THEME" --pwd "$CWD" --shell uni 2>/dev/null || true)"
    if [ -n "$OUTPUT" ]; then
        printf '%s' "$OUTPUT"
        exit 0
    fi
fi

# Fallback if Oh My Posh is unavailable.
CHANGES=""
if [ -n "${COPILOT_STATUS_CHANGES:-}" ]; then
    CHANGES=" ${COPILOT_STATUS_CHANGES}"
fi
printf 'ctx %s %s | %s%s' \
    "$COPILOT_STATUS_CONTEXT" \
    "$COPILOT_STATUS_GAUGE" \
    "$COPILOT_STATUS_DURATION" \
    "$CHANGES"
