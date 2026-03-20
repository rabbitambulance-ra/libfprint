#!/usr/bin/env bash
set -euo pipefail

ALLOW_NON_ROOT="${PYTHON_VALIDITY_VFS0090_FIX_ALLOW_NON_ROOT:-0}"
PAM_DIR="${PYTHON_VALIDITY_VFS0090_FIX_PAM_DIR:-/etc/pam.d}"

if [[ ${ALLOW_NON_ROOT} != 1 && ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

restore_target() {
  local target="$1"
  local path="${PAM_DIR}/${target}"
  local latest_backup

  latest_backup="$(ls -1t "${path}".fprintd-backup-* 2>/dev/null | head -n1 || true)"
  if [[ -z "${latest_backup}" ]]; then
    return 0
  fi

  install -m 0644 "${latest_backup}" "${path}"
  echo "Restored ${path} from ${latest_backup}"
}

for target in \
  sudo polkit-1 login greetd budgie-screensaver cinnamon-screensaver \
  mate-screensaver xfce4-screensaver xscreensaver ukui-screensaver-qt \
  su su-l vlock lightdm sddm lxdm
do
  restore_target "${target}"
done

echo
echo "Local PAM fingerprint integration reverted."
