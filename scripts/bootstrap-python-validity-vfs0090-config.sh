#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${PYTHON_VALIDITY_VFS0090_FIX_CONFIG_DIR:-/etc/python-validity-vfs0090-fix}"
ENV_FILE="${CONFIG_DIR}/identity.env"
OVERRIDE_FILE="${PYTHON_VALIDITY_VFS0090_FIX_OVERRIDE_FILE:-/etc/systemd/system/python3-validity.service.d/override.conf}"
DBUS_CONFIG="${PYTHON_VALIDITY_VFS0090_FIX_DBUS_CONFIG:-/etc/python-validity/dbus-service.yaml}"
ALLOW_NON_ROOT="${PYTHON_VALIDITY_VFS0090_FIX_ALLOW_NON_ROOT:-0}"

usage() {
  cat <<'EOF'
Usage: bootstrap-python-validity-vfs0090-config.sh [options]

Options:
  --product-name VALUE    Pairing product name
  --product-serial VALUE  Pairing product serial
  --dbus-user VALUE       User name for dbus-service.yaml bootstrap
  --dbus-sid VALUE        SID for dbus-service.yaml bootstrap
  --force                 Overwrite existing identity.env
  --help                  Show this help

If product name/serial are not provided, the script will try to extract them
from the current python3-validity systemd override.
EOF
}

product_name=""
product_serial=""
dbus_user=""
dbus_sid=""
force=0

while (( $# > 0 )); do
  case "$1" in
    --product-name)
      product_name="${2:-}"
      shift 2
      ;;
    --product-serial)
      product_serial="${2:-}"
      shift 2
      ;;
    --dbus-user)
      dbus_user="${2:-}"
      shift 2
      ;;
    --dbus-sid)
      dbus_sid="${2:-}"
      shift 2
      ;;
    --force)
      force=1
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

if [[ ( -n "${dbus_user}" && -z "${dbus_sid}" ) || ( -z "${dbus_user}" && -n "${dbus_sid}" ) ]]; then
  echo "Pass both --dbus-user and --dbus-sid together, or omit both." >&2
  exit 1
fi

if [[ ${ALLOW_NON_ROOT} != 1 && ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

extract_override_value() {
  local key="$1"
  python3 - "${OVERRIDE_FILE}" "${key}" <<'PY'
import pathlib
import shlex
import sys

path = pathlib.Path(sys.argv[1])
key = sys.argv[2]

if not path.exists():
    raise SystemExit(1)

for raw_line in path.read_text().splitlines():
    line = raw_line.strip()
    if not line.startswith("Environment="):
        continue

    payload = line[len("Environment="):]
    try:
        tokens = shlex.split(payload)
    except ValueError:
        continue

    for token in tokens:
        if token.startswith(f"{key}="):
            print(token[len(key) + 1:])
            raise SystemExit(0)

raise SystemExit(1)
PY
}

quote_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

if [[ -z "${product_name}" || -z "${product_serial}" ]]; then
  current_name="$(extract_override_value "PYTHON_VALIDITY_PRODUCT_NAME" || true)"
  current_serial="$(extract_override_value "PYTHON_VALIDITY_PRODUCT_SERIAL" || true)"

  if [[ -z "${product_name}" ]]; then
    product_name="${current_name}"
  fi
  if [[ -z "${product_serial}" ]]; then
    product_serial="${current_serial}"
  fi
fi

if [[ -z "${product_name}" || -z "${product_serial}" ]]; then
  echo "Missing pairing identity. Pass --product-name and --product-serial, or keep a current override.conf with those values." >&2
  exit 1
fi

mkdir -p "${CONFIG_DIR}"
if [[ -e "${ENV_FILE}" && ${force} -ne 1 ]]; then
  echo "Refusing to overwrite existing ${ENV_FILE} without --force" >&2
  exit 1
fi

cat > "${ENV_FILE}" <<EOF
PYTHON_VALIDITY_PRODUCT_NAME=$(quote_env_value "${product_name}")
PYTHON_VALIDITY_PRODUCT_SERIAL=$(quote_env_value "${product_serial}")
EOF
chmod 0600 "${ENV_FILE}"
echo "Wrote ${ENV_FILE}"

if [[ -n "${dbus_user}" && -n "${dbus_sid}" ]]; then
  mkdir -p "$(dirname "${DBUS_CONFIG}")"
  cat > "${DBUS_CONFIG}" <<EOF
user_to_sid:
  ${dbus_user}: ${dbus_sid}
EOF
  chmod 0644 "${DBUS_CONFIG}"
  echo "Wrote ${DBUS_CONFIG}"
elif [[ -f "${DBUS_CONFIG}" ]]; then
  echo "Keeping existing ${DBUS_CONFIG}"
else
  echo "No ${DBUS_CONFIG} present. Create it manually or rerun with --dbus-user/--dbus-sid." >&2
fi

echo
echo "Bootstrap complete."
echo "Next step:"
if [[ ! -f "${DBUS_CONFIG}" ]]; then
  echo "  create ${DBUS_CONFIG} with a user_to_sid mapping"
fi
echo "  sudo apply-python-validity-vfs0090-fix"
