#!/bin/sh
# Build Nuked OPL3 (https://github.com/nukeykt/Nuked-OPL3, LGPL 2.1) as a
# shared library in data/lib, where Castle DOOM loads it at runtime
# (DoomOpl3). The sources are fetched at a pinned commit (v1.8) and are not
# part of this repository; the licence is placed next to the library.
#
#   tools/build_nuked_opl3.sh            # downloads into a temporary directory
#   NUKED_OPL3_SRC=dir tools/build_nuked_opl3.sh   # uses opl3.c / opl3.h there
#
# Needs a C compiler: cc / gcc / clang (mingw-w64 gcc on Windows, e.g. in
# Git Bash or the GitHub runner's shell).
set -e
COMMIT=765ec962e473aeb767e4cba74ffdc8f588ffbfe8
cd "$(dirname "$0")/.."
OUT=data/lib
mkdir -p "$OUT"
SRC="${NUKED_OPL3_SRC:-}"
if [ -z "$SRC" ]; then
  SRC="$(mktemp -d)"
  for f in opl3.c opl3.h LICENSE; do
    curl -sSfL -o "$SRC/$f" "https://raw.githubusercontent.com/nukeykt/Nuked-OPL3/$COMMIT/$f"
  done
fi
CC="${CC:-}"
if [ -z "$CC" ]; then
  for c in cc gcc clang; do
    if command -v "$c" >/dev/null 2>&1; then CC="$c"; break; fi
  done
fi
[ -n "$CC" ] || { echo "No C compiler (cc / gcc / clang) found" >&2; exit 1; }
case "$(uname -s)" in
  Darwin)
    LIB=libnukedopl3.dylib
    "$CC" -O2 -dynamiclib -o "$OUT/$LIB" "$SRC/opl3.c" ;;
  MINGW*|MSYS*|CYGWIN*|Windows*)
    LIB=nukedopl3.dll
    "$CC" -O2 -shared -o "$OUT/$LIB" "$SRC/opl3.c" -Wl,--kill-at ;;
  *)
    LIB=libnukedopl3.so
    "$CC" -O2 -fPIC -shared -o "$OUT/$LIB" "$SRC/opl3.c" ;;
esac
cp "$SRC/LICENSE" "$OUT/LICENSE-Nuked-OPL3.txt"
cat > "$OUT/README-Nuked-OPL3.txt" <<TXT
$LIB is Nuked OPL3 (https://github.com/nukeykt/Nuked-OPL3, commit $COMMIT),
copyright Nuke.YKT, licensed under the GNU Lesser General Public License
2.1 or later (LICENSE-Nuked-OPL3.txt). Castle DOOM loads it at runtime for
the music; replace it with your own build if you like, or delete it to use
the built-in FM synthesizer.
TXT
echo "Built $OUT/$LIB with $CC"
