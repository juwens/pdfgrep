#!/usr/bin/env bash
# Build pdfgrep with the MSYS2 UCRT64 toolchain.

set -euo pipefail

if [[ "${MSYSTEM:-}" != "UCRT64" || "${MINGW_PREFIX:-}" != "/ucrt64" ]]; then
  echo "Run this script from an MSYS2 UCRT64 shell (MSYSTEM=UCRT64)." >&2
  exit 1
fi

for tool in autoreconf gcc g++ grep make mktemp nproc pkg-config sed; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool not found: $tool" >&2
    exit 1
  fi
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

# Keep Autotools and the native compiler away from an invalid Windows TEMP
# inherited by the shell, and clean the temporary files on exit.
build_tmpdir="$(mktemp -d "$script_dir/.build-tmp.XXXXXX")"
trap 'rm -rf "$build_tmpdir"' EXIT
export TMPDIR="$build_tmpdir" TMP="$build_tmpdir" TEMP="$build_tmpdir"

# AM_PATH_LIBGCRYPT is installed with the UCRT64 development package.
export ACLOCAL_PATH="$MINGW_PREFIX/share/aclocal${ACLOCAL_PATH:+:$ACLOCAL_PATH}"

gnulib_tool="${GNULIB_TOOL:-$script_dir/../gnulib/gnulib-tool}"
if [[ ! -x "$gnulib_tool" ]]; then
  echo "gnulib-tool not found; set GNULIB_TOOL or clone gnulib next to pdfgrep." >&2
  exit 1
fi

# The gnulib import is deliberately generated rather than checked in. Run its
# Python launcher with the MSYS runtime so it can invoke MSYS helper tools.
PATH="/usr/bin:$MINGW_PREFIX/bin:$PATH" "$gnulib_tool" --import \
  --lib=libgnu \
  --source-base=gl \
  --m4-base=m4 \
  --makefile-name=Makefile.am \
  fnmatch strcasestr lstat scandir

# gnulib generates a Makefile fragment. Give Automake its required targets.
if ! grep -qxF 'noinst_LIBRARIES = libgnu.a' gl/Makefile.am; then
  sed -i '1iMOSTLYCLEANDIRS =' gl/Makefile.am
  sed -i '1iMOSTLYCLEANFILES = core *.stackdump' gl/Makefile.am
  sed -i '1iEXTRA_DIST =' gl/Makefile.am
  sed -i '1iBUILT_SOURCES =' gl/Makefile.am
  sed -i '1inoinst_LIBRARIES = libgnu.a' gl/Makefile.am
fi

# Do not mix headers from a separate GCC installation into the MSYS2 build.
unset C_INCLUDE_PATH CPLUS_INCLUDE_PATH

# Keep these steps serial: starting make while configure is still running can
# leave config.h inconsistent with the generated gnulib headers on Windows.
autoreconf -fi
./configure --host="$(g++ -dumpmachine)" --disable-doc "$@"
make -j"${JOBS:-$(nproc)}"
