#!/usr/bin/env bash
# Build pdfgrep with the MSYS2 MinGW64 toolchain.

set -euo pipefail

if [[ "${MSYSTEM:-}" != "MINGW64" ]]; then
  echo "Run this script from an MSYS2 MinGW64 shell (MSYSTEM=MINGW64)." >&2
  exit 1
fi

for tool in autoreconf gcc g++ grep make nproc pkg-config sed; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool not found: $tool" >&2
    exit 1
  fi
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

gnulib_tool="${GNULIB_TOOL:-$script_dir/../gnulib/gnulib-tool}"
if [[ ! -x "$gnulib_tool" ]]; then
  echo "gnulib-tool not found; set GNULIB_TOOL or clone gnulib next to pdfgrep." >&2
  exit 1
fi

# The gnulib import is deliberately generated rather than checked in.
"$gnulib_tool" --import \
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

# Ensure generated feature definitions are available in every C++ source.
for source in src/*.cc; do
  if ! grep -Eq '^[[:space:]]*#include[[:space:]]+"config\.h"[[:space:]]*$' "$source"; then
    sed -i '1i#include "config.h"' "$source"
  fi
done

# Keep these steps serial: starting make while configure is still running can
# leave config.h inconsistent with the generated gnulib headers on MinGW.
autoreconf -fi
./configure --disable-doc "$@"
make -j"${JOBS:-$(nproc)}"
