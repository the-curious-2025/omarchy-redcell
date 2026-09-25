#!/usr/bin/env bash
# state.sh - RedCell's install ledger.
#
# Every tool RedCell installs is recorded here: package, category, source
# (pacman/blackarch/aur) and the timestamp of the install. This is what
# makes `--update` and `--uninstall` possible without ever touching a
# package RedCell didn't put there itself.
#
# Format: plain tab-separated text, one line per package. No jq, no
# dependency beyond bash itself:
#   package<TAB>category<TAB>source<TAB>iso8601-timestamp

set -uo pipefail

state_file() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/redcell"
  mkdir -p "$dir"
  echo "${dir}/installed.tsv"
}

# state_record <package> <category> <source>
state_record() {
  local pkg="$1" category="$2" source="$3"
  local file ts
  file="$(state_file)"
  ts="$(date -Is)"
  touch "$file"

  # Replace any existing line for this package, then append the fresh one.
  local tmp
  tmp="$(mktemp)"
  grep -v "^${pkg}	" "$file" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$file"
  printf '%s\t%s\t%s\t%s\n' "$pkg" "$category" "$source" "$ts" >> "$file"
}

# state_remove <package>
state_remove() {
  local pkg="$1"
  local file tmp
  file="$(state_file)"
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  grep -v "^${pkg}	" "$file" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$file"
}

# state_packages_for_categories <id> [<id> ...]
# Prints "package<TAB>source" for every tracked package whose recorded
# category is one of the given ids.
state_packages_for_categories() {
  local file
  file="$(state_file)"
  [[ -f "$file" ]] || return 0
  local id
  for id in "$@"; do
    awk -F'\t' -v cat="$id" '$2 == cat { print $1 "\t" $3 }' "$file"
  done
}

# state_all_packages - prints "package<TAB>source" for everything tracked.
state_all_packages() {
  local file
  file="$(state_file)"
  [[ -f "$file" ]] || return 0
  awk -F'\t' '{ print $1 "\t" $3 }' "$file"
}

state_count() {
  local file
  file="$(state_file)"
  [[ -f "$file" ]] || { echo 0; return 0; }
  wc -l < "$file" | tr -d ' '
}
