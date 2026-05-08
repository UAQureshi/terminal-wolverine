# ---- Oh My Posh prompt ----
export PATH="$HOME/.local/bin:$PATH"
if command -v oh-my-posh >/dev/null 2>&1; then
  # Cache RAM/load to a file refreshed in the background (no per-prompt blocking)
  _OMP_SYSINFO_FILE="${TMPDIR:-/tmp}/omp_sysinfo_$UID"
  _omp_sysinfo() {
    [[ -r "$_OMP_SYSINFO_FILE" ]] && source "$_OMP_SYSINFO_FILE"
    # Refresh in background if file is missing or older than 2s
    if [[ ! -f "$_OMP_SYSINFO_FILE" ]] || \
       [[ $(( $(date +%s) - $(stat -f %m "$_OMP_SYSINFO_FILE" 2>/dev/null || echo 0) )) -ge 2 ]]; then
      {
        local r="$(~/.config/oh-my-posh/mem.sh 2>/dev/null)"
        local l="$(~/.config/oh-my-posh/load.sh 2>/dev/null)"
        local d="$(~/.config/oh-my-posh/disk.sh 2>/dev/null)"
        local c="$(~/.config/oh-my-posh/cpu.sh 2>/dev/null)"
        printf 'export OMP_RAM=%q\nexport OMP_LOAD=%q\nexport OMP_DISK=%q\nexport OMP_CPU=%q\n' "$r" "$l" "$d" "$c" > "$_OMP_SYSINFO_FILE"
      } &!
    fi
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _omp_sysinfo
  _omp_sysinfo
  eval "$(oh-my-posh init zsh --config $HOME/.config/oh-my-posh/zsh.omp.json)"
fi
