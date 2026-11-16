#!/usr/bin/env python3
"""Write AppDB data files for one software: its entry (if new), a version (if
new) and a compatibility report with screenshots, laid out the way the
darling-appdb-database validator expects.

usage: new_entry.py <database checkout> <name> <version> <status> <description file>
           [--screenshot FILE ...] [--new-software JSON] [--new-version JSON]

  name           the display name, in the product's own spelling ("SkyFighters 1945");
                 the directory is the name without characters outside [A-Za-z0-9._-]
  status         platinum | gold | silver | bronze | garbage
  --new-software JSON object with links, cpu, free, categories (name is added)
  --new-version  JSON object with download and optionally issues (version is added)
Screenshots are copied as screenshot-0.png, screenshot-1.png, ... in the given
order. Prints the files written. Run the repository's own validator afterwards.
"""
import argparse
import json
import os
import re
import shutil
import sys
import uuid

NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
MAX_DISPLAY_NAME = 100


def directory_name(display_name):
    """The directory a display name is stored under ("Angry Birds" -> "AngryBirds")."""
    return re.sub(r"[^A-Za-z0-9._-]", "", display_name)
STATUSES = {"platinum", "gold", "silver", "bronze", "garbage"}


def software_dir(db, name):
    shard = name[:2] if len(name) > 1 else "_"
    return os.path.join(db, "data", "software", name[0], shard, name)


def write_json(path, data, written):
    if os.path.exists(path):
        sys.exit("%s already exists; new entries must not modify existing files" % path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent="\t", ensure_ascii=False)
        f.write("\n")
    written.append(path)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("db")
    p.add_argument("name")
    p.add_argument("version")
    p.add_argument("status")
    p.add_argument("description")
    p.add_argument("--screenshot", action="append", default=[])
    p.add_argument("--new-software")
    p.add_argument("--new-version")
    a = p.parse_args()

    if (not a.name or len(a.name) > MAX_DISPLAY_NAME or a.name != a.name.strip() or "  " in a.name
            or any(ord(c) < 0x20 or ord(c) == 0x7f for c in a.name)):
        sys.exit("name %r must be 1 to %d characters without leading, trailing or repeated spaces"
                 % (a.name, MAX_DISPLAY_NAME))
    dirname = directory_name(a.name)
    for value, what in ((dirname, "directory name"), (a.version, "version")):
        if not NAME.fullmatch(value):
            sys.exit("%s %r must match %s" % (what, value, NAME.pattern))
    if a.status not in STATUSES:
        sys.exit("status must be one of " + ", ".join(sorted(STATUSES)))
    if len(a.screenshot) > 5:
        sys.exit("at most 5 screenshots")
    for s in a.screenshot:
        if not s.endswith((".png", ".jpg")) or os.path.getsize(s) > 150 * 1024:
            sys.exit("%s: screenshots must be .png or .jpg and at most 150 KB" % s)
    with open(a.description) as f:
        description = f.read().strip()
    if not description or len(description) > 5000:
        sys.exit("the description must be 1 to 5000 characters")

    sw = software_dir(a.db, dirname)
    existing = os.path.join(a.db, "data", "software")
    for root, dirs, _ in os.walk(existing):
        for d in dirs:
            if root.count(os.sep) - existing.count(os.sep) == 2 and d.lower() == dirname.lower() and d != dirname:
                sys.exit("software %r already exists with different case; use that name" % d)

    written = []
    if a.new_software:
        data = {"name": a.name}
        data.update(json.loads(a.new_software))
        write_json(os.path.join(sw, "index.json"), data, written)
    elif not os.path.exists(os.path.join(sw, "index.json")):
        sys.exit("software %r does not exist; pass --new-software" % dirname)

    ver = os.path.join(sw, "versions", a.version)
    if a.new_version:
        data = {"version": a.version}
        data.update(json.loads(a.new_version))
        write_json(os.path.join(ver, "index.json"), data, written)
    elif not os.path.exists(os.path.join(ver, "index.json")):
        sys.exit("version %r does not exist; pass --new-version" % a.version)

    rid = uuid.uuid4().hex[:8]
    names = []
    for i, s in enumerate(a.screenshot):
        dest = os.path.join(ver, "reports", rid, "screenshot-%d%s" % (i, os.path.splitext(s)[1]))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(s, dest)
        written.append(dest)
        names.append(os.path.basename(dest))
    report = {"status": a.status, "description": description}
    if names:
        report["screenshots"] = names
    write_json(os.path.join(ver, "reports", rid + ".json"), report, written)
    print("\n".join(written))


if __name__ == "__main__":
    main()
