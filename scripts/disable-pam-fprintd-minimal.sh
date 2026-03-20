#!/usr/bin/env bash
set -euo pipefail

ALLOW_NON_ROOT="${PYTHON_VALIDITY_VFS0090_FIX_ALLOW_NON_ROOT:-0}"
PAM_DIR="${PYTHON_VALIDITY_VFS0090_FIX_PAM_DIR:-/etc/pam.d}"

if [[ ${ALLOW_NON_ROOT} != 1 && ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

if (( $# > 0 )); then
  TARGETS=("$@")
else
  TARGETS=("sudo" "polkit-1")
fi

restore_target() {
  local target="$1"
  local path="${PAM_DIR}/${target}"
  local latest_backup

  latest_backup="$(ls -1t "${path}".fprintd-backup-* 2>/dev/null | head -n1 || true)"
  if [[ -z "${latest_backup}" ]]; then
    echo "No backup found for ${path}" >&2
    return 1
  fi

  install -m 0644 "${latest_backup}" "${path}"
  echo "Restored ${path} from ${latest_backup}"
}

for target in "${TARGETS[@]}"; do
  restore_target "${target}"
done

echo
echo "Minimal PAM fingerprint integration reverted."
