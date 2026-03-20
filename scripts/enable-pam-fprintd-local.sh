#!/usr/bin/env bash
set -euo pipefail

ALLOW_NON_ROOT="${PYTHON_VALIDITY_VFS0090_FIX_ALLOW_NON_ROOT:-0}"
PAM_DIR="${PYTHON_VALIDITY_VFS0090_FIX_PAM_DIR:-/etc/pam.d}"
DISPLAY_MANAGER_LINK="${PYTHON_VALIDITY_VFS0090_FIX_DISPLAY_MANAGER_LINK:-/etc/systemd/system/display-manager.service}"

if [[ ${ALLOW_NON_ROOT} != 1 && ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

PAM_LINE='auth       sufficient   pam_fprintd.so max-tries=3 timeout=10'
include_su=0

while (( $# > 0 )); do
  case "$1" in
    --include-su)
      include_su=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

detect_display_manager_target() {
  local target
  target="$(basename "$(readlink -f "${DISPLAY_MANAGER_LINK}" 2>/dev/null || true)" .service)"
  case "${target}" in
    lightdm|sddm|lxdm)
      printf '%s\n' "${target}"
      ;;
    *)
      return 1
      ;;
  esac
}

patch_target() {
  local target="$1"
  local anchor="$2"
  local path="${PAM_DIR}/${target}"
  local backup="${path}.fprintd-backup.orig"
  local tmp

  if [[ ! -f "${path}" ]]; then
    return 0
  fi

  if [[ ! -f "${backup}" ]]; then
    install -D -m 0644 "${path}" "${backup}"
  fi
  tmp="$(mktemp)"

  awk -v line="${PAM_LINE}" -v anchor="${anchor}" '
    BEGIN { inserted = 0 }
    $0 ~ /^[[:space:]]*#auth[[:space:]]+sufficient[[:space:]]+pam_fprintd[.]so/ {
      print line
      inserted = 1
      next
    }
    $0 == line {
      inserted = 1
    }
    inserted == 0 && $0 ~ anchor {
      print line
      inserted = 1
    }
    { print }
    END {
      if (inserted == 0) {
        print line
      }
    }
  ' "${path}" > "${tmp}"

  install -m 0644 "${tmp}" "${path}"
  rm -f "${tmp}"
  echo "Enabled pam_fprintd in ${path}"
}

patch_target "sudo" '^auth[[:space:]]+include[[:space:]]+system-auth$'
patch_target "polkit-1" '^auth[[:space:]]+include[[:space:]]+system-auth$'
patch_target "login" '^auth[[:space:]]+include[[:space:]]+system-local-login$'
patch_target "greetd" '^auth[[:space:]]+include[[:space:]]+system-local-login$'
patch_target "budgie-screensaver" '^auth[[:space:]]+include[[:space:]]+system-auth$'
patch_target "cinnamon-screensaver" '^auth[[:space:]]+include[[:space:]]+system-auth$'
patch_target "mate-screensaver" '^auth[[:space:]]+include[[:space:]]+system-auth$'
patch_target "xfce4-screensaver" '^auth[[:space:]]+include[[:space:]]+system-auth$'
patch_target "xscreensaver" '^auth[[:space:]]+include[[:space:]]+system-local-login$'
patch_target "ukui-screensaver-qt" '^auth[[:space:]]+include[[:space:]]+system-local-login$'
patch_target "vlock" '^auth[[:space:]]+required[[:space:]]+pam_unix[.]so$'

if [[ ${include_su} -eq 1 ]]; then
  patch_target "su" '^auth[[:space:]]+required[[:space:]]+pam_unix[.]so$'
  patch_target "su-l" '^auth[[:space:]]+required[[:space:]]+pam_unix[.]so$'
fi

if dm_target="$(detect_display_manager_target)"; then
  patch_target "${dm_target}" '^auth[[:space:]]+include[[:space:]]+system-login$'
fi

echo
echo "Local PAM fingerprint integration enabled."
echo "Suggested checks:"
echo "  sudo -k && sudo true"
echo "  sudo -i"
echo "  pkexec true"
if [[ ${include_su} -eq 1 ]]; then
  echo "  su -l   # only if root fingerprint auth is an explicit local policy choice"
fi
echo "  lock the screen and verify unlock"
