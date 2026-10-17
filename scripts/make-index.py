#!/usr/bin/env python3
"""Add checked wheels to a static PEP 503 index for one Python ABI id.

  make-index.py <site dir> <abi id> <python-abi file> <wheel dir>

Layout (GitHub Pages, branch gh-pages):
  simple/index.html                     the ABI ids
  simple/<id>/index.html                projects
  simple/<id>/<project>/index.html      links with #sha256=
  simple/<id>/<project>/<wheel>         the files
  simple/<id>/python-abi                the fingerprint the wheels were checked against

Append-only: a wheel already published is never replaced; one with the same
name but different bytes is refused (reported, left out).
"""
import hashlib
import html
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
        if not os.path.isdir(pdir):
            continue
        files = sorted(f for f in os.listdir(pdir) if f.endswith(".whl"))
        write(os.path.join(pdir, "index.html"), "Links for " + project,
              [("%s#sha256=%s" % (f, sha256(os.path.join(pdir, f))), f) for f in files])
    projects = sorted(p for p in os.listdir(root) if os.path.isdir(os.path.join(root, p)))
    write(os.path.join(root, "index.html"), "NebulaOS package index " + abi_id,
          [(p + "/", p) for p in projects])
    ids = sorted(d for d in os.listdir(os.path.join(site, "simple"))
                 if os.path.isdir(os.path.join(site, "simple", d)))
    write(os.path.join(site, "simple", "index.html"), "NebulaOS package index",
          [(d + "/", d) for d in ids])
    print("make-index: %d added, %d refused, %d projects for %s" % (added, refused, len(projects), abi_id))
    if refused:
        sys.exit(1)


if __name__ == "__main__":
    main()
