#!/usr/bin/env python3
"""G72: Klipper's compiled helper (klippy/chelper -> c_helper.so) for one
NebulaOS ABI, so a Klipper update never needs a compiler on the printer.

  build-chelper.py <sdk dir> <python-abi file> <sources root> <out dir>

<sources root> holds one Klipper tree per ref: <ref>/klippy/chelper/...
(collect-requirements.sh: master; ci-all.sh adds "pinned", the Klipper the
image ships).

Nothing about HOW the helper is built lives in this repository: the SDK
carries the firmware's own files (exported with it from the attested build):
  nebulaos/build-chelper.sh               the recipe - the one stage 04 uses
  nebulaos/nebulaos-chelper-preflight.sh  chelper_source_hash - the one the
                                          printer computes over its Klipper
  nebulaos/image-chelper                  the image library's source hash and
                                          sha256
Each library is checked like every wheel (check-wheels.check_so) and written
to <out>/<source hash>/c_helper.so (+ refs).

Reproducibility gate: "pinned" must rebuild byte-identical to the library
the image ships. If it does not, nothing is published for this ABI (the
CI-built helpers would not be the image's).
"""
import glob
import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys


def sha256(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def source_hash(lib, tree):
    out = subprocess.run(["sh", "-c", '. "$1"; chelper_source_hash "$2"', "sh", lib, tree],
                         capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def main():
    sdk, abi_file, sources, out = sys.argv[1:5]
    tools = os.path.join(sdk, "nebulaos")
    recipe = os.path.join(tools, "build-chelper.sh")
    lib = os.path.join(tools, "nebulaos-chelper-preflight.sh")
    if not (os.path.isfile(recipe) and os.path.isfile(lib)):
        print("SKIP   this SDK predates the shared chelper recipe - no helpers for it")
        return
    record = {}
    if os.path.isfile(os.path.join(tools, "image-chelper")):
        for line in open(os.path.join(tools, "image-chelper")):
            if "=" in line:
                key, value = line.strip().split("=", 1)
                record[key] = value
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("check_wheels", os.path.join(here, "check-wheels.py"))
    cw = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cw)
    abi = cw.read_abi(abi_file)
    prefix = glob.glob(os.path.join(sdk, "bin", "*-buildroot-linux-gnu-gcc"))[0][:-len("gcc")]
    os.makedirs(out, exist_ok=True)
    failures, built = [], {}
    for ref in sorted(os.listdir(sources)):
        tree = os.path.join(sources, ref)
        key = source_hash(lib, tree)
        if not key:
            failures.append("chelper %s: no source hash" % ref)
            continue
        work = os.path.join(out, ".work", ref)
        shutil.rmtree(work, ignore_errors=True)
        shutil.copytree(os.path.join(tree, "klippy", "chelper"), work)
        for so in glob.glob(os.path.join(work, "*.so")):
            os.unlink(so)
        proc = subprocess.run(["sh", recipe, work, prefix], capture_output=True, text=True)
        libso = os.path.join(work, "c_helper.so")
        if proc.returncode != 0 or not os.path.isfile(libso):
            failures.append("chelper %s: build failed: %s" % (ref, proc.stderr.strip()[-400:]))
            print("FAIL   %s" % failures[-1])
            continue
        problems = cw.check_so(libso, abi, sdk)
        if problems:
            failures.append("chelper %s: rejected by the ABI check: %s" % (ref, "; ".join(problems)))
            print("REJECT %s" % failures[-1])
            continue
        built[ref] = (key, libso)
        print("OK     %s: source hash %s" % (ref, key[:16]))
    if "pinned" in built and record:
        key, libso = built["pinned"]
        if key != record.get("source_hash") or sha256(libso) != record.get("sha256"):
            failures.append("chelper: the image's Klipper (%s) did not rebuild byte-identical to the "
                            "shipped c_helper.so (source hash %s vs %s, sha256 %s vs %s) - nothing "
                            "published for this ABI" % (record.get("klipper_commit", "?")[:12], key[:16],
                                                       record.get("source_hash", "?")[:16],
                                                       sha256(libso)[:16], record.get("sha256", "?")[:16]))
            print("FAIL   %s" % failures[-1])
            built = {}
        else:
            print("OK     reproducible: the pinned Klipper rebuilds byte-identical to the image's c_helper.so")
    elif record:
        failures.append("chelper: the image's Klipper was not built - reproducibility unproven, nothing published")
        built = {}
    for ref, (key, libso) in sorted(built.items()):
        dest = os.path.join(out, key)
        os.makedirs(dest, exist_ok=True)
        shutil.copy2(libso, os.path.join(dest, "c_helper.so"))
        with open(os.path.join(dest, "refs"), "a") as handle:
            handle.write(ref + "\n")
    shutil.rmtree(os.path.join(out, ".work"), ignore_errors=True)
    if failures:
        with open(os.path.join(out, ".failed"), "a") as handle:
            handle.write("\n".join(failures) + "\n")


if __name__ == "__main__":
    main()
