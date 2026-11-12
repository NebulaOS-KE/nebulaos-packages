# The image side of the contract

This repository is one end of a contract; the NebulaOS image is the other. Read from firmware
`3bdf3ff` (tag `v1.0.2`) on 2026-11-11.

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

The index itself is alive: the `gh-pages` tip is `9bef4d4`, published 2026-11-11, built from
`9d0d264` - and the three commits before it are the same thing on 2026-11-10, 2026-11-07 and
earlier, each naming the source commit it was built from. That is the publish side of the daily
workflow doing its job, read from the branch - not an observation of a printer installing
anything.
