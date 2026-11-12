# Four invariants

What is easy to break here without noticing, and what breaks if you do. Written against
`9d0d264`.

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
