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

## Verification state

| | |
|---|---|
| Source commit | `9d0d264` (branch `main`) |
| Tests | `tests/run-tests.sh`, 10 passed, 0 failed, run 2026-11-03 |
| Full CI pass | **not run here** - needs `gh`, Docker and the pinned build image |
| Hardware verification | **none** - no printer access; nothing on this page is an observation of a printer installing a wheel |

Everything above is established by reading the scripts at that commit and by running the offline
tests. The behaviour of a real index build against a real SDK is not claimed.
