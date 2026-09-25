#!/usr/bin/env bash
#
# RedCell - turns a fresh Omarchy install into a penetration testing
# workstation, one category at a time.
#
# Usage:
#   ./install.sh                          interactive category picker
#   ./install.sh --categories=recon,web   skip the picker
#   ./install.sh --update                 upgrade every tool RedCell installed
#   ./install.sh --uninstall=web,recon    remove RedCell-tracked tools in these categories
#   ./install.sh --status                 show what RedCell has installed
#   ./install.sh --list                   print every tool and exit
#   ./install.sh --dry-run                simulate, change nothing
#   ./install.sh --yes                    skip confirmation prompts
#   ./install.sh --help
#
# Safe to re-run: already-installed tools are detected and skipped.
# RedCell only ever touches packages it installed itself (tracked in
# ~/.local/state/redcell/installed.tsv) when updating or uninstalling.

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Paths & constants
# ---------------------------------------------------------------------------
REDCELL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly REDCELL_ROOT
readonly REDCELL_VERSION="2.0.0"
readonly REDCELL_REPO_SLUG="the-curious-2025/omarchy-redcell"

readonly REDCELL_LOG_DIR="${REDCELL_ROOT}/logs"
mkdir -p "$REDCELL_LOG_DIR"
_run_id="$(date +%Y%m%d-%H%M%S)"
readonly REDCELL_RUN_ID="$_run_id"
unset _run_id
readonly REDCELL_LOG_FILE="${REDCELL_LOG_DIR}/redcell-${REDCELL_RUN_ID}.log"
readonly REDCELL_REPORT_FILE="${REDCELL_LOG_DIR}/redcell-${REDCELL_RUN_ID}-report.md"
touch "$REDCELL_LOG_FILE"

DRY_RUN=0
ASSUME_YES=0
CATEGORIES_ARG=""
LIST_ONLY=0
STATUS_ONLY=0
UPDATE_MODE=0
UNINSTALL_ARG=""

# ---------------------------------------------------------------------------
# Load library
# ---------------------------------------------------------------------------
# shellcheck source=lib/ui.sh
source "${REDCELL_ROOT}/lib/ui.sh"
# shellcheck source=lib/resolver.sh
source "${REDCELL_ROOT}/lib/resolver.sh"
# shellcheck source=lib/categories.sh
source "${REDCELL_ROOT}/lib/categories.sh"
# shellcheck source=lib/state.sh
source "${REDCELL_ROOT}/lib/state.sh"

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
  --update              Upgrade every tool RedCell has installed.
  --uninstall=a,b,c     Remove RedCell-tracked tools in these categories.
  --status              Show what RedCell has installed, by category.
  --list                List every tool in every category, then exit.
  --dry-run             Simulate the run without changing anything.
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
    --status) STATUS_ONLY=1 ;;
    --update) UPDATE_MODE=1 ;;
    --categories=*) CATEGORIES_ARG="${arg#*=}" ;;
    --uninstall=*) UNINSTALL_ARG="${arg#*=}" ;;
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
# --status mode: read-only report of what RedCell has installed
# ---------------------------------------------------------------------------
if [[ "$STATUS_ONLY" == "1" ]]; then
  ui_banner
  total="$(state_count)"
  ui_section "RedCell-tracked tools: ${total}"
  if [[ "$total" -eq 0 ]]; then
    ui_info "Nothing tracked yet. Run an install first."
    exit 0
  fi
  while IFS= read -r id; do
    count="$(state_packages_for_categories "$id" | wc -l | tr -d ' ')"
    [[ "$count" -eq 0 ]] && continue
    printf '  %-28s %s\n' "${CATEGORY_LABELS[$id]}" "$count"
  done < <(categories_all_ids)
  echo
  ui_info "Ledger: $(state_file)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Environment sanity checks (everything below can touch the system)
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

ui_banner

# ---------------------------------------------------------------------------
# --uninstall mode
# ---------------------------------------------------------------------------
if [[ -n "$UNINSTALL_ARG" ]]; then
  declare -a UNINSTALL_IDS=()
  IFS=',' read -r -a UNINSTALL_IDS <<<"$UNINSTALL_ARG"
  for id in "${UNINSTALL_IDS[@]}"; do
    if [[ -z "${CATEGORY_LABELS[$id]:-}" ]]; then
      ui_fail "Unknown category: ${id}"
      exit 1
    fi
  done

  declare -A TO_REMOVE=()
  declare -a REMOVE_ORDER=()
  while IFS=$'\t' read -r pkg src; do
    [[ -z "$pkg" ]] && continue
    if [[ -z "${TO_REMOVE[$pkg]:-}" ]]; then
      REMOVE_ORDER+=("$pkg")
    fi
    TO_REMOVE["$pkg"]="$src"
  done < <(state_packages_for_categories "${UNINSTALL_IDS[@]}")

  if [[ "${#REMOVE_ORDER[@]}" -eq 0 ]]; then
    ui_warn "No RedCell-tracked tools found in: ${UNINSTALL_ARG}"
    exit 0
  fi

  ui_section "RedCell-tracked tools in: ${UNINSTALL_ARG}"
  for pkg in "${REMOVE_ORDER[@]}"; do
    printf '  - %s\n' "$pkg"
  done
  echo

  if [[ "$ASSUME_YES" != "1" ]]; then
    ui_confirm "Remove ${#REMOVE_ORDER[@]} tool(s)? Only tools RedCell installed are touched." \
      || { ui_warn "Cancelled."; exit 0; }
  fi

  REMOVED_COUNT=0
  REMOVE_FAILED_COUNT=0
  for pkg in "${REMOVE_ORDER[@]}"; do
    if [[ "$DRY_RUN" == "1" ]]; then
      ui_ok "${pkg}  (dry-run, would remove)"
      REMOVED_COUNT=$((REMOVED_COUNT + 1))
      continue
    fi
    # shellcheck disable=SC2024
    if sudo pacman -R --noconfirm "$pkg" >>"$REDCELL_LOG_FILE" 2>&1; then
      ui_ok "${pkg}  removed"
      state_remove "$pkg"
      REMOVED_COUNT=$((REMOVED_COUNT + 1))
    else
      ui_fail "${pkg}  - removal failed (see log)"
      REMOVE_FAILED_COUNT=$((REMOVE_FAILED_COUNT + 1))
    fi
  done

  echo
  ui_info "Removed: ${REMOVED_COUNT}   Failed: ${REMOVE_FAILED_COUNT}"
  exit 0
fi

# ---------------------------------------------------------------------------
# --update mode
# ---------------------------------------------------------------------------
if [[ "$UPDATE_MODE" == "1" ]]; then
  declare -A PACMAN_PKGS=()
  declare -A AUR_PKGS=()
  TRACKED_ANY=0
  while IFS=$'\t' read -r pkg src; do
    [[ -z "$pkg" ]] && continue
    TRACKED_ANY=1
    if [[ "$src" == "aur" ]]; then
      AUR_PKGS["$pkg"]=1
    else
      PACMAN_PKGS["$pkg"]=1
    fi
  done < <(state_all_packages)

  if [[ "$TRACKED_ANY" -eq 0 ]]; then
    ui_warn "Nothing tracked yet. Run an install first."
    exit 0
  fi

  ui_section "Updating $(state_count) RedCell-tracked tool(s)"

  if [[ "$DRY_RUN" == "1" ]]; then
    ui_info "Dry run - would sync and upgrade tracked tools."
    exit 0
  fi

  ui_step "Syncing package databases"
  # shellcheck disable=SC2024
  sudo pacman -Sy --noconfirm >>"$REDCELL_LOG_FILE" 2>&1 \
    || ui_warn "pacman -Sy reported an issue (see log)"

  if [[ "${#PACMAN_PKGS[@]}" -gt 0 ]]; then
    ui_step "Updating ${#PACMAN_PKGS[@]} pacman/BlackArch tool(s)"
    # shellcheck disable=SC2024
    if sudo pacman -S --needed --noconfirm "${!PACMAN_PKGS[@]}" >>"$REDCELL_LOG_FILE" 2>&1; then
      ui_ok "pacman/BlackArch tools up to date."
    else
      ui_fail "Some pacman/BlackArch tools failed to update (see log)."
    fi
  fi

  if [[ "${#AUR_PKGS[@]}" -gt 0 ]]; then
    resolver_bootstrap_aur_helper || true
    if [[ -n "$AUR_HELPER" ]]; then
      ui_step "Updating ${#AUR_PKGS[@]} AUR tool(s)"
      if "$AUR_HELPER" -S --needed --noconfirm "${!AUR_PKGS[@]}" >>"$REDCELL_LOG_FILE" 2>&1; then
        ui_ok "AUR tools up to date."
      else
        ui_fail "Some AUR tools failed to update (see log)."
      fi
    else
      ui_warn "No AUR helper - skipped ${#AUR_PKGS[@]} AUR tool(s)."
    fi
  fi

  ui_info "Full log written to: ${REDCELL_LOG_FILE}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Normal install: boot sequence
# ---------------------------------------------------------------------------
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
# Category selection (labels show a live tool count per category)
# ---------------------------------------------------------------------------
declare -A LABELS_WITH_COUNTS=()
while IFS= read -r id; do
  count="$(categories_tools "$id" | wc -l | tr -d ' ')"
  # shellcheck disable=SC2034  # read via nameref inside ui_choose_categories
  LABELS_WITH_COUNTS["$id"]="${CATEGORY_LABELS[$id]} (${count})"
done < <(categories_all_ids)

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
  done < <(ui_choose_categories LABELS_WITH_COUNTS)
fi

if [[ "${#SELECTED_IDS[@]}" -eq 0 ]]; then
  ui_warn "Nothing selected. Exiting."
  exit 0
fi

# ---------------------------------------------------------------------------
# Build the deduplicated tool list (first category seen "owns" a tool
# that appears in more than one, for state-tracking purposes)
# ---------------------------------------------------------------------------
declare -A TOOL_DESC=()      # package -> description
declare -A TOOL_CATEGORY=()  # package -> owning category id
declare -a TOOL_ORDER=()     # insertion order, de-duplicated

for id in "${SELECTED_IDS[@]}"; do
  while IFS='|' read -r pkg desc; do
    [[ -z "$pkg" ]] && continue
    if [[ -z "${TOOL_DESC[$pkg]:-}" ]]; then
      TOOL_ORDER+=("$pkg")
      TOOL_CATEGORY["$pkg"]="$id"
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
declare -a INSTALLED_LIST=()
declare -a SKIPPED_LIST=()
INSTALLED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0
CURRENT=0

for pkg in "${TOOL_ORDER[@]}"; do
  CURRENT=$((CURRENT + 1))
  ui_progress "$CURRENT" "$TOTAL" "$pkg"

  if resolver_install "$pkg"; then
    case "$RESOLVER_LAST_STATUS" in
      installed)
        ui_ok "${pkg}  (${RESOLVER_LAST_SOURCE})"
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        INSTALLED_LIST+=("${pkg} (${RESOLVER_LAST_SOURCE})")
        if [[ "$DRY_RUN" != "1" ]]; then
          state_record "$pkg" "${TOOL_CATEGORY[$pkg]}" "$RESOLVER_LAST_SOURCE"
        fi
        ;;
      skipped)
        ui_warn "${pkg}  already installed"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        SKIPPED_LIST+=("$pkg")
        ;;
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

# ---------------------------------------------------------------------------
# Write the run report
# ---------------------------------------------------------------------------
{
  echo "# RedCell run report"
  echo
  echo "- Date: $(date -Is)"
  echo "- Mode: $([[ "$DRY_RUN" == "1" ]] && echo "dry-run" || echo "live")"
  echo "- Categories: ${SELECTED_IDS[*]}"
  echo "- Total tools considered: ${TOTAL}"
  echo "- Installed: ${INSTALLED_COUNT}"
  echo "- Skipped (already present): ${SKIPPED_COUNT}"
  echo "- Failed: ${FAILED_COUNT}"
  echo "- Elapsed: ${ELAPSED}"
  echo
  echo "## Installed"
  if [[ "${#INSTALLED_LIST[@]}" -eq 0 ]]; then
    echo "(none)"
  else
    for line in "${INSTALLED_LIST[@]}"; do echo "- ${line}"; done
  fi
  echo
  echo "## Skipped"
  if [[ "${#SKIPPED_LIST[@]}" -eq 0 ]]; then
    echo "(none)"
  else
    for line in "${SKIPPED_LIST[@]}"; do echo "- ${line}"; done
  fi
  echo
  echo "## Failed"
  if [[ "${#FAILED_TOOLS[@]}" -eq 0 ]]; then
    echo "(none)"
  else
    for line in "${FAILED_TOOLS[@]}"; do echo "- ${line}"; done
  fi
} > "$REDCELL_REPORT_FILE"

ui_info "Full log written to: ${REDCELL_LOG_FILE}"
ui_info "Run report written to: ${REDCELL_REPORT_FILE}"
exit 0
