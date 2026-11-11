# Developer reference: `nebulaos-packages`

Technical reference for the NebulaOS package index, at commit `9d0d264` (branch `main`).

**Read the repository [README](../../README.md) first.** It explains *what* the index is and
why it exists, and it is accurate. This page is the other half: how the pieces fit, how to run
them yourself, and the invariants that are easy to break without noticing.

## The problem this repository solves

Moonraker's update manager runs `pip install -U -r <requirements>` on the printer. The printer
has no compiler, no development headers, and a CPU and C library that PyPI has never heard of.
Left alone, pip would try to build a source distribution and fail - or worse, succeed against
the wrong ABI.

So the printer never talks to PyPI. The image's `/etc/pip.conf` points pip at
`simple/<abi id>/` on this repository's GitHub Pages site with `only-binary = :all:`, and
everything it can be asked for is already there, already compiled, already checked.

## The ABI fingerprint is the hinge

Every NebulaOS image carries `/usr/share/nebulaos/python-abi`: Python version, glibc, CPU, FP
and NaN ABI, and the libraries a package is allowed to link. Its `id` is the path component
that separates one image's index from another's.

That matters more than it looks. A wheel tag like `cp312-cp312-linux_mips` says **nothing**
about endianness, FP mode, NaN encoding, glibc version or linked libraries - all of which the
KE gets wrong by default. A wheel that installs cleanly and crashes at import is the failure
this design exists to prevent, and the tag cannot detect it.

So `check-wheels.py` opens every shared object and checks the things the tag cannot: ELF32
little-endian MIPS, o32, `mips32r2`, legacy NaN (no NaN2008 flag), FP ABI FPXX or no FP use,
the highest `GLIBC_x.y` symbol version against the fingerprint's glibc, and every `DT_NEEDED`
against the fingerprint's list of linkable sonames.

## The pieces

| Script | What it does |
|---|---|
| `scripts/collect-requirements.sh` | Writes one requirements file per source: Moonraker's latest release, Moonraker master, Klipper master, plus pip itself. These are what a printer's update can ask for. |
| `scripts/build-wheels.sh` | Resolves and cross-builds a requirements file against one SDK, using that SDK's host Python and crossenv, its gcc and its sysroot. A requirement that cannot be built is reported and skipped. |
| `scripts/build-chelper.py` | Builds Klipper's `c_helper.so` for one ABI, for Klipper master and for the Klipper the image ships. |
| `scripts/check-wheels.py` | The gate described above. Rejected wheels are moved to `<wheel dir>/rejected`; it always exits 0, because the caller publishes what passed. |
| `scripts/make-index.py` | Writes the static PEP 503 index onto the `gh-pages` site. |
| `scripts/ci-all.sh` | One full pass: every SDK release, in turn. |
| `tests/run-tests.sh` | Offline tests of the index logic - no GitHub, no container, no SDK. |
| `packages.conf` | Per-package build settings. One line per package. |
| `.github/workflows/index.yml` | Daily, manual, and on push. |

## Four invariants, and what breaks if you change them

**Append-only.** A file that has been published is never replaced. Wheel builds are not
reproducible, so rebuilding the same version produces different bytes; `make-index.py` keeps the
published file and drops the rebuild. That is normal operation, not a failure - and it is what
makes an older version stay installable forever, which is the whole point for a printer that
updates on its own schedule.

**One failure never stops the rest.** Each ABI runs on its own in `ci-all.sh`. A package that
will not build, a wheel the check rejects, a broken SDK - each is appended to the failures file,
the next ABI still runs, and everything that did build is published. The pass exits 0 unless the
pass itself could not run. The run goes red through the open *"Index build failures"* issue
instead, which is deliberate: a red pass that publishes nothing would take every printer's
updates down because one package broke.

**The helpers live outside `simple/`.** `chelper/<abi id>/...`, never under the pip namespace, so
pip cannot see them and cannot try to install one as a project. The tests check this explicitly.

**The chelper recipe is not in this repository.** How the helper is built travels inside the SDK,
exported from the attested firmware build: the recipe stage 04 uses, the preflight that computes
`chelper_source_hash` the same way the printer does, and the image library's own hash. This
repository only runs them. If the build recipe lived here it could drift from the one that made
the image, and the printer looks a helper up by the hash of its Klipper's chelper sources - a
drift would simply never match, or worse, match wrongly.

**The reproducibility gate.** The Klipper the image ships must rebuild byte-identical to the
library inside the image. If it does not, **nothing** is published for that ABI. That check is
what turns "we built a helper" into "we built *the* helper".

## Running it yourself

The offline tests need nothing but Python and a shell:

```sh
tests/run-tests.sh
```

Verified at `9d0d264` on 2026-11-03: **10 passed, 0 failed.** They cover the invariants above -
helpers outside `simple/`, append-only for helpers and for wheels, one ABI failing without
stopping the others, and only `sdk-*` releases being used.

A real pass needs an authenticated `gh`, Docker, and `BUILD_IMAGE` set to the firmware build
image pinned by digest - the SDK's host tools were built in it, so another image is not
equivalent. That is a CI-shaped job rather than a laptop one.

## Trust, stated plainly

The sha256 in the index protects against a damaged download. It comes from the same place as the
files, so it is **not a signature**: the trust is GitHub - this repository and its Pages site -
over HTTPS. The repository README says this too, and it is worth not softening.

## The image side, checked against NebulaOS 1.0.2 (2026-11-11)

Nothing in this repository changed for the release - `main` is still `9d0d264` - so this page is
re-verified rather than rewritten. What is worth recording is the other end of the contract, read
from firmware `3bdf3ff` (tag `v1.0.2`):

- **The image depends on this index at runtime only.** `manifests/dependencies.conf:595-609`
  carries both URLs - `NEBULAOS_PACKAGE_INDEX_URL=https://nebulaos-ke.github.io/nebulaos-packages/simple`
  and `NEBULAOS_CHELPER_INDEX_URL=https://nebulaos-ke.github.io/nebulaos-packages/chelper` - and
  says in as many words that *the firmware build itself never uses it*. A build is never waiting
  on this repository; a printer's update is.
- **A missing URL fails the build.** `scripts/build/02-configure-buildroot.sh:154-157` refuses to
  configure Buildroot without either one and writes them beside the board files as
  `package-index.url` and `chelper-index.url`.
- **The fingerprint is derived once, by the image that will use it.**
  `scripts/build/nebulaos-post-build.sh:117-140` sources `lib/python-abi.sh`, writes
  `/usr/share/nebulaos/python-abi`, generates `/etc/pip.conf` (`index-url = <url>/<id>/`,
  `only-binary = :all:`, `disable-pip-version-check = true`) and writes
  `/usr/share/nebulaos/chelper-index.url`. The manifest's `NEBULAOS_PYTHON_ABI_SCHEME=1` matches
  `PYTHON_ABI_SCHEME=1` in that script: a scheme change is meant to be visible on both sides.
- **The build gates what it produced.** `scripts/build/06-verify.sh:1688-1712` checks that the
  fingerprint is there and is the expected ABI (`platform_tag=linux_mips`, `fp32_mode=xx`,
  `nan=legacy`), that `/etc/pip.conf` names this index for *this* id with `only-binary`, and -
  explicitly - that it carries **no** `extra-index-url`. An image that could still fall back to
  PyPI does not pass its own verification.
- **`linkable` is a list, not a guess.** `python-abi.sh` offers `libz.so.1 libpng16.so.16
  libfreetype.so.6 libffi.so.8 libssl.so.3 libcrypto.so.3 libsodium.so.26 libstdc++.so.6
  libgcc_s.so.1` and records the ones the image actually has; `id` is the first 16 hex of a
  sha256 over the whole body. Adding a soname there moves every printer with that image to a new
  index path, which is the intended cost.
- **The helper index is read by the update supervisor, never at boot.**
  `/usr/share/nebulaos/chelper-index.url` is read by
  `overlay/usr/lib/nebulaos/python/nebulaos_osconfig/updates.py:39` and by
  `overlay/etc/nebulaos-chelper-preflight.sh`, in the layout this repository publishes:
  `<url>/<abi id>/index` with `<source hash> <sha256> <size>` per line, and
  `<url>/<abi id>/<source hash>/c_helper.so`.
- **The Klipper the reproducibility gate must match** is `KLIPPER_PIN=58bd67db` at `v1.0.2`
  (upstream `Klipper3d/klipper`) - the one composed into the image, not this repository's idea of
  master.

The index itself is alive: the `gh-pages` tip is `f29ba29`, published 2026-11-10, built from
`9d0d264`. That is the publish side of the daily workflow doing its job, read from the branch -
not an observation of a printer installing anything.

## Verification state

| | |
|---|---|
| Source commit | `9d0d264` (branch `main`) - unchanged since this page was written |
| Tests | `tests/run-tests.sh`, 10 passed, 0 failed - run 2026-11-03, re-run 2026-11-11 at the same commit |
| Image side | firmware `3bdf3ff` (NebulaOS 1.0.2): manifest, `02-configure-buildroot.sh`, `nebulaos-post-build.sh`, `06-verify.sh`, `lib/python-abi.sh` |
| Published index | `gh-pages` `f29ba29`, 2026-11-10, built from `9d0d264` - read from the branch, not fetched over HTTP |
| Full CI pass | **not run here** - needs `gh`, Docker and the pinned build image |
| Hardware verification | **none** - no printer access; nothing on this page is an observation of a printer installing a wheel |

Everything above is established by reading the scripts at that commit and by running the offline
tests. The behaviour of a real index build against a real SDK is not claimed.
