# The pipeline

The scripts, in the order a pass runs them, and how to run the offline parts yourself. Written
against `9d0d264`.

| Script | What it does |
|---|---|
| `scripts/collect-requirements.sh` | Writes one requirements file per source: Moonraker's latest release, Moonraker master, Klipper master, plus pip itself. These are what a printer's update can ask for. |
| `scripts/build-wheels.sh` | Resolves and cross-builds a requirements file against one SDK, using that SDK's host Python and crossenv, its gcc and its sysroot. A requirement that cannot be built is reported and skipped. |
| `scripts/build-chelper.py` | Builds Klipper's `c_helper.so` for one ABI, for Klipper master and for the Klipper the image ships. |
| `scripts/check-wheels.py` | The gate described in [The ABI fingerprint](ABI-Fingerprint). Rejected wheels are moved to `<wheel dir>/rejected`; it always exits 0, because the caller publishes what passed. |
| `scripts/make-index.py` | Writes the static PEP 503 index onto the `gh-pages` site. |
| `scripts/ci-all.sh` | One full pass: every SDK release, in turn. |
| `tests/run-tests.sh` | Offline tests of the index logic - no GitHub, no container, no SDK. |
| `packages.conf` | Per-package build settings. One line per package. |
| `.github/workflows/index.yml` | Daily, manual, and on push. |

## Running it yourself

The offline tests need nothing but Python and a shell:

```sh
tests/run-tests.sh
```

Verified at `9d0d264` on 2026-11-03, and re-run unchanged on 2026-11-11 and 2026-11-12: **10
passed, 0 failed.** They cover [the four invariants](Invariants) -
helpers outside `simple/`, append-only for helpers and for wheels, one ABI failing without
stopping the others, and only `sdk-*` releases being used.

A real pass needs an authenticated `gh`, Docker, and `BUILD_IMAGE` set to the firmware build
image pinned by digest - the SDK's host tools were built in it, so another image is not
equivalent. That is a CI-shaped job rather than a laptop one.
