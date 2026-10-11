#!/bin/sh
#
# Apply the changes this device needs in the LineageOS sources themselves.
#
# Run from the device directory inside the LineageOS tree:
#   cd <tree>/device/asus/ASUS_P00I && ./tools/apply-tree-patches.sh
#
# Everything else here lives in the device tree and leaves LineageOS as `repo sync`
# delivers it. What is in tools/tree-patches/ could not be done from outside: each
# patch says what it fixes. They are laid out by project, tools/tree-patches/<path of
# the project in the tree>/NNNN-*.patch, and applied with `git apply` in that project.
#
# Running it again applies only what is new. After a `repo sync` that rewrites a
# patched project, run it again.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tree=$(CDPATH= cd -- "$here/../../../.." && pwd)
[ -d "$tree/.repo" ] || { echo "error: $tree is not the top of a repo tree" >&2; exit 1; }

cd "$here/tree-patches"
for p in $(find . -name '*.patch' | sort); do
    project=$(dirname "${p#./}")
    name=$(basename "$p")
    [ -d "$tree/$project" ] || { echo "error: no project $project in $tree" >&2; exit 1; }
    if git -C "$tree/$project" apply --reverse --check "$here/tree-patches/$p" 2>/dev/null; then
        echo "    already applied $project: $name"
    elif git -C "$tree/$project" apply --check "$here/tree-patches/$p" 2>/dev/null; then
        git -C "$tree/$project" apply "$here/tree-patches/$p"
        echo "    applied $project: $name"
    else
        echo "    FAILED $project: $name" >&2
        exit 1
    fi
done
