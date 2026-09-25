#!/usr/bin/env bash
# categories.sh - the category catalogue. Mirrors the Kali menu structure
# so anyone coming from Kali finds their bearings immediately.
#
# Add a category:
#   1. Add an id + label pair to CATEGORY_LABELS below.
#   2. Create data/categories/<id>.txt with lines: package|description

set -uo pipefail

declare -A CATEGORY_LABELS=(
  [recon]="Information Gathering"
  [vuln]="Vulnerability Analysis"
  [web]="Web Application Analysis"
  [password]="Password Attacks"
  [wireless]="Wireless Attacks"
  [exploitation]="Exploitation Tools"
  [sniffing]="Sniffing & Spoofing"
  [postexploit]="Post-Exploitation"
  [forensics]="Digital Forensics"
  [reversing]="Reverse Engineering"
)

categories_file() {
  echo "${REDCELL_ROOT}/data/categories/${1}.txt"
}

# categories_tools <id> - prints "package|description" lines, comments and
# blank lines stripped.
categories_tools() {
  local file
  file="$(categories_file "$1")"
  [[ -f "$file" ]] || return 0
  grep -vE '^\s*(#|$)' "$file"
}

categories_all_ids() {
  printf '%s\n' "${!CATEGORY_LABELS[@]}" | sort
}
