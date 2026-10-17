#!/usr/bin/env python3
"""Gate every wheel against a NebulaOS image's Python ABI fingerprint before
it is published (architecture review 2026-10-17). A wheel tag such as
cp312-cp312-linux_mips says nothing about endianness, FP mode, NaN encoding,
glibc or linked libraries - so each shared object is checked:

  - ELF32, little endian (per the fingerprint), MIPS
  - o32, the fingerprint's ISA (mips32r2), no NaN2008 flag for legacy NaN
  - FP ABI FPXX ("Any FPU") or no FP use at all, for fp32_mode=xx
  - highest GLIBC_x.y symbol version <= the fingerprint's glibc
  - every DT_NEEDED is glibc itself or one of the fingerprint's linkable sonames
  - wheel tag: py3-none-any, or the fingerprint's cpXY/platform tag

  check-wheels.py <sdk dir> <python-abi file> <wheel dir>
Prints one line per wheel; rejected wheels are moved to <wheel dir>/rejected.
Exit 0 always - the caller publishes what passed.
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

GLIBC_LIBS = {"libc.so.6", "ld.so.1", "libm.so.6", "libpthread.so.0", "libdl.so.2",
              "librt.so.1", "libutil.so.1", "libresolv.so.2", "libcrypt.so.1"}
EF_MIPS_NAN2008 = 0x400


def read_abi(path):
    abi = {}
    with open(path) as handle:
        for line in handle:
            key, sep, value = line.strip().partition("=")
            if sep:
                abi[key] = value
    return abi


def vtuple(text):
    return tuple(int(p) for p in text.split(".") if p.isdigit())


def tool(sdk, name):
    found = glob.glob(os.path.join(sdk, "bin", "*-buildroot-linux-gnu-" + name))
    if not found:
        raise SystemExit("check-wheels: no %s in %s" % (name, sdk))
    return found[0]


def run(*argv):
    return subprocess.run(argv, capture_output=True, text=True).stdout


def check_so(path, abi, sdk):
    problems = []
    with open(path, "rb") as handle:
        head = handle.read(52)
    if head[:4] != b"\x7fELF":
        return ["not ELF"]
    if head[4] != 1:
        problems.append("not ELF32")
    want_data = 1 if abi.get("endian") == "little" else 2
    if head[5] != want_data:
        problems.append("wrong endianness")
    byteorder = "little" if head[5] == 1 else "big"
    machine = int.from_bytes(head[18:20], byteorder)
    if machine != 8:
        problems.append("not MIPS (e_machine %d)" % machine)
    flags = int.from_bytes(head[36:40], byteorder)
    if abi.get("nan") == "legacy" and flags & EF_MIPS_NAN2008:
        problems.append("NaN2008 code, image uses legacy NaN")
    header = run(tool(sdk, "readelf"), "-h", path)
    if abi.get("abi") == "32" and "o32" not in header:
        problems.append("not o32")
    if abi.get("arch") and abi["arch"] not in header:
        problems.append("ISA is not %s" % abi["arch"])
    attrs = run(tool(sdk, "readelf"), "-A", path)
    fp = re.search(r"FP ABI:\s*(.+)", attrs)
    fp = fp.group(1).strip() if fp else ""
    if abi.get("fp32_mode") == "xx" and fp and "Any FPU" not in fp and "Hard or soft" not in fp:
        problems.append("FP ABI '%s', image is FPXX" % fp)
    dyn = run(tool(sdk, "readelf"), "-d", path)
    linkable = set(abi.get("linkable", "").split()) | GLIBC_LIBS
    for needed in re.findall(r"\(NEEDED\).*\[(.+?)\]", dyn):
        if needed not in linkable:
            problems.append("links %s, not in the image's linkable set" % needed)
    syms = run(tool(sdk, "objdump"), "-T", path)
    versions = [vtuple(v) for v in re.findall(r"GLIBC_([0-9.]+)", syms)]
    glibc = vtuple(abi.get("glibc", "0"))
    if versions and max(versions) > glibc:
        problems.append("needs GLIBC_%s, image has %s" % (".".join(map(str, max(versions))), abi.get("glibc")))
    return problems


def check_wheel(whl, abi, sdk):
    name = os.path.basename(whl)
    tags = name[:-4].split("-")[-3:]
    py_tag = "cp" + abi["python"].replace(".", "")
    if tags == ["py3", "none", "any"] or (tags[0] in ("py3", "py2.py3") and tags[1:] == ["none", "any"]):
        pure = True
    elif tags[0] == py_tag and tags[2] == abi["platform_tag"] and tags[1] in (py_tag, "abi3", "none"):
        pure = False
    elif tags[1] == "abi3" and tags[2] == abi["platform_tag"]:
        pure = False
    else:
        return ["wheel tag %s does not fit this ABI" % "-".join(tags)]
    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(whl) as zf:
            zf.extractall(tmp)
        objects = [os.path.join(r, f) for r, _, fs in os.walk(tmp) for f in fs
                   if re.search(r"\.so(\.|$)", f)]
        if pure and objects:
            problems.append("pure-tagged wheel carries shared objects")
        for obj in objects:
            for p in check_so(obj, abi, sdk):
                problems.append("%s: %s" % (os.path.relpath(obj, tmp), p))
    return problems


def main():
    sdk, abi_path, wheels = sys.argv[1:4]
    abi = read_abi(abi_path)
    rejected = os.path.join(wheels, "rejected")
    ok = bad = 0
    for whl in sorted(glob.glob(os.path.join(wheels, "*.whl"))):
        problems = check_wheel(whl, abi, sdk)
        if problems:
            bad += 1
            os.makedirs(rejected, exist_ok=True)
            shutil.move(whl, os.path.join(rejected, os.path.basename(whl)))
            print("REJECT %s: %s" % (os.path.basename(whl), "; ".join(problems)))
        else:
            ok += 1
            print("OK     %s" % os.path.basename(whl))
    print("check-wheels: %d passed, %d rejected" % (ok, bad))


if __name__ == "__main__":
    main()
