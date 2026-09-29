#!/usr/bin/env python3
"""Drops project.pbxproj references to source files that are not in the tree.

After a merge takes upstream's project file, it still lists every Pro file this fork deleted. Xcode skips an
unresolvable entry silently, so the project builds and stays malformed; this removes, in order: file references
whose file is gone, build files pointing at them, list entries naming any object that no longer exists, and
groups left empty or unreachable. Run from the repository root; prints what it removed.
"""
import os
import re
import subprocess
import sys

PROJECT = "alt-tab-macos.xcodeproj/project.pbxproj"
ID = r"[0-9A-Z]{24}"


def tree_files():
    names = set()
    listed = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"],
                            capture_output=True, text=True, check=True).stdout
    for path in listed.splitlines():
        if os.path.exists(path):
            names.add(os.path.basename(path))
    return names


def drop_lines(text, ids):
    kept = [line for line in text.split("\n")
            if not ((m := re.match(rf"^\t+({ID}) ", line)) and m.group(1) in ids)]
    return "\n".join(kept)


def main():
    text = open(PROJECT).read()
    present = tree_files()
    refs = re.findall(rf'^\t\t({ID}) /\* ([^*]+?) \*/ = \{{isa = PBXFileReference;[^\n]*?path = ("?)([^;"]+)\3;',
                      text, re.M)
    dead_refs = {i: n for i, n, _, path in refs
                 if path.endswith((".swift", ".md", ".m", ".h")) and os.path.basename(path) not in present}
    builds = re.findall(rf"^\t\t({ID}) /\* [^\n]*isa = PBXBuildFile; fileRef = ({ID})", text, re.M)
    dead_builds = {b for b, f in builds if f in dead_refs}
    text = drop_lines(text, set(dead_refs) | dead_builds)

    defined = set(re.findall(rf"^\t\t({ID}) (?:/\*[^*]*\*/ )?= \{{", text, re.M))
    dangling = {i for i in re.findall(rf"^\t{{3,}}({ID}) /\*[^\n]*,$", text, re.M) if i not in defined}
    text = drop_lines(text, dangling)

    removed_groups = []
    while True:
        changed = False
        for gid, name in re.findall(rf"^\t\t({ID}) /\* ([^*]+) \*/ = \{{\n\t\t\tisa = PBXGroup;", text, re.M):
            block = re.search(rf"^\t\t{gid} /\* [^*]+ \*/ = \{{\n.*?^\t\t\}};\n", text, re.M | re.S)
            empty = re.search(r"children = \(\n\t\t\t\);", block.group(0))
            orphan = text.count(gid) == 1
            if empty or orphan:
                text = text[:block.start()] + text[block.end():]
                text = drop_lines(text, {gid})
                removed_groups.append(name)
                changed = True
                break
        if not changed:
            break

    open(PROJECT, "w").write(text)
    for name in sorted(set(dead_refs.values())):
        print(f"removed file reference: {name}")
    if dangling:
        print(f"removed {len(dangling)} dangling list entries")
    for name in removed_groups:
        print(f"removed group: {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
