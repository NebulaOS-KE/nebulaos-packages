#!/bin/sh
# Cross-build every wheel a requirements file resolves to, for one NebulaOS
# Python ABI, with that ABI's SDK (exported from an attested firmware build).
#
#   build-wheels.sh <sdk dir> <out dir> <requirements.txt>...
#
# The SDK's own host Python + crossenv: pip resolves the full set (newest
# allowed versions, transitive dependencies), downloads pure wheels and
# cross-compiles the rest with the SDK's gcc against its sysroot - the same
# toolchain, glibc and ABI flags the image was built with. A requirement that
# cannot be built is reported and skipped; check-wheels.py gates the result.
set -u
SDK=${1:?usage: build-wheels.sh <sdk dir> <out dir> <requirements>...}
OUT=${2:?}
shift 2
SDK=$(cd "$SDK" && pwd)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
HERE=$(cd "$(dirname "$0")/.." && pwd)

T=$(ls "$SDK"/bin/*-buildroot-linux-gnu-gcc | head -1); T=${T%-gcc}
SYSROOT=$(ls -d "$SDK"/*-buildroot-linux-gnu/sysroot | head -1)
TARGET_PY=$(ls "$SYSROOT"/usr/bin/python3.[0-9]* | grep -v config | head -1)
SYSCONFIGDATA=$(ls "$SYSROOT"/usr/lib/python3.*/_sysconfigdata__linux_*.py | head -1)
HOST_PY=$(ls "$SDK"/bin/python3.[0-9]* | grep -v config | head -1)
export PATH="$SDK/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PIP_DISABLE_PIP_VERSION_CHECK=1
# Build switches for packages that are only pulled in as dependencies (so
# packages.conf, which matches requirement lines, cannot reach them):
# PyYAML (via apprise) - its libyaml extension would link libyaml-0.so.2,
# which is not in the image's linkable set; PyYAML falls back to pure Python.
export PYYAML_FORCE_LIBYAML=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
set -e
# crossenv in a venv of the SDK's host Python (same minor as the target).
"$HOST_PY" -m venv "$WORK/host"
"$WORK/host/bin/python" -m pip install -q crossenv
# pip reports the platform from uname -m: "mips" on the printer.
"$WORK/host/bin/python" -m crossenv "$TARGET_PY" "$WORK/cross" \
	--sysroot "$SYSROOT" --sysconfigdata-file "$SYSCONFIGDATA" --machine mips \
	--cc "$T-gcc" --cxx "$T-g++" --ar "$T-gcc-ar"
CROSS_PIP="$WORK/cross/bin/cross-pip"
"$WORK/cross/bin/build-pip" install -q setuptools wheel
"$CROSS_PIP" install -q setuptools wheel
set +e

FAILED=""
# 1. packages with their own settings, built alone, at the newest version the
#    requirements allow
for REQ in "$@"; do
	grep -v '^[[:space:]]*#' "$HERE/packages.conf" | while read -r NAME SETTINGS; do
		[ -n "$NAME" ] || continue
		SPEC=$(grep -iE "^[[:space:]]*$NAME([<>=!~ ;]|$)" "$REQ" | head -1 | sed 's/#.*//')
		[ -n "$SPEC" ] || continue
		echo "== $NAME ($REQ): $SPEC"
		# shellcheck disable=SC2086
		"$CROSS_PIP" wheel --no-deps -w "$OUT" "$SPEC" $SETTINGS || echo "!! $NAME failed"
	done
done

# 2. everything, the specials taken from step 1; one requirement at a time so
#    one failure does not hide the rest
for REQ in "$@"; do
	echo "== resolving $REQ"
	sed 's/#.*//' "$REQ" | grep -v '^[[:space:]]*$' | while read -r LINE; do
		"$CROSS_PIP" wheel -w "$OUT" --find-links "$OUT" "$LINE" >"$WORK/one.log" 2>&1 \
			|| { echo "!! FAILED: $LINE"; tail -20 "$WORK/one.log"; echo "$LINE" >> "$OUT/.failed"; }
	done
done
ls -1 "$OUT"
[ ! -f "$OUT/.failed" ] || { echo "== not built:"; cat "$OUT/.failed"; }
exit 0
