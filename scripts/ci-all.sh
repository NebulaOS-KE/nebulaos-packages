#!/bin/sh
# One CI pass: for every NebulaOS SDK release (one per Python ABI id), build
# the wheels the requirements resolve to and Klipper's c_helper.so, gate
# them, add them to the index.
#
#   ci-all.sh <requirements dir> <site dir> [failures file]
# Needs: gh (authenticated), docker, git, BUILD_IMAGE (the firmware build
# image, pinned by digest - the SDK's host tools were built in it).
#
# Each ABI runs on its own: whatever fails there is appended to the failures
# file and the next ABI still runs - everything that did build is published.
# Exit 0 unless the pass itself could not run.
set -u
REQS=$(cd "${1:?}" && pwd)
SITE=$(mkdir -p "${2:?}" && cd "$2" && pwd)
FAILURES=${3:-/dev/null}
touch "$FAILURES"
HERE=$(cd "$(dirname "$0")/.." && pwd)
: "${BUILD_IMAGE:?}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

one_abi() { # $1 = ABI id, in a subshell
	set -e
	ID=$1
	D="$WORK/$ID"
	rm -rf "$D"; mkdir -p "$D"
	gh release download "sdk-$ID" --dir "$D" --pattern 'nebulaos-sdk-*.tar.xz*'
	( cd "$D" && sha256sum -c "nebulaos-sdk-$ID.tar.xz.sha256" )
	tar -C "$D" -xJf "$D/nebulaos-sdk-$ID.tar.xz"
	rm -f "$D/nebulaos-sdk-$ID.tar.xz"
	SDK="$D/nebulaos-sdk-$ID"
	# An SDK published before the chelper recipe travelled inside it: the
	# firmware adds it to the release as nebulaos-chelper-tools-<id>.tar.gz.
	if [ ! -d "$SDK/nebulaos" ] && gh release download "sdk-$ID" --dir "$D" \
		--pattern "nebulaos-chelper-tools-$ID.tar.gz" 2>/dev/null; then
		tar -C "$SDK" -xzf "$D/nebulaos-chelper-tools-$ID.tar.gz"
	fi

	# Klipper sources for c_helper.so: what collect-requirements.sh gathered
	# (master) plus the Klipper this SDK's image ships ("pinned" - the
	# reproducibility check in build-chelper.py).
	mkdir -p "$D/chelper-src"
	[ -d "$REQS/chelper" ] && cp -a "$REQS/chelper/." "$D/chelper-src/"
	PIN=$(sed -n "s/^klipper_commit=//p" "$SDK/nebulaos/image-chelper" 2>/dev/null || true)
	if [ -n "$PIN" ]; then
		git init -q "$D/klipper-pin"
		git -C "$D/klipper-pin" fetch -q --depth 1 https://github.com/Klipper3d/klipper.git "$PIN"
		git -C "$D/klipper-pin" checkout -q FETCH_HEAD
		mkdir -p "$D/chelper-src/pinned/klippy"
		cp -a "$D/klipper-pin/klippy/chelper" "$D/chelper-src/pinned/klippy/"
		echo "$PIN" > "$D/chelper-src/pinned/COMMIT"
	fi

	# Relocate, build and gate inside the build image; the SDK's own Python
	# runs the gates (no assumption about the image's python3).
	# The image's entrypoint is ["sh", "-c"]: the script is its one argument.
	docker run --rm -v "$D:/w" -v "$HERE:/repo:ro" -v "$REQS:/reqs:ro" -w /w "$BUILD_IMAGE" "
		cd /w/nebulaos-sdk-$ID && ./relocate-sdk.sh >/dev/null || exit 1
		S=/w/nebulaos-sdk-$ID
		PATH=\$S/bin:\$PATH sh /repo/scripts/build-wheels.sh \$S /w/wheels /reqs/*.txt
		\$S/bin/python3 /repo/scripts/check-wheels.py \$S \$S/python-abi /w/wheels
		PATH=\$S/bin:\$PATH \$S/bin/python3 /repo/scripts/build-chelper.py \$S \$S/python-abi /w/chelper-src /w/chelper
		chmod -R a+rwX /w"
	python3 "$HERE/scripts/make-index.py" "$SITE" "$ID" "$SDK/python-abi" "$D/wheels" "$D/chelper" \
		|| echo "ABI $ID: make-index failed (see the log)" >> "$FAILURES"
	if [ -f "$D/chelper/.failed" ]; then
		sed "s/^/ABI $ID: /" "$D/chelper/.failed" >> "$FAILURES"
	fi
	if [ -f "$D/wheels/.failed" ]; then
		echo "Not built for $ID:"; cat "$D/wheels/.failed"
		sed "s/^/ABI $ID: not built: /" "$D/wheels/.failed" >> "$FAILURES"
	fi
	if ls "$D/wheels/rejected/"*.whl >/dev/null 2>&1; then
		for R in "$D/wheels/rejected/"*.whl; do
			echo "ABI $ID: rejected by the ABI check: ${R##*/}" >> "$FAILURES"
		done
	fi
}

TAGS=$(gh release list --limit 100 --json tagName -q '.[].tagName') || {
	echo "SDK releases: gh release list failed" >> "$FAILURES"
	exit 0
}
for TAG in $(echo "$TAGS" | grep '^sdk-' || true); do
	ID=${TAG#sdk-}
	echo "::group::ABI $ID"
	# Not "( ... ) ||": set -e would be ignored inside a tested subshell.
	( one_abi "$ID" )
	[ $? -eq 0 ] || echo "ABI $ID: the build for this ABI stopped early (download, relocation or container failure - see the log)" >> "$FAILURES"
	rm -rf "$WORK/$ID"
	echo "::endgroup::"
done
exit 0
