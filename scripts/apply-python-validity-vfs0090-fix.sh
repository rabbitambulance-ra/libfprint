#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${PYTHON_VALIDITY_VFS0090_FIX_CONFIG_DIR:-/etc/python-validity-vfs0090-fix}"
ENV_FILE="${CONFIG_DIR}/identity.env"
DBUS_CONFIG="${PYTHON_VALIDITY_VFS0090_FIX_DBUS_CONFIG:-/etc/python-validity/dbus-service.yaml}"
OVERRIDE_FILE="${PYTHON_VALIDITY_VFS0090_FIX_OVERRIDE_FILE:-/etc/systemd/system/python3-validity.service.d/override.conf}"
OVERRIDE_DIR="$(dirname "${OVERRIDE_FILE}")"
OVERRIDE_BACKUP="${OVERRIDE_FILE}.vfs0090fix.orig"
ALLOW_NON_ROOT="${PYTHON_VALIDITY_VFS0090_FIX_ALLOW_NON_ROOT:-0}"
SYSTEMCTL_BIN="${PYTHON_VALIDITY_VFS0090_FIX_SYSTEMCTL:-systemctl}"
DATA_DIR_OVERRIDE="${PYTHON_VALIDITY_VFS0090_FIX_DATA_DIR:-}"
MODULE_DIR_OVERRIDE="${PYTHON_VALIDITY_VFS0090_FIX_MODULE_DIR:-}"
SITEPKG_ROOT_OVERRIDE="${PYTHON_VALIDITY_VFS0090_FIX_SITEPKG_ROOT:-}"

quiet=0
if_configured=0
restart_services=1

usage() {
  cat <<'EOF'
Usage: apply-python-validity-vfs0090-fix.sh [options]

Options:
  --quiet           Reduce output
  --if-configured   Exit successfully if identity/env config is not present
  --no-restart      Do not restart services after applying
  --help            Show this help
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --quiet)
      quiet=1
      shift
      ;;
    --if-configured)
      if_configured=1
      shift
      ;;
    --no-restart)
      restart_services=0
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ${ALLOW_NON_ROOT} != 1 && ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

say() {
  if [[ ${quiet} -ne 1 ]]; then
    printf '%s\n' "$*"
  fi
}

find_data_dir() {
  if [[ -n "${DATA_DIR_OVERRIDE}" ]]; then
    printf '%s\n' "${DATA_DIR_OVERRIDE}"
    return 0
  fi

  local script_dir repo_root
  script_dir="$(cd -- "$(dirname "$0")" && pwd)"
  repo_root="$(cd -- "${script_dir}/.." && pwd)"

  if [[ -d "/usr/share/python-validity-vfs0090-fix/patches/python-validity" ]]; then
    printf '%s\n' "/usr/share/python-validity-vfs0090-fix"
    return 0
  fi

  if [[ -d "${repo_root}/packaging/patches/python-validity" ]]; then
    printf '%s\n' "${repo_root}"
    return 0
  fi

  return 1
}

extract_override_value() {
  local key="$1"
  sed -n "s/^Environment=${key}=//p" "${OVERRIDE_FILE}" 2>/dev/null | head -n1
}

bootstrap_identity_env_from_override() {
  local current_name current_serial

  [[ -s "${ENV_FILE}" ]] && return 0

  current_name="$(extract_override_value "PYTHON_VALIDITY_PRODUCT_NAME" || true)"
  current_serial="$(extract_override_value "PYTHON_VALIDITY_PRODUCT_SERIAL" || true)"

  if [[ -z "${current_name}" || -z "${current_serial}" ]]; then
    return 1
  fi

  mkdir -p "${CONFIG_DIR}"
  cat > "${ENV_FILE}" <<EOF
PYTHON_VALIDITY_PRODUCT_NAME="${current_name}"
PYTHON_VALIDITY_PRODUCT_SERIAL="${current_serial}"
EOF
  chmod 0600 "${ENV_FILE}"
  say "Bootstrapped ${ENV_FILE} from the current override"
}

module_dir="${MODULE_DIR_OVERRIDE}"
sitepkg_root="${SITEPKG_ROOT_OVERRIDE}"

if [[ -z "${module_dir}" ]]; then
module_dir="$(python3 - <<'PY'
import os
import validitysensor
print(os.path.dirname(validitysensor.__file__))
PY
)"
fi

if [[ -z "${sitepkg_root}" ]]; then
  sitepkg_root="$(dirname "${module_dir}")"
fi

tls_file="${module_dir}/tls.py"
sensor_file="${module_dir}/sensor.py"

data_dir="$(find_data_dir)" || {
  echo "Unable to locate packaged patch data." >&2
  exit 1
}

patch_dir="${data_dir}/packaging/patches/python-validity"
if [[ ! -d "${patch_dir}" ]]; then
  patch_dir="${data_dir}/patches/python-validity"
fi

if [[ ! -s "${ENV_FILE}" ]]; then
  bootstrap_identity_env_from_override || true
fi

if [[ ! -s "${ENV_FILE}" ]]; then
  if [[ ${if_configured} -eq 1 ]]; then
    say "No ${ENV_FILE} found; skipping apply"
    exit 0
  fi
  echo "Missing ${ENV_FILE}. Run bootstrap-python-validity-vfs0090-config.sh first." >&2
  exit 1
fi

if [[ ! -f "${DBUS_CONFIG}" ]]; then
  if [[ ${if_configured} -eq 1 ]]; then
    say "No ${DBUS_CONFIG} found; skipping apply"
    exit 0
  fi
  echo "Missing ${DBUS_CONFIG}. Create a user_to_sid mapping first." >&2
  exit 1
fi

backup_if_missing() {
  local src="$1"
  local backup="$2"
  if [[ -f "${src}" && ! -f "${backup}" ]]; then
    install -D -m 0644 "${src}" "${backup}"
  fi
}

apply_patch_if_needed() {
  local patch_file="$1"
  if patch --dry-run --forward --silent -p1 -d "${sitepkg_root}" -i "${patch_file}" >/dev/null 2>&1; then
    patch --forward --silent -p1 -d "${sitepkg_root}" -i "${patch_file}" >/dev/null
    say "Applied $(basename "${patch_file}")"
    return 0
  fi

  if patch --dry-run --silent -R -p1 -d "${sitepkg_root}" -i "${patch_file}" >/dev/null 2>&1; then
    say "Already applied $(basename "${patch_file}")"
    return 0
  fi

  echo "Failed to apply $(basename "${patch_file}") against ${sitepkg_root}" >&2
  return 1
}

backup_if_missing "${tls_file}" "${tls_file}.vfs0090fix.orig"
backup_if_missing "${sensor_file}" "${sensor_file}.vfs0090fix.orig"
backup_if_missing "${OVERRIDE_FILE}" "${OVERRIDE_BACKUP}"

apply_patch_if_needed "${patch_dir}/0001-tls-identity-override.patch"
apply_patch_if_needed "${patch_dir}/0002-vfs0090-capture-fix.patch"

mkdir -p "${OVERRIDE_DIR}"
cat > "${OVERRIDE_FILE}" <<EOF
[Service]
EnvironmentFile=-${ENV_FILE}
EOF
say "Installed generic systemd override ${OVERRIDE_FILE}"

if [[ ${restart_services} -eq 1 ]]; then
  "${SYSTEMCTL_BIN}" daemon-reload
  "${SYSTEMCTL_BIN}" restart open-fprintd.service
  "${SYSTEMCTL_BIN}" restart python3-validity.service
  say "Restarted open-fprintd.service and python3-validity.service"
fi

say "python-validity VFS0090 fix is applied."
