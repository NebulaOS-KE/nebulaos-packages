# NebulaOS package index

Ready-made Python packages (wheels) for printers running
[NebulaOS](https://github.com/coreflake1/NebulaOS), so Moonraker and Klipper
can update themselves - including their compiled dependencies - without a
compiler on the printer.

## How it works

- Every NebulaOS image carries a **Python ABI fingerprint**
  (`/usr/share/nebulaos/python-abi`): Python version, glibc, CPU/FP/NaN ABI,
  the libraries a package may link. Its `id` is part of the index path, and
  the image's `/etc/pip.conf` points pip at `simple/<id>/` with
  `only-binary = :all:` - pip on the printer never builds and never asks PyPI.
- The **SDK** of a firmware build (toolchain + sysroot, exported from an
  attested build with `tools/sdk/export-sdk.sh` in the firmware repo) is a
  release here, `sdk-<id>`.
- **GitHub Actions** (daily, manual, on push): collects the requirements of
  Moonraker's latest release and master and Klipper's master, cross-builds
  everything they resolve to with each SDK inside the firmware build image,
  **checks every compiled library** against the fingerprint (MIPS o32,
  mips32r2, FPXX, legacy NaN, glibc symbol versions, linked libraries), and
  adds the wheels to the index on GitHub Pages - append-only, with a sha256
  per file. Nothing published is ever deleted or replaced, so older versions
  stay installable.
- **Klipper's compiled helper** (`klippy/chelper` -> `c_helper.so`): built
  for Klipper master on every run and for the Klipper each image ships, with
  the firmware's own recipe and source hash (both travel inside the SDK,
  `nebulaos/`). The image's Klipper must rebuild byte-identical to the
  library the image ships, or nothing is published for that ABI. The printer
  looks a helper up by the hash of its Klipper's chelper sources.
- **Failures** (a package that does not build, a library the check rejects,
  a broken SDK) never stop the rest from being published; they make the run
  red and are reported in the open "Index build failures" issue.
- A **new firmware build** with a new ABI publishes its SDK here
  (`tools/sdk/publish-sdk.sh` in the firmware repo, after the build) and
  starts this workflow.

## Trust

The sha256 in the index protects against damaged downloads. It comes from
the same place as the files, so it is not a signature: the trust is GitHub
(this repository and its Pages site) over HTTPS.

## Layout

```
simple/<abi id>/                     pip index for one image ABI
simple/<abi id>/<project>/           wheels + index.html with #sha256=
simple/<abi id>/python-abi           the fingerprint they were checked against
chelper/<abi id>/index               "<source hash> <sha256> <size>" per line
chelper/<abi id>/<source hash>/c_helper.so
```

The helpers are outside `simple/`, so pip never sees them.

`packages.conf` holds per-package build settings (e.g. which Pillow features,
limited to libraries the image ships).
