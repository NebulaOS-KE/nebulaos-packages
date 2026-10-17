#!/bin/sh
# Which packages the printer's app updates can ask for.
#
# Moonraker's update_manager runs `pip install -U -r <requirements>` for
# Moonraker and for Klipper, so the index must hold every package - and the
# newest version allowed - that those files resolve to, for the releases a
# printer can update to: Moonraker's latest release and master, Klipper's
# master. Plus pip itself (Moonraker may upgrade it, within its own limit).
#
#   collect-requirements.sh <out dir>   writes one .txt per source
set -eu
OUT=${1:?usage: collect-requirements.sh <out dir>}
mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git clone -q --filter=blob:none --no-checkout https://github.com/Arksine/moonraker.git "$WORK/moonraker"
TAG=$(git -C "$WORK/moonraker" tag --list 'v*' --sort=-v:refname | head -1)
for REF in "$TAG" origin/master; do
	NAME="moonraker-$(echo "$REF" | sed 's#origin/##')"
	git -C "$WORK/moonraker" show "$REF:scripts/moonraker-requirements.txt" \
		| grep -v -- '--find-links' > "$OUT/$NAME.txt"
	# Moonraker upgrades pip itself only up to MAX_PIP_VERSION.
	MAXPIP=$(git -C "$WORK/moonraker" show "$REF:moonraker/utils/pip_utils.py" 2>/dev/null \
		| sed -n 's/^MAX_PIP_VERSION = (\([0-9]*\), *\([0-9]*\)).*/\1.\2/p')
	[ -n "$MAXPIP" ] && echo "pip<=$MAXPIP" >> "$OUT/$NAME.txt"
	echo "== $NAME: $(grep -vc '^#' "$OUT/$NAME.txt") lines (pip<=${MAXPIP:-?})"
done

git clone -q --depth 1 https://github.com/Klipper3d/klipper.git "$WORK/klipper"
cp "$WORK/klipper/scripts/klippy-requirements.txt" "$OUT/klipper-master.txt"
echo "== klipper-master: $(grep -vc '^#' "$OUT/klipper-master.txt") lines"
