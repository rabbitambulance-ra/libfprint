#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${PYTHON_VALIDITY_VFS0090_FIX_CONFIG_DIR:-/etc/python-validity-vfs0090-fix}"
OVERRIDE_FILE="${PYTHON_VALIDITY_VFS0090_FIX_OVERRIDE_FILE:-/etc/systemd/system/python3-validity.service.d/override.conf}"
OVERRIDE_BACKUP="${OVERRIDE_FILE}.vfs0090fix.orig"
ALLOW_NON_ROOT="${PYTHON_VALIDITY_VFS0090_FIX_ALLOW_NON_ROOT:-0}"
SYSTEMCTL_BIN="${PYTHON_VALIDITY_VFS0090_FIX_SYSTEMCTL:-systemctl}"
MODULE_DIR_OVERRIDE="${PYTHON_VALIDITY_VFS0090_FIX_MODULE_DIR:-}"

if [[ ${ALLOW_NON_ROOT} != 1 && ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

module_dir="${MODULE_DIR_OVERRIDE}"
if [[ -z "${module_dir}" ]]; then
  module_dir="$(python3 - <<'PY'
import os
import validitysensor
print(os.path.dirname(validitysensor.__file__))
PY
)"
fi

restore_if_present() {
  local backup="$1"
  local dst="$2"
  if [[ -f "${backup}" ]]; then
    install -m 0644 "${backup}" "${dst}"
    echo "Restored ${dst}"
  fi
}

restore_if_present "${module_dir}/tls.py.vfs0090fix.orig" "${module_dir}/tls.py"
restore_if_present "${module_dir}/sensor.py.vfs0090fix.orig" "${module_dir}/sensor.py"

if [[ -f "${OVERRIDE_BACKUP}" ]]; then
  install -m 0644 "${OVERRIDE_BACKUP}" "${OVERRIDE_FILE}"
  echo "Restored ${OVERRIDE_FILE}"
else
  rm -f "${OVERRIDE_FILE}"
fi

"${SYSTEMCTL_BIN}" daemon-reload
"${SYSTEMCTL_BIN}" restart open-fprintd.service
"${SYSTEMCTL_BIN}" restart python3-validity.service

echo
echo "python-validity VFS0090 fix reverted."
echo "Local config in ${CONFIG_DIR} was left in place."
