#!/usr/bin/env python3
"""Add checked wheels to a static PEP 503 index for one Python ABI id.

  make-index.py <site dir> <abi id> <python-abi file> <wheel dir> [<chelper dir>]

Layout (GitHub Pages, branch gh-pages):
  simple/index.html                     the ABI ids
  simple/<id>/index.html                projects
  simple/<id>/<project>/index.html      links with #sha256=
  simple/<id>/<project>/<wheel>         the files
  simple/<id>/python-abi                the fingerprint the wheels were checked against
  simple/<id>/chelper/<key>/c_helper.so Klipper's compiled helper (G72), by source key
  simple/<id>/chelper/index.json        {key: {"sha256", "size", "refs"}}

Append-only: a wheel already published is never replaced; one with the same
name but different bytes is refused (reported, left out).
"""
import hashlib
import html
import json
import os
import re
import shutil
import sys


def normalize(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write(path, title, links):
    body = "\n".join('    <a href="%s">%s</a><br/>' % (html.escape(h, True), html.escape(t))
                     for h, t in links)
    with open(path + ".tmp", "w") as handle:
        handle.write("<!DOCTYPE html>\n<html>\n  <head><meta name=\"pypi:repository-version\" "
                     "content=\"1.0\"><title>%s</title></head>\n  <body>\n%s\n  </body>\n</html>\n"
                     % (html.escape(title), body))
    os.replace(path + ".tmp", path)


def add_chelper(root, src_dir):
    """Append-only, like the wheels: a published helper is never replaced."""
    cdir = os.path.join(root, "chelper")
    os.makedirs(cdir, exist_ok=True)
    index_path = os.path.join(cdir, "index.json")
    try:
        with open(index_path) as handle:
            index = json.load(handle)
    except (OSError, ValueError):
        index = {}
    added = refused = 0
    for key in sorted(os.listdir(src_dir)):
        lib = os.path.join(src_dir, key, "c_helper.so")
        if not (len(key) == 64 and os.path.isfile(lib)):
            continue
        refs = sorted(set(open(os.path.join(src_dir, key, "refs")).read().split()))
        dest = os.path.join(cdir, key, "c_helper.so")
        digest = sha256(lib)
        if os.path.exists(dest):
            if sha256(dest) != digest and index.get(key, {}).get("sha256") != digest:
                # the same sources rebuilt to other bytes: keep the published one
                print("KEPT    chelper %s (already published)" % key[:16])
            entry = index.setdefault(key, {"sha256": sha256(dest), "size": os.path.getsize(dest), "refs": []})
            entry["refs"] = sorted(set(entry.get("refs", [])) | set(refs))
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(lib, dest)
        index[key] = {"sha256": digest, "size": os.path.getsize(dest), "refs": refs}
        added += 1
        print("ADDED   chelper %s (%s)" % (key[:16], ", ".join(refs)))
    with open(index_path + ".tmp", "w") as handle:
        json.dump(index, handle, indent=1, sort_keys=True)
    os.replace(index_path + ".tmp", index_path)
    return added, refused


def main():
    site, abi_id, abi_file, wheels = sys.argv[1:5]
    root = os.path.join(site, "simple", abi_id)
    os.makedirs(root, exist_ok=True)
    shutil.copy(abi_file, os.path.join(root, "python-abi"))
    added = refused = 0
    for name in sorted(os.listdir(wheels)):
        if not name.endswith(".whl"):
            continue
        project = normalize(name.split("-")[0])
        pdir = os.path.join(root, project)
        os.makedirs(pdir, exist_ok=True)
        dest = os.path.join(pdir, name)
        src = os.path.join(wheels, name)
        if os.path.exists(dest):
            if sha256(dest) != sha256(src):
                refused += 1
                print("REFUSED %s: already published with different bytes" % name)
            continue
        shutil.copy2(src, dest)
        added += 1
        print("ADDED   %s" % name)
    for project in sorted(os.listdir(root)):
        pdir = os.path.join(root, project)
        if not os.path.isdir(pdir) or project == "chelper":
            continue
        files = sorted(f for f in os.listdir(pdir) if f.endswith(".whl"))
        write(os.path.join(pdir, "index.html"), "Links for " + project,
              [("%s#sha256=%s" % (f, sha256(os.path.join(pdir, f))), f) for f in files])
    projects = sorted(p for p in os.listdir(root) if os.path.isdir(os.path.join(root, p)) and p != "chelper")
    write(os.path.join(root, "index.html"), "NebulaOS package index " + abi_id,
          [(p + "/", p) for p in projects])
    ids = sorted(d for d in os.listdir(os.path.join(site, "simple"))
                 if os.path.isdir(os.path.join(site, "simple", d)))
    write(os.path.join(site, "simple", "index.html"), "NebulaOS package index",
          [(d + "/", d) for d in ids])
    if len(sys.argv) > 5 and os.path.isdir(sys.argv[5]):
        a, r = add_chelper(root, sys.argv[5])
        added += a
        refused += r
    print("make-index: %d added, %d refused, %d projects for %s" % (added, refused, len(projects), abi_id))
    if refused:
        sys.exit(1)


if __name__ == "__main__":
    main()
