# The ABI fingerprint

The one idea the whole index turns on, and the gate that enforces it. Written against
`nebulaos-packages` at `9d0d264` (branch `main`).

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

## Why this matters more than it looks

Every path in the index - `simple/<abi id>/` for wheels and `chelper/<abi id>/...` for the
Klipper helper - is namespaced by this id. Two images with different ABIs read different indexes
and can never be served each other's binaries. Adding a soname to `linkable` moves every printer
with that image to a new index path, which is the intended cost of the design, not a side
effect.
