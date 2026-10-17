#!/usr/bin/env python3
"""G72: Klipper's compiled helper (klippy/chelper -> c_helper.so) for one
NebulaOS ABI, so a Klipper update never needs a compiler on the printer.

  build-chelper.py <sdk dir> <python-abi file> <chelper sources root> <out dir>

<chelper sources root> holds one directory per Klipper ref (collect-
requirements.sh). Each is built exactly as Klipper's own
klippy/chelper/__init__.py does - SOURCE_FILES and COMPILE_ARGS read out of
that file (as the firmware build does), the SDK's gcc for "gcc", no SSE flags
(upstream adds them only when the compiler accepts them) - then checked like
every wheel (check-wheels.py), and written to

  <out>/<key>/c_helper.so    <out>/<key>/refs   (the Klipper refs with this key)

<key> = chelper_key(): sha256 over "<name> <sha256 of content>\\n" for every
*.c, *.h and __init__.py in klippy/chelper, sorted by name. NebulaOS on the
printer computes the same key over its installed Klipper (any change to those
files - also ones Klipper's own staleness list leaves out, like compiler.h -
means another key).
"""
import ast
import glob
import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys


def chelper_key(directory):
    lines = []
    for name in sorted(os.listdir(directory)):
        if name.endswith((".c", ".h")) or name == "__init__.py":
            with open(os.path.join(directory, name), "rb") as handle:
                lines.append("%s %s\n" % (name, hashlib.sha256(handle.read()).hexdigest()))
    return hashlib.sha256("".join(lines).encode()).hexdigest()


def recipe(directory):
    tree = ast.parse(open(os.path.join(directory, "__init__.py")).read())
    found = {}
    for node in tree.body:
        if (isinstance(node, ast.Assign) and len(node.targets) == 1
                and isinstance(node.targets[0], ast.Name)
                and node.targets[0].id in ("SOURCE_FILES", "COMPILE_ARGS", "DEST_LIB")):
            found[node.targets[0].id] = ast.literal_eval(node.value)
    missing = {"SOURCE_FILES", "COMPILE_ARGS", "DEST_LIB"} - set(found)
    if missing:
        raise SystemExit("chelper/__init__.py no longer defines %s" % ", ".join(sorted(missing)))
    return found


def main():
    sdk, abi_file, sources, out = sys.argv[1:5]
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("check_wheels", os.path.join(here, "check-wheels.py"))
    cw = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cw)
    abi = cw.read_abi(abi_file)
    gcc = glob.glob(os.path.join(sdk, "bin", "*-buildroot-linux-gnu-gcc"))[0]
    failures = []
    for ref in sorted(os.listdir(sources)):
        src = os.path.join(sources, ref)
        key = chelper_key(src)
        dest = os.path.join(out, key)
        if os.path.isfile(os.path.join(dest, "c_helper.so")):
            print("SAME   %s: key %s already built" % (ref, key[:16]))
            with open(os.path.join(dest, "refs"), "a") as handle:
                handle.write(ref + "\n")
            continue
        r = recipe(src)
        work = os.path.join(out, ".work-" + key)
        shutil.rmtree(work, ignore_errors=True)
        shutil.copytree(src, work)
        args = r["COMPILE_ARGS"] % (r["DEST_LIB"], " ".join(r["SOURCE_FILES"]))
        proc = subprocess.run("%s %s" % (gcc, args), shell=True, cwd=work, capture_output=True, text=True)
        lib = os.path.join(work, r["DEST_LIB"])
        if proc.returncode != 0 or not os.path.isfile(lib):
            failures.append("chelper %s: compile failed: %s" % (ref, proc.stderr.strip()[-400:]))
            print("FAIL   %s" % failures[-1])
            continue
        problems = cw.check_so(lib, abi, sdk)
        if problems:
            failures.append("chelper %s: rejected by the ABI check: %s" % (ref, "; ".join(problems)))
            print("REJECT %s" % failures[-1])
            continue
        os.makedirs(dest, exist_ok=True)
        shutil.copy2(lib, os.path.join(dest, "c_helper.so"))
        with open(os.path.join(dest, "refs"), "a") as handle:
            handle.write(ref + "\n")
        shutil.rmtree(work, ignore_errors=True)
        print("OK     %s: key %s (%d sources)" % (ref, key[:16], len(r["SOURCE_FILES"])))
    if failures:
        with open(os.path.join(out, ".failed"), "a") as handle:
            handle.write("\n".join(failures) + "\n")


if __name__ == "__main__":
    main()
