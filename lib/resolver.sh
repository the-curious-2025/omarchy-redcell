#!/usr/bin/env bash
# resolver.sh - decides where a tool comes from and installs it.
#
# Resolution order for every tool name:
#   1. Already installed?                -> skip
#   2. Official Arch repos (pacman -Si)  -> pacman -S
#   3. BlackArch repo (if enabled)       -> pacman -S (same call, repo just
#                                            widens what pacman -Si can see)
#   4. AUR (via the detected AUR helper) -> yay/paru -S
#   5. Not found anywhere                -> recorded as failed, never fatal
#
# Every install attempt is isolated: a single tool failing must never stop
# the run. Callers only ever see RESOLVER_LAST_STATUS afterwards.

set -uo pipefail

AUR_HELPER=""
BLACKARCH_ENABLED=0

# Populated by resolver_install for the caller (install.sh) to inspect
# after every call. Read across files, so shellcheck can't see the usage.
# shellcheck disable=SC2034
RESOLVER_LAST_STATUS=""   # installed | skipped | failed
# shellcheck disable=SC2034
RESOLVER_LAST_SOURCE=""   # pacman | blackarch | aur | none
# shellcheck disable=SC2034
RESOLVER_LAST_REASON=""   # human-readable, only set on failure

resolver_detect_aur_helper() {
  if command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
  elif command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
  else
    AUR_HELPER=""
  fi
}

# Bootstraps `paru` from the AUR if the user has neither paru nor yay.
# Requires base-devel + git, which are near-universal on Arch/Omarchy
# installs already, but we check anyway.
resolver_bootstrap_aur_helper() {
  resolver_detect_aur_helper
  [[ -n "$AUR_HELPER" ]] && return 0

  ui_warn "No AUR helper found (paru/yay). RedCell needs one for AUR-only tools."
  if [[ "${ASSUME_YES:-0}" != "1" ]] && ! ui_confirm "Build and install 'paru' from source now?"; then
    ui_warn "Continuing without an AUR helper - AUR-only tools will be skipped."
    return 1
  fi

  for dep in git base-devel; do
    if ! pacman -Qg "$dep" >/dev/null 2>&1 && ! pacman -Qi "$dep" >/dev/null 2>&1; then
      ui_step "Installing build dependency: ${dep}"
      sudo pacman -S --needed --noconfirm "$dep" || true
    fi
  done

  local build_dir
  build_dir="$(mktemp -d)"
  if ui_spin "Cloning paru" git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$build_dir/paru-bin"; then
    (cd "$build_dir/paru-bin" && makepkg -si --noconfirm) && AUR_HELPER="paru"
  fi
  rm -rf "$build_dir"

  if [[ -z "$AUR_HELPER" ]]; then
    ui_fail "Could not bootstrap an AUR helper. AUR-only tools will be skipped."
    return 1
  fi
  ui_ok "AUR helper ready: ${AUR_HELPER}"
  return 0
}

# Enables the BlackArch repo via its official strap script, if not present
# already in pacman.conf. Safe to call repeatedly.
resolver_enable_blackarch() {
  if grep -q '^\[blackarch\]' /etc/pacman.conf 2>/dev/null; then
    BLACKARCH_ENABLED=1
    return 0
  fi

  ui_warn "BlackArch repo is not enabled. It widens tool coverage significantly."
  if [[ "${ASSUME_YES:-0}" != "1" ]] && ! ui_confirm "Enable the BlackArch repo now (adds one line to pacman.conf)?"; then
    BLACKARCH_ENABLED=0
    return 1
  fi

  local tmp_strap
  tmp_strap="$(mktemp)"
  if ui_spin "Fetching BlackArch strap script" curl -fsSL https://blackarch.org/strap.sh -o "$tmp_strap"; then
    chmod +x "$tmp_strap"
    if ui_spin "Running strap.sh" sudo "$tmp_strap"; then
      BLACKARCH_ENABLED=1
      ui_ok "BlackArch repo enabled."
    else
      ui_fail "strap.sh failed - continuing with pacman/AUR only."
      BLACKARCH_ENABLED=0
    fi
  else
    ui_fail "Could not download strap.sh - continuing with pacman/AUR only."
    BLACKARCH_ENABLED=0
  fi
  rm -f "$tmp_strap"
}

resolver_is_installed() {
  pacman -Qi "$1" >/dev/null 2>&1
}

resolver_exists_in_pacman() {
  pacman -Si "$1" >/dev/null 2>&1
}

resolver_exists_in_aur() {
  [[ -n "$AUR_HELPER" ]] || return 1
  "$AUR_HELPER" -Si "$1" >/dev/null 2>&1
}

# resolver_install <package_name>
# Sets RESOLVER_LAST_STATUS / RESOLVER_LAST_SOURCE / RESOLVER_LAST_REASON.
# Never exits non-zero in a way that should kill the caller's loop -
# callers check RESOLVER_LAST_STATUS instead.
resolver_install() {
  local pkg="$1"
  RESOLVER_LAST_STATUS=""
  RESOLVER_LAST_SOURCE=""
  RESOLVER_LAST_REASON=""

  if resolver_is_installed "$pkg"; then
    RESOLVER_LAST_STATUS="skipped"
    RESOLVER_LAST_SOURCE="local"
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    RESOLVER_LAST_STATUS="installed"
    RESOLVER_LAST_SOURCE="dry-run"
    return 0
  fi

  if resolver_exists_in_pacman "$pkg"; then
    # (log redirect runs as the calling user, not root - intentional; see
    # the equivalent gum-install comment in install.sh)
    # shellcheck disable=SC2024
    if sudo pacman -S --needed --noconfirm "$pkg" >>"$REDCELL_LOG_FILE" 2>&1; then
      RESOLVER_LAST_STATUS="installed"
      RESOLVER_LAST_SOURCE=$([[ "$BLACKARCH_ENABLED" == "1" ]] && echo "blackarch/pacman" || echo "pacman")
      return 0
    else
      RESOLVER_LAST_STATUS="failed"
      RESOLVER_LAST_REASON="pacman install failed (see log)"
      return 1
    fi
  fi

  if resolver_exists_in_aur "$pkg"; then
    if "$AUR_HELPER" -S --needed --noconfirm "$pkg" >>"$REDCELL_LOG_FILE" 2>&1; then
      RESOLVER_LAST_STATUS="installed"
      RESOLVER_LAST_SOURCE="aur"
      return 0
    else
      RESOLVER_LAST_STATUS="failed"
      RESOLVER_LAST_REASON="AUR build failed (see log)"
      return 1
    fi
  fi

  # shellcheck disable=SC2034  # read by install.sh after this call returns
  RESOLVER_LAST_STATUS="failed"
  # shellcheck disable=SC2034
  RESOLVER_LAST_SOURCE="none"
  # shellcheck disable=SC2034
  RESOLVER_LAST_REASON="not found in pacman, BlackArch, or AUR"
  return 1
}
