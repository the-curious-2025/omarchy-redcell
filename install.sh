#!/usr/bin/env bash
#
# RedCell - turns a fresh Omarchy install into a penetration testing
# workstation, one category at a time.
#
# Usage:
#   ./install.sh                          interactive category picker
#   ./install.sh --categories=recon,web   skip the picker
#   ./install.sh --list                   print every tool and exit
#   ./install.sh --dry-run                simulate, install nothing
#   ./install.sh --yes                    skip confirmation prompts
#   ./install.sh --help
#
# Safe to re-run: already-installed tools are detected and skipped.

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Paths & constants
# ---------------------------------------------------------------------------
REDCELL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly REDCELL_ROOT
readonly REDCELL_VERSION="1.0.0"
readonly REDCELL_REPO_SLUG="YOUR-GITHUB-USERNAME/omarchy-redcell"

readonly REDCELL_LOG_DIR="${REDCELL_ROOT}/logs"
mkdir -p "$REDCELL_LOG_DIR"
_log_timestamp="$(date +%Y%m%d-%H%M%S)"
readonly REDCELL_LOG_FILE="${REDCELL_LOG_DIR}/redcell-${_log_timestamp}.log"
unset _log_timestamp
touch "$REDCELL_LOG_FILE"

DRY_RUN=0
ASSUME_YES=0
CATEGORIES_ARG=""
LIST_ONLY=0

# ---------------------------------------------------------------------------
# Load library
# ---------------------------------------------------------------------------
# shellcheck source=lib/ui.sh
source "${REDCELL_ROOT}/lib/ui.sh"
# shellcheck source=lib/resolver.sh
source "${REDCELL_ROOT}/lib/resolver.sh"
# shellcheck source=lib/categories.sh
source "${REDCELL_ROOT}/lib/categories.sh"

trap 'ui_fail "Something went wrong (line $LINENO). Full log: ${REDCELL_LOG_FILE}"; exit 1' ERR

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
print_help() {
  cat <<EOF
RedCell ${REDCELL_VERSION} - Omarchy Red Team Edition

Usage: $(basename "$0") [options]

Options:
  --categories=a,b,c   Install these categories non-interactively.
                        Valid ids: $(categories_all_ids | tr '\n' ',' | sed 's/,$//')
  --list                List every tool in every category, then exit.
  --dry-run             Simulate the run without installing anything.
  --yes                 Skip confirmation prompts.
  --help                Show this help and exit.
  --version             Show version and exit.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    --list) LIST_ONLY=1 ;;
    --categories=*) CATEGORIES_ARG="${arg#*=}" ;;
    --help) print_help; exit 0 ;;
    --version) echo "RedCell ${REDCELL_VERSION}"; exit 0 ;;
    *)
      echo "Unknown option: ${arg}" >&2
      print_help
      exit 1
      ;;
  esac
done
export DRY_RUN

# ---------------------------------------------------------------------------
# --list mode: print catalogue and exit, no environment checks needed
# ---------------------------------------------------------------------------
if [[ "$LIST_ONLY" == "1" ]]; then
  ui_banner
  while IFS= read -r id; do
    ui_section "${CATEGORY_LABELS[$id]}"
    while IFS='|' read -r pkg desc; do
      printf '  %-18s %s\n' "$pkg" "$desc"
    done < <(categories_tools "$id")
  done < <(categories_all_ids)
  exit 0
fi

# ---------------------------------------------------------------------------
# Environment sanity checks
# ---------------------------------------------------------------------------
if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this as your normal user, not root. RedCell calls sudo itself"
  echo "only where it's needed, and AUR builds refuse to run as root anyway."
  exit 1
fi

if [[ "${DRY_RUN}" != "1" ]] && ! command -v pacman >/dev/null 2>&1; then
  echo "RedCell targets Arch-based systems (Omarchy included) - pacman was"
  echo "not found. Use --dry-run to preview the script on another distro."
  exit 1
fi

if [[ "${DRY_RUN}" != "1" ]] && ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required (RedCell never asks for your password directly)."
  exit 1
fi

# ---------------------------------------------------------------------------
# Boot sequence
# ---------------------------------------------------------------------------
ui_banner

# gum makes everything below nicer but nothing hard-requires it.
if ! ui_has_gum && [[ "${DRY_RUN}" != "1" ]]; then
  ui_warn "gum (the UI toolkit RedCell renders with) isn't installed."
  if [[ "$ASSUME_YES" == "1" ]] || ui_confirm "Install gum now for the full experience?"; then
    # The log file is user-owned; sudo only elevates pacman, the append
    # redirect itself still runs as the calling user. That's intentional.
    # shellcheck disable=SC2024
    if sudo pacman -S --needed --noconfirm gum >>"$REDCELL_LOG_FILE" 2>&1; then
      ui_ok "gum installed."
    else
      ui_warn "Could not install gum automatically - continuing in plain-text mode."
    fi
  fi
fi

if [[ "${DRY_RUN}" != "1" ]]; then
  resolver_enable_blackarch || true
  resolver_bootstrap_aur_helper || true
else
  ui_info "Dry run - skipping BlackArch/AUR bootstrap."
fi

# ---------------------------------------------------------------------------
# Category selection
# ---------------------------------------------------------------------------
declare -a SELECTED_IDS=()

if [[ -n "$CATEGORIES_ARG" ]]; then
  IFS=',' read -r -a SELECTED_IDS <<<"$CATEGORIES_ARG"
  for id in "${SELECTED_IDS[@]}"; do
    if [[ -z "${CATEGORY_LABELS[$id]:-}" ]]; then
      ui_fail "Unknown category: ${id}"
      exit 1
    fi
  done
else
  ui_section "Choose what to install"
  while IFS= read -r id; do
    SELECTED_IDS+=("$id")
  done < <(ui_choose_categories CATEGORY_LABELS)
fi

if [[ "${#SELECTED_IDS[@]}" -eq 0 ]]; then
  ui_warn "Nothing selected. Exiting."
  exit 0
fi

# ---------------------------------------------------------------------------
# Build the deduplicated tool list
# ---------------------------------------------------------------------------
declare -A TOOL_DESC=()   # package -> description
declare -a TOOL_ORDER=()  # insertion order, de-duplicated

for id in "${SELECTED_IDS[@]}"; do
  while IFS='|' read -r pkg desc; do
    [[ -z "$pkg" ]] && continue
    if [[ -z "${TOOL_DESC[$pkg]:-}" ]]; then
      TOOL_ORDER+=("$pkg")
    fi
    TOOL_DESC["$pkg"]="$desc"
  done < <(categories_tools "$id")
done

TOTAL="${#TOOL_ORDER[@]}"
if [[ "$TOTAL" -eq 0 ]]; then
  ui_warn "Selected categories have no tools defined. Nothing to do."
  exit 0
fi

ui_section "Ready to install ${TOTAL} tools"
for pkg in "${TOOL_ORDER[@]}"; do
  printf '  - %-18s %s\n' "$pkg" "${TOOL_DESC[$pkg]}"
done
echo

if [[ "$ASSUME_YES" != "1" ]]; then
  ui_confirm "Proceed?" || { ui_warn "Cancelled."; exit 0; }
fi

# ---------------------------------------------------------------------------
# Install loop
# ---------------------------------------------------------------------------
START_TIME="$(date +%s)"
declare -a FAILED_TOOLS=()
INSTALLED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0
CURRENT=0

for pkg in "${TOOL_ORDER[@]}"; do
  CURRENT=$((CURRENT + 1))
  ui_progress "$CURRENT" "$TOTAL" "$pkg"

  if resolver_install "$pkg"; then
    case "$RESOLVER_LAST_STATUS" in
      installed) ui_ok "${pkg}  (${RESOLVER_LAST_SOURCE})"; INSTALLED_COUNT=$((INSTALLED_COUNT + 1)) ;;
      skipped)   ui_warn "${pkg}  already installed"; SKIPPED_COUNT=$((SKIPPED_COUNT + 1)) ;;
    esac
  else
    ui_fail "${pkg}  - ${RESOLVER_LAST_REASON}"
    FAILED_TOOLS+=("${pkg}: ${RESOLVER_LAST_REASON}")
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done

END_TIME="$(date +%s)"
ELAPSED="$(( END_TIME - START_TIME ))s"

ui_summary_table "$INSTALLED_COUNT" "$FAILED_COUNT" "$SKIPPED_COUNT" "$ELAPSED"

if [[ "$FAILED_COUNT" -gt 0 ]]; then
  ui_section "Failed tools"
  for line in "${FAILED_TOOLS[@]}"; do
    ui_fail "$line"
  done
  echo
fi

ui_info "Full log written to: ${REDCELL_LOG_FILE}"
exit 0
