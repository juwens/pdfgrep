#!/usr/bin/env bash
# Install the version-locked MSYS2 UCRT64 SDK inputs for the static release.

set -euo pipefail

if [[ "${MSYSTEM:-}" != "UCRT64" || "${MINGW_PREFIX:-}" != "/ucrt64" ]]; then
  echo "Run this script from an MSYS2 UCRT64 shell (MSYSTEM=UCRT64)." >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
lock="$script_dir/windows-static-sdk.lock"
targets=()

while IFS='|' read -r package version _; do
  [[ -z "$package" || "$package" == \#* ]] && continue
  targets+=("$package=$version")
done < "$lock"

pacman -S --needed "${targets[@]}"

cat <<'EOF'

Static-build SDK dependencies are installed.

Gnulib is intentionally not an MSYS2 package.  Clone it next to this source
tree, or set GNULIB_TOOL to an existing executable:

  cd ..
  git clone https://git.savannah.gnu.org/git/gnulib.git

Then run ./build-windows-static.sh from the same UCRT64 shell.
EOF
