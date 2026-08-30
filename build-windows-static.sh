#!/usr/bin/env bash
# Build a self-contained x86-64 Windows 11 pdfgrep executable.
#
# The resulting dist/windows-static/pdfgrep.exe has no MSYS2 or other
# third-party DLL imports. It uses Windows 11's system and UCRT DLLs only.

set -euo pipefail

if [[ "${MSYSTEM:-}" != "UCRT64" || "${MINGW_PREFIX:-}" != "/ucrt64" ]]; then
  echo "Run this script from an MSYS2 UCRT64 shell (MSYSTEM=UCRT64)." >&2
  exit 1
fi

for tool in autoreconf cmake curl g++ grep make mktemp ninja nproc objdump pkg-config sed sha256sum tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool not found: $tool" >&2
    exit 1
  fi
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

# Keep native compilers and Autotools away from an invalid inherited TEMP.
build_tmpdir="$(mktemp -d "$script_dir/.windows-static-tmp.XXXXXX")"
trap 'rm -rf "$build_tmpdir"' EXIT
export TMPDIR="$build_tmpdir" TMP="$build_tmpdir" TEMP="$build_tmpdir"

readonly source_lock="$script_dir/windows-static-sources.lock"
readonly sdk_lock="$script_dir/windows-static-sdk.lock"
readonly cache_dir="${STATIC_CACHE_DIR:-$script_dir/.windows-static-cache}"
readonly poppler_prefix="$build_tmpdir/prefix"
readonly poppler_source="$build_tmpdir/poppler-source"
readonly poppler_build="$build_tmpdir/poppler-build"
readonly output_dir="$script_dir/dist/windows-static"

mkdir -p "$cache_dir" "$output_dir"

lock_field() {
  local field=$1
  awk -F'|' -v field="$field" '$1 == "poppler" { print $field; exit }' "$source_lock"
}

readonly poppler_version="$(lock_field 2)"
readonly poppler_url="$(lock_field 3)"
readonly poppler_hash="$(lock_field 4)"
readonly poppler_archive="$cache_dir/poppler-$poppler_version.tar.xz"

if [[ -z "$poppler_version" || -z "$poppler_url" || -z "$poppler_hash" ]]; then
  echo "Invalid Poppler entry in $source_lock" >&2
  exit 1
fi

if [[ ! -f "$poppler_archive" ]]; then
  curl --fail --location --retry 3 --output "$poppler_archive" "$poppler_url"
fi
printf '%s  %s\n' "$poppler_hash" "$poppler_archive" | sha256sum --check --status

# The UCRT SDK supplies static archives for the offline Poppler dependency
# graph.  Its exact package versions are locked so that a changed SDK cannot
# silently produce a different release.  Poppler itself is built here because
# MSYS2 distributes only its DLL import library.  CURL, NSS, GPGME, GLib, Qt,
# and Cairo are deliberately off.
while IFS='|' read -r package expected_version _; do
  [[ -z "$package" || "$package" == \#* ]] && continue
  actual_version="$(pacman -Q "$package" 2>/dev/null | awk '{ print $2 }')" || {
    echo "Required MSYS2 package is not installed: $package" >&2
    exit 1
  }
  if [[ "$actual_version" != "$expected_version" ]]; then
    echo "MSYS2 package version mismatch for $package: expected $expected_version, found $actual_version" >&2
    echo "Run ./install-windows-static-build-deps.sh or update the reviewed SDK lock." >&2
    exit 1
  fi
done < "$sdk_lock"

for archive in \
  libatomic.a libbrotlicommon.a libbrotlidec.a libbz2.a libdeflate.a \
  libfreetype.a libgcrypt.a libgpg-error.a libglib-2.0.a libgraphite2.a \
  libharfbuzz.a libiconv.a libintl.a libjbig.a libjpeg.a liblcms2.a \
  liblcms2_fast_float.a libLerc.a liblzma.a libopenjp2.a libpcre2-8.a \
  libpng16.a libsharpyuv.a libsystre.a libtiff.a libtre.a libunistring.a \
  libwebp.a libz.a libzstd.a; do
  if [[ ! -f "$MINGW_PREFIX/lib/$archive" ]]; then
    echo "Required static archive not found: $MINGW_PREFIX/lib/$archive" >&2
    exit 1
  fi
done

mkdir -p "$poppler_source" "$poppler_build"
tar -xf "$poppler_archive" -C "$poppler_source" --strip-components=1

export CC=x86_64-w64-mingw32-gcc
export CXX=x86_64-w64-mingw32-g++

cmake -S "$poppler_source" -B "$poppler_build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$poppler_prefix" \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_CXX_FLAGS=-DOPJ_STATIC \
  -DENABLE_CPP=ON \
  -DBUILD_GTK_TESTS=OFF \
  -DBUILD_QT5_TESTS=OFF \
  -DBUILD_QT6_TESTS=OFF \
  -DBUILD_CPP_TESTS=OFF \
  -DBUILD_MANUAL_TESTS=OFF \
  -DWITH_Cairo=OFF \
  -DENABLE_GLIB=OFF \
  -DENABLE_GOBJECT_INTROSPECTION=OFF \
  -DENABLE_GTK_DOC=OFF \
  -DENABLE_LIBCURL=OFF \
  -DENABLE_NSS3=OFF \
  -DENABLE_GPGME=OFF \
  -DENABLE_QT5=OFF \
  -DENABLE_QT6=OFF \
  -DENABLE_UTILS=OFF \
  -DENABLE_BOOST=OFF \
  -DENABLE_UNSTABLE_API_ABI_HEADERS=ON \
  -DENABLE_ZLIB_UNCOMPRESS=ON \
  -DFREETYPE_LIBRARY_RELEASE="$MINGW_PREFIX/lib/libfreetype.a" \
  -DTIFF_LIBRARY_RELEASE="$MINGW_PREFIX/lib/libtiff.a" \
  -DZLIB_LIBRARY_RELEASE="$MINGW_PREFIX/lib/libz.a" \
  -DPNG_LIBRARY_RELEASE="$MINGW_PREFIX/lib/libpng16.a" \
  -DJPEG_LIBRARY_RELEASE="$MINGW_PREFIX/lib/libjpeg.a" \
  -DLCMS2_LIBRARIES="$MINGW_PREFIX/lib/liblcms2.a" \
  -DIconv_LIBRARY="$MINGW_PREFIX/lib/libiconv.a"
cmake --build "$poppler_build" --parallel "${JOBS:-$(nproc)}"
cmake --install "$poppler_build"

gnulib_tool="${GNULIB_TOOL:-$script_dir/../gnulib/gnulib-tool}"
if [[ ! -x "$gnulib_tool" ]]; then
  echo "gnulib-tool not found; set GNULIB_TOOL or clone gnulib next to pdfgrep." >&2
  exit 1
fi

# Run Gnulib's Python launcher under the MSYS runtime, not the UCRT runtime.
PATH="/usr/bin:$MINGW_PREFIX/bin:$PATH" "$gnulib_tool" --import \
  --lib=libgnu \
  --source-base=gl \
  --m4-base=m4 \
  --makefile-name=Makefile.am \
  fnmatch strcasestr lstat scandir

if ! grep -qxF 'noinst_LIBRARIES = libgnu.a' gl/Makefile.am; then
  sed -i '1iMOSTLYCLEANDIRS =' gl/Makefile.am
  sed -i '1iMOSTLYCLEANFILES = core *.stackdump' gl/Makefile.am
  sed -i '1iEXTRA_DIST =' gl/Makefile.am
  sed -i '1iBUILT_SOURCES =' gl/Makefile.am
  sed -i '1inoinst_LIBRARIES = libgnu.a' gl/Makefile.am
fi

# Reconfigure the source tree for static headers and libraries. This removes
# generated files only; build-windows.sh can recreate the dynamic build later.
if [[ -f Makefile ]]; then
  make distclean
fi
unset C_INCLUDE_PATH CPLUS_INCLUDE_PATH
export ACLOCAL_PATH="$MINGW_PREFIX/share/aclocal${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
autoreconf -fi

cat > "$build_tmpdir/pkg-config-static" <<EOF
#!/usr/bin/env sh
exec "$MINGW_PREFIX/bin/pkg-config" --static "\$@"
EOF
chmod +x "$build_tmpdir/pkg-config-static"

# GnuPG's Autoconf macro prefers gpgrt-config when it is available.  Its
# --libs result is intended for dynamic linking and omits libgpg-error and
# other private requirements.  Keep the standard macro, but feed it the
# complete static dependency closure for this build only.
cat > "$build_tmpdir/libgcrypt-config-static" <<EOF
#!/usr/bin/env sh
case "\${1:-}" in
  --libs)
    exec "$MINGW_PREFIX/bin/pkg-config" --static --libs libgcrypt
    ;;
  --cflags)
    exec "$MINGW_PREFIX/bin/pkg-config" --cflags libgcrypt
    ;;
  *)
    exec "$MINGW_PREFIX/bin/libgcrypt-config" "\$@"
    ;;
esac
EOF
chmod +x "$build_tmpdir/libgcrypt-config-static"

export PKG_CONFIG="$build_tmpdir/pkg-config-static"
export PKG_CONFIG_PATH="$poppler_prefix/lib/pkgconfig:$MINGW_PREFIX/lib/pkgconfig"
export ac_cv_path_GPGRT_CONFIG=no
export LIBGCRYPT_CONFIG="$build_tmpdir/libgcrypt-config-static"
export CPPFLAGS="-DPOPPLER_CPP_STATIC_DEFINE -DPCRE2_STATIC"
export LDFLAGS="-static -static-libgcc -static-libstdc++"

./configure --host="$(g++ -dumpmachine)" --disable-doc
make -j"${JOBS:-$(nproc)}"

readonly artifact="$output_dir/pdfgrep.exe"
cp src/pdfgrep.exe "$artifact"

# A standalone release may import only Windows 11 system/UCRT API DLLs.
while IFS= read -r dll; do
  case "$dll" in
    api-ms-win-*|ext-ms-win-*|advapi32.dll|bcrypt.dll|combase.dll|crypt32.dll|dwrite.dll|gdi32.dll|gdi32full.dll|iphlpapi.dll|kernel32.dll|kernelbase.dll|msvcp_win.dll|msvcrt.dll|mswsock.dll|ntdll.dll|ole32.dll|rpcrt4.dll|sechost.dll|secur32.dll|shell32.dll|sspicli.dll|user32.dll|usp10.dll|win32u.dll|winmm.dll|wldap32.dll|ws2_32.dll)
      ;;
    *)
      echo "Unexpected non-system DLL import: $dll" >&2
      exit 1
      ;;
  esac
done < <(objdump -p "$artifact" | sed -n 's/^[[:space:]]*DLL Name: //p' | tr '[:upper:]' '[:lower:]')

"$artifact" --version
"$artifact" --help >/dev/null
"$artifact" --color=never hello testsuite/fixtures/pdfgrep-smoke.pdf | grep -qx 'hello pdfgrep'

echo "Standalone executable: $artifact"
