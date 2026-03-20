#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"

echo "install-python-validity-vbox-fix.sh is deprecated."
echo "Using the generic replayable VFS0090 apply flow instead."

"${SCRIPT_DIR}/apply-python-validity-vfs0090-fix.sh"
