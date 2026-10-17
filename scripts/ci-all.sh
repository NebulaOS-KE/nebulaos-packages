#!/bin/sh
# One CI pass: for every NebulaOS SDK release (one per Python ABI id), build
# the wheels the requirements resolve to, gate them, add them to the index.
#
#   ci-all.sh <requirements dir> <site dir>
# Needs: gh (authenticated), docker, BUILD_IMAGE (the firmware build image,
# pinned by digest - the SDK's host tools were built in it).
set -eu
REQS=$(cd "${1:?}" && pwd)
SITE=$(mkdir -p "${2:?}" && cd "$2" && pwd)
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
		sh /repo/scripts/build-wheels.sh /w/nebulaos-sdk-$ID /w/wheels /reqs/*.txt
		/w/nebulaos-sdk-$ID/bin/python3 /repo/scripts/check-wheels.py /w/nebulaos-sdk-$ID /w/nebulaos-sdk-$ID/python-abi /w/wheels
		chmod -R a+rwX /w"
	python3 "$HERE/scripts/make-index.py" "$SITE" "$ID" "$WORK/$ID/nebulaos-sdk-$ID/python-abi" "$WORK/$ID/wheels"
	[ ! -f "$WORK/$ID/wheels/.failed" ] || { echo "Not built for $ID:"; cat "$WORK/$ID/wheels/.failed"; }
	ls "$WORK/$ID/wheels/rejected" 2>/dev/null && echo "(rejected - see the gate output above)" || true
	rm -rf "$WORK/$ID"
	echo "::endgroup::"
done
rm -rf "$WORK"
