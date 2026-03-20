#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"

echo "revert-python-validity-vbox-fix.sh is deprecated."
echo "Using the generic replayable VFS0090 revert flow instead."

"${SCRIPT_DIR}/revert-python-validity-vfs0090-fix.sh"
