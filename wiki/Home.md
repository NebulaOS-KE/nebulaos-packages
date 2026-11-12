# nebulaos-packages

The NebulaOS package index: ready-made Python wheels, and Klipper's compiled `c_helper.so`, built
for exactly the ABI a NebulaOS image has. A printer never compiles anything, and **never talks to
PyPI**.

This wiki is the developer documentation. The end-user manual is the
[NebulaOS wiki](https://github.com/NebulaOS-KE/NebulaOS/wiki).

## Which code this describes

| | |
|---|---|
| This repository | **`9d0d264`** (branch `main`) |
| Image side read from | firmware **`3bdf3ff`** (NebulaOS 1.0.2, tag `v1.0.2`) |
| Published index | `gh-pages` `9bef4d4`, published 2026-11-11, built from `9d0d264` - read from the branch, not fetched over HTTP |

## The problem this repository solves

Moonraker's update manager runs `pip install -U -r <requirements>` on the printer. The printer
has no compiler, no development headers, and a CPU and C library that PyPI has never heard of.
Left alone, pip would try to build a source distribution and fail - or worse, succeed against
the wrong ABI.

So the printer never talks to PyPI. The image's `/etc/pip.conf` points pip at
`simple/<abi id>/` on this repository's GitHub Pages site with `only-binary = :all:`, and
everything it can be asked for is already there, already compiled, already checked.

## The pages

- **[The ABI fingerprint](ABI-Fingerprint)** - the hinge the whole design turns on, and the
  checks a wheel tag cannot make
- **[The pipeline](The-Pipeline)** - the scripts, what each one does, and the offline tests
- **[Four invariants](Invariants)** - append-only, one failure never stops the rest, helpers
  outside `simple/`, and the reproducibility gate
- **[The image side](The-Image-Side)** - the other end of the contract, read from firmware
  `3bdf3ff`: runtime-only dependency, a missing URL failing the build, the fingerprint derived
  once, and an image that cannot fall back to PyPI

## Trust, stated plainly

The sha256 in the index protects against a damaged download. It comes from the same place as the
files, so it is **not a signature**: the trust is GitHub - this repository and its Pages site -
over HTTPS. The repository README says this too, and it is worth not softening.

## Verification state

| | |
|---|---|
| Source commit | `9d0d264` (branch `main`) - unchanged since this page was written |
| Tests | `tests/run-tests.sh`, 10 passed, 0 failed - run 2026-11-03, re-run 2026-11-11 and again 2026-11-12, all at `9d0d264` |
| Image side | firmware `3bdf3ff` (NebulaOS 1.0.2): manifest, `02-configure-buildroot.sh`, `nebulaos-post-build.sh`, `06-verify.sh`, `lib/python-abi.sh` |
| Published index | `gh-pages` `9bef4d4`, published 2026-11-11, built from `9d0d264` - read from the branch, not fetched over HTTP |
| Full CI pass | **not run here** - needs `gh`, Docker and the pinned build image |
| Hardware verification | **none** - no printer access; nothing on this page is an observation of a printer installing a wheel |

Everything above is established by reading the scripts at that commit and by running the offline
tests. The behaviour of a real index build against a real SDK is not claimed.

## Related

- [NebulaOS-firmware wiki](https://github.com/NebulaOS-KE/NebulaOS-firmware/wiki) - the image
  that carries the fingerprint and the `pip.conf` this index serves
- [Repository map](https://github.com/NebulaOS-KE/NebulaOS-firmware/wiki/Repository-Map)
