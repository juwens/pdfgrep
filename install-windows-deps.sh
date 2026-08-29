#!/usr/bin/env bash
# Install the MSYS2 packages needed to build pdfgrep for 64-bit MinGW.
# Run from an MSYS2 MinGW64 shell, not from PowerShell or cmd.exe.

set -euo pipefail

if [[ "${MSYSTEM:-}" != "MINGW64" ]]; then
  echo "Run this script from an MSYS2 MinGW64 shell (MSYSTEM=MINGW64)." >&2
  exit 1
fi

# The MinGW packages provide the target compiler and libraries; the unprefixed
# packages provide the Autotools used by build-windows.sh.
packages=(
  autoconf
  automake
  git
  libtool
  mingw-w64-x86_64-gcc
  mingw-w64-x86_64-libgcrypt
  # MSYS2 packages gnurx as libsystre; it provides regex.h and gnurx.pc.
  # see: https://github.com/laurikari/tre/
  mingw-w64-x86_64-libsystre
  mingw-w64-x86_64-make
  mingw-w64-x86_64-pcre2
  mingw-w64-x86_64-pkgconf
  mingw-w64-x86_64-poppler
)

pacman -S --needed "${packages[@]}"

cat <<'EOF'

Pacman dependencies are installed.

Gnulib is not packaged by MSYS2. build-windows.sh expects its checkout next
to this repository, for example:

  cd ..
  git clone https://git.savannah.gnu.org/git/gnulib.git

Alternatively, point GNULIB_TOOL at an existing gnulib-tool executable.
EOF
