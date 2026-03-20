#!/usr/bin/env bash
set -euo pipefail

ALLOW_NON_ROOT="${PYTHON_VALIDITY_VFS0090_FIX_ALLOW_NON_ROOT:-0}"
PAM_DIR="${PYTHON_VALIDITY_VFS0090_FIX_PAM_DIR:-/etc/pam.d}"

if [[ ${ALLOW_NON_ROOT} != 1 && ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

PAM_LINE='auth       sufficient   pam_fprintd.so max-tries=3 timeout=10'
if (( $# > 0 )); then
  TARGETS=("$@")
else
  TARGETS=("sudo" "polkit-1")
fi

patch_target() {
  local target="$1"
  local path="${PAM_DIR}/${target}"
  local backup="${path}.fprintd-backup.orig"
  local tmp

  if [[ ! -f "${path}" ]]; then
    echo "Skipping missing PAM target: ${path}" >&2
    return 0
  fi

  if [[ ! -f "${backup}" ]]; then
    install -D -m 0644 "${path}" "${backup}"
  fi
  tmp="$(mktemp)"

  awk -v line="${PAM_LINE}" '
    BEGIN {
      inserted = 0
      uncommented = 0
    }
    $0 ~ /^[[:space:]]*#auth[[:space:]]+sufficient[[:space:]]+pam_fprintd[.]so/ {
      print line
      inserted = 1
      uncommented = 1
      next
    }
    $0 == line {
      inserted = 1
    }
    /^auth[[:space:]]+include[[:space:]]+system-auth$/ && inserted == 0 {
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

for target in "${TARGETS[@]}"; do
  patch_target "${target}"
done

echo
echo "Minimal PAM fingerprint integration enabled."
echo "Targets: ${TARGETS[*]}"
echo "Suggested checks:"
echo "  sudo -k"
echo "  sudo true"
echo "  pkexec true"
