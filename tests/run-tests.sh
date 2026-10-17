#!/bin/sh
# Offline tests for the index scripts (no GitHub, no container, no SDK).
#
#   - make-index keeps c_helper.so outside simple/ (pip never sees it) and
#     never replaces a published helper
#   - ci-all: one ABI failing does not stop the others, every failure is
#     recorded, and the pass still exits 0 so the rest is published
#
# Usage: sh tests/run-tests.sh
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/index-tests.XXXXXX")
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "FATAL: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT INT TERM
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- make-index ---------------------------------------------------------
H1=$(printf 'a%.0s' $(seq 64)); H2=$(printf 'b%.0s' $(seq 64))
mkdir -p "$WORK/wheels" "$WORK/ch/$H1" "$WORK/site"
printf 'id=abc\n' > "$WORK/abi"
printf 'wheel' > "$WORK/wheels/foo-1.0-py3-none-any.whl"
printf 'lib1' > "$WORK/ch/$H1/c_helper.so"; echo master > "$WORK/ch/$H1/refs"
python3 "$HERE/scripts/make-index.py" "$WORK/site" abc "$WORK/abi" "$WORK/wheels" "$WORK/ch" > /dev/null
[ ! -e "$WORK/site/simple/abc/chelper" ] && ! grep -q chelper "$WORK/site/simple/abc/index.html" \
	&& pass "make-index: no chelper under simple/ (pip's namespace)" || fail "make-index: chelper inside simple/"
grep -q '>foo<' "$WORK/site/simple/abc/index.html" && pass "make-index: wheels still indexed" || fail "make-index: wheel missing"
LINE="$H1 $(sha256sum "$WORK/ch/$H1/c_helper.so" | cut -d' ' -f1) 4"
[ "$(cat "$WORK/site/chelper/abc/index")" = "$LINE" ] && pass "make-index: chelper/<id>/index has '<hash> <sha256> <size>'" \
	|| { fail "make-index: chelper index"; cat "$WORK/site/chelper/abc/index"; }
# Second pass: other bytes for the same hash are kept out, a new hash added.
printf 'other' > "$WORK/ch/$H1/c_helper.so"
mkdir -p "$WORK/ch/$H2"; printf 'lib2' > "$WORK/ch/$H2/c_helper.so"; echo master > "$WORK/ch/$H2/refs"
python3 "$HERE/scripts/make-index.py" "$WORK/site" abc "$WORK/abi" "$WORK/wheels" "$WORK/ch" > /dev/null
[ "$(cat "$WORK/site/chelper/abc/$H1/c_helper.so")" = lib1 ] && [ "$(wc -l < "$WORK/site/chelper/abc/index")" -eq 2 ] \
	&& pass "make-index: append-only for helpers (published bytes never replaced)" || fail "make-index: helper replaced or not added"
python3 "$HERE/scripts/make-index.py" "$WORK/site" abc "$WORK/abi" "$WORK/wheels" > /dev/null
[ "$(wc -l < "$WORK/site/chelper/abc/index")" -eq 2 ] && pass "make-index: a run without helpers leaves the chelper tree alone" \
	|| fail "make-index: chelper tree changed by a wheels-only run"

printf 'rebuilt' > "$WORK/wheels/foo-1.0-py3-none-any.whl"
python3 "$HERE/scripts/make-index.py" "$WORK/site" abc "$WORK/abi" "$WORK/wheels" > /dev/null
rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$WORK/site/simple/abc/foo/foo-1.0-py3-none-any.whl")" = wheel ] \
	&& pass "make-index: a rebuilt wheel with other bytes keeps the published one, no failure" || fail "make-index: rebuilt wheel (rc=$rc)"

# --- ci-all: per-ABI isolation ------------------------------------------
mkdir -p "$WORK/bin" "$WORK/reqs" "$WORK/site2"
cat > "$WORK/bin/gh" <<EOF
#!/bin/sh
echo "\$*" >> "$WORK/gh.log"
case "\$1 \$2" in
	"release list") printf 'sdk-bad\nsdk-good\nother\n' ;;
	"release download")
		[ "\$3" = sdk-bad ] && exit 1
		D=\$5; mkdir -p "\$D/x/nebulaos-sdk-good"; printf 'id=good\n' > "\$D/x/nebulaos-sdk-good/python-abi"
		tar -C "\$D/x" -cJf "\$D/nebulaos-sdk-good.tar.xz" nebulaos-sdk-good; rm -rf "\$D/x"
		( cd "\$D" && sha256sum nebulaos-sdk-good.tar.xz > nebulaos-sdk-good.tar.xz.sha256 ) ;;
esac
EOF
# The container: creates an empty wheel dir in the mounted work dir.
CT=$(printf 'do%sker' c)
cat > "$WORK/bin/$CT" <<EOF
#!/bin/sh
echo "\$*" >> "$WORK/ct.log"
W=\$(echo "\$*" | sed -n 's#.*-v \([^:]*\):/w .*#\1#p')
mkdir -p "\$W/wheels" "\$W/chelper"
EOF
chmod 755 "$WORK/bin/gh" "$WORK/bin/$CT"
PATH="$WORK/bin:$PATH" BUILD_IMAGE=img sh "$HERE/scripts/ci-all.sh" "$WORK/reqs" "$WORK/site2" "$WORK/failures" > "$WORK/ci.log" 2>&1
rc=$?
[ "$rc" -eq 0 ] && pass "ci-all: exits 0 with a failing ABI (the rest is still published)" || { fail "ci-all rc=$rc"; cat "$WORK/ci.log"; }
grep -q '^ABI bad: the build for this ABI stopped early' "$WORK/failures" && pass "ci-all: the failing ABI is recorded" \
	|| { fail "ci-all: failure not recorded"; cat "$WORK/failures" "$WORK/ci.log"; }
[ -f "$WORK/site2/simple/good/python-abi" ] && grep -q 'nebulaos-sdk-good' "$WORK/ct.log" \
	&& pass "ci-all: the next ABI still builds and is indexed" || { fail "ci-all: good ABI not processed"; cat "$WORK/ci.log"; }
! grep -q 'other' "$WORK/gh.log" && pass "ci-all: only sdk-* releases are used" || fail "ci-all: non-SDK release used"

echo "index-tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
