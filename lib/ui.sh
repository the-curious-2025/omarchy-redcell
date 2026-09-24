#!/usr/bin/env bash
# ui.sh - presentation layer for RedCell.
# All visual output goes through this file so the look stays consistent
# and can be reskinned in one place.
#
# Palette follows the Catppuccin Mocha tones common across Omarchy/Hyprland
# dotfiles, so the installer feels native to the desktop rather than bolted on.

set -uo pipefail

# ---- Palette --------------------------------------------------------------
readonly C_TEXT="#cdd6f4"
readonly C_SUBTLE="#7f849c"
readonly C_ACCENT="#cba6f7"   # mauve - primary brand accent
readonly C_INFO="#89b4fa"     # blue
readonly C_OK="#a6e3a1"       # green
readonly C_WARN="#f9e2af"     # yellow
readonly C_FAIL="#f38ba8"     # red
readonly C_PEACH="#fab387"

# ---- Low-level guards -------------------------------------------------------
ui_has_gum() { command -v gum >/dev/null 2>&1; }

# ---- Banner -----------------------------------------------------------------
ui_banner() {
  local banner_file="${REDCELL_ROOT}/assets/banner.txt"
  echo
  if [[ -f "$banner_file" ]]; then
    if ui_has_gum; then
      gum style --foreground "$C_ACCENT" "$(cat "$banner_file")"
    else
      printf '\033[38;2;203;166;247m%s\033[0m\n' "$(cat "$banner_file")"
    fi
  fi

  if ui_has_gum; then
    gum style \
      --foreground "$C_SUBTLE" \
      --align center --width 60 \
      "Omarchy -> Red Team Edition"
    gum style \
      --foreground "$C_SUBTLE" \
      --align center --width 60 \
      "v${REDCELL_VERSION}  -  github.com/${REDCELL_REPO_SLUG}"
  else
    printf '%s\n' "         Omarchy -> Red Team Edition"
    printf '%s\n\n' "         v${REDCELL_VERSION}"
  fi
  echo
}

# ---- Section headers ---------------------------------------------------------
ui_section() {
  local title="$1"
  echo
  if ui_has_gum; then
    gum style \
      --border normal --border-foreground "$C_ACCENT" \
      --foreground "$C_TEXT" --padding "0 2" --margin "0 0" \
      "$title"
  else
    printf -- '--- %s ---\n' "$title"
  fi
}

# ---- Status lines -------------------------------------------------------------
ui_info()    { ui_line "$C_INFO"  "[*]" "$1"; }
ui_ok()      { ui_line "$C_OK"    "[+]" "$1"; }
ui_warn()    { ui_line "$C_WARN"  "[!]" "$1"; }
ui_fail()    { ui_line "$C_FAIL"  "[-]" "$1"; }
ui_step()    { ui_line "$C_ACCENT" "[*]" "$1"; }

ui_line() {
  local color="$1" glyph="$2" msg="$3"
  if ui_has_gum; then
    gum style --foreground "$color" "${glyph} ${msg}"
  else
    printf '%s %s\n' "$glyph" "$msg"
  fi
}

# ---- Interactive prompts -----------------------------------------------------
# ui_confirm "question" -> return code 0 = yes, 1 = no
ui_confirm() {
  local question="$1"
  if ui_has_gum; then
    gum confirm --affirmative "Yes" --negative "No" \
      --selected.background "$C_ACCENT" "$question"
  else
    read -r -p "${question} [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
  fi
}

# ui_choose_categories: prints newline-separated chosen category ids on stdout
ui_choose_categories() {
  local -n _labels_ref="$1"   # associative array id -> label
  local ids=()
  mapfile -t ids < <(printf '%s\n' "${!_labels_ref[@]}" | sort)

  if ui_has_gum; then
    local display=()
    for id in "${ids[@]}"; do display+=("${_labels_ref[$id]}"); done
    local chosen
    chosen="$(printf '%s\n' "${display[@]}" | gum choose --no-limit \
      --selected.foreground "$C_ACCENT" \
      --cursor.foreground "$C_PEACH" \
      --header "Select categories  (space = toggle, enter = confirm)")"
    # map chosen labels back to ids
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      for id in "${ids[@]}"; do
        [[ "${_labels_ref[$id]}" == "$line" ]] && echo "$id"
      done
    done <<<"$chosen"
  else
    echo "Categories:" >&2
    local i=1
    for id in "${ids[@]}"; do
      printf '  %d) %s\n' "$i" "${_labels_ref[$id]}" >&2
      i=$((i + 1))
    done
    read -r -p "Enter numbers separated by spaces (e.g. 1 3 4): " picks
    for p in $picks; do
      local idx=$((p - 1))
      [[ $idx -ge 0 && $idx -lt ${#ids[@]} ]] && echo "${ids[$idx]}"
    done
  fi
}

# ui_spin "label" -- command args...
ui_spin() {
  local label="$1"; shift
  if ui_has_gum; then
    gum spin --spinner dot --title.foreground "$C_INFO" --title "$label" -- "$@"
  else
    printf '... %s\n' "$label"
    "$@"
  fi
}

# ---- Progress bar -------------------------------------------------------------
# ui_progress current total label
ui_progress() {
  local current="$1" total="$2" label="$3"
  local width=30
  local filled=$(( total > 0 ? current * width / total : 0 ))
  local empty=$(( width - filled ))
  local bar
  bar="$(printf '%*s' "$filled" '' | tr ' ' '#')"
  bar+="$(printf '%*s' "$empty" '' | tr ' ' '-')"
  if ui_has_gum; then
    gum style --foreground "$C_INFO" "[$bar] ${current}/${total}  ${label}"
  else
    printf '[%s] %d/%d  %s\n' "$bar" "$current" "$total" "$label"
  fi
}

# ---- Summary table ------------------------------------------------------------
ui_summary_table() {
  local ok_count="$1" fail_count="$2" skip_count="$3" elapsed="$4"
  echo
  ui_section "Run summary"
  ui_ok   "Installed : ${ok_count}"
  ui_warn "Skipped   : ${skip_count}  (already present)"
  ui_fail "Failed    : ${fail_count}"
  ui_info "Elapsed   : ${elapsed}"
  echo
}
