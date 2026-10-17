#!/bin/sh
# One CI pass: for every NebulaOS SDK release (one per Python ABI id), build
# the wheels the requirements resolve to, gate them, add them to the index.
#
#   ci-all.sh <requirements dir> <site dir> [failures file]
# Needs: gh (authenticated), docker, BUILD_IMAGE (the firmware build image,
# pinned by digest - the SDK's host tools were built in it).
set -eu
REQS=$(cd "${1:?}" && pwd)
SITE=$(mkdir -p "${2:?}" && cd "$2" && pwd)
FAILURES=${3:-/dev/null}
: > "$FAILURES"
HERE=$(cd "$(dirname "$0")/.." && pwd)
: "${BUILD_IMAGE:?}"
WORK=$(mktemp -d)

for TAG in $(gh release list --limit 100 --json tagName -q '.[].tagName' | grep '^sdk-' || true); do
	ID=${TAG#sdk-}
	echo "::group::ABI $ID"
	rm -rf "$WORK/$ID"; mkdir -p "$WORK/$ID"
	gh release download "$TAG" --dir "$WORK/$ID" --pattern 'nebulaos-sdk-*.tar.xz*'
	( cd "$WORK/$ID" && sha256sum -c nebulaos-sdk-"$ID".tar.xz.sha256 )
	tar -C "$WORK/$ID" -xJf "$WORK/$ID/nebulaos-sdk-$ID.tar.xz"
	rm -f "$WORK/$ID/nebulaos-sdk-$ID.tar.xz"
	# Relocate, build and gate inside the build image; the SDK's own Python
	# runs the gate (no assumption about the image's python3).
	# The image's entrypoint is ["sh", "-c"]: the script is its one argument.
	docker run --rm -v "$WORK/$ID:/w" -v "$HERE:/repo:ro" -v "$REQS:/reqs:ro" -w /w "$BUILD_IMAGE" "
		set -e
		cd /w/nebulaos-sdk-$ID && ./relocate-sdk.sh >/dev/null
		PATH=/w/nebulaos-sdk-$ID/bin:\$PATH sh /repo/scripts/build-wheels.sh /w/nebulaos-sdk-$ID /w/wheels /reqs/*.txt
		/w/nebulaos-sdk-$ID/bin/python3 /repo/scripts/check-wheels.py /w/nebulaos-sdk-$ID /w/nebulaos-sdk-$ID/python-abi /w/wheels
		/w/nebulaos-sdk-$ID/bin/python3 /repo/scripts/build-chelper.py /w/nebulaos-sdk-$ID /w/nebulaos-sdk-$ID/python-abi /reqs/chelper /w/chelper
		chmod -R a+rwX /w"
	python3 "$HERE/scripts/make-index.py" "$SITE" "$ID" "$WORK/$ID/nebulaos-sdk-$ID/python-abi" "$WORK/$ID/wheels" "$WORK/$ID/chelper"
	if [ -f "$WORK/$ID/chelper/.failed" ]; then
		sed "s/^/ABI $ID: /" "$WORK/$ID/chelper/.failed" >> "$FAILURES"
	fi
	if [ -f "$WORK/$ID/wheels/.failed" ]; then
		echo "Not built for $ID:"; cat "$WORK/$ID/wheels/.failed"
		sed "s/^/ABI $ID: not built: /" "$WORK/$ID/wheels/.failed" >> "$FAILURES"
	fi
	if ls "$WORK/$ID/wheels/rejected/"*.whl >/dev/null 2>&1; then
		for R in "$WORK/$ID/wheels/rejected/"*.whl; do
			echo "ABI $ID: rejected by the ABI check: ${R##*/}" >> "$FAILURES"
		done
	fi
	rm -rf "$WORK/$ID"
	echo "::endgroup::"
done
rm -rf "$WORK"
