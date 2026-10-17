#!/bin/sh
#
# Put SQLite 3.44.5 in the tree's external/sqlite, in place of 3.42.1.
#
# Run from the device directory inside the LineageOS tree, after `repo sync`:
#   cd <tree>/device/asus/ASUS_P00I && ./tools/setup-sqlite.sh
#
# Why: the query planner of 3.42.1, the version Google backported to Android 13,
# puts a full-text (FTS4) table in the inner loop of a join, and so runs the
# full-text match once for every row of the outer table. F-Droid's search is such a
# join: on this tablet "gps*" took 37 s and "gp*" 88 s over 4,760 apps, and the
# search looked hung. 3.44.5 puts the full-text table outside and answers in a
# hundredth of a second; the same query on the same database, on a PC, went from
# 8.4 s to 0.011 s. Any other app that joins on a full-text table gains the same way.
#
# 3.44.5 is what LineageOS 22.2 (Android 15) ships, with Google's Android changes
# already applied (dist/sqlite-autoconf-3440300/Android.patch, the same changes as
# 3.42.1's). Only the four source files are taken, and the patched copies under
# dist/orig with them; the tree's own Android.bp builds them as before, since the
# Android 15 one needs build features Android 13 does not have.
#
# A later `repo sync` puts 3.42.1 back: run this again.

set -eu

SQLITE_REMOTE=${SQLITE_REMOTE:-https://github.com/LineageOS/android_external_sqlite.git}
SQLITE_COMMIT=${SQLITE_COMMIT:-b6de9d89b233abcc04b69612820b5db063c62599}
SQLITE_VERSION=3.44.5

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tree=$(CDPATH= cd -- "$here/../../../.." && pwd)
[ -d "$tree/.repo" ] || { echo "error: $tree is not the top of a repo tree" >&2; exit 1; }
dist=$tree/external/sqlite/dist

if grep -q "define SQLITE_VERSION *\"$SQLITE_VERSION\"" "$dist/sqlite3.c"; then
    echo "    already $SQLITE_VERSION in external/sqlite"
    exit 0
fi

echo "==> fetching SQLite $SQLITE_VERSION from $SQLITE_REMOTE at $SQLITE_COMMIT"
tmp=$(mktemp -d)
git -C "$tmp" init -q
git -C "$tmp" remote add origin "$SQLITE_REMOTE"
git -C "$tmp" sparse-checkout set --no-cone /dist/sqlite-autoconf-3440300/
git -C "$tmp" fetch -q --depth=1 --filter=blob:none origin "$SQLITE_COMMIT"
git -C "$tmp" checkout -q FETCH_HEAD
src=$tmp/dist/sqlite-autoconf-3440300
grep -q "define SQLITE_VERSION *\"$SQLITE_VERSION\"" "$src/sqlite3.c" || {
    echo "error: $SQLITE_COMMIT does not carry $SQLITE_VERSION" >&2; rm -rf "${tmp:?}"; exit 1; }

for f in sqlite3.c sqlite3.h sqlite3ext.h shell.c; do
    cp "$src/$f" "$dist/$f"
    cp "$src/orig/$f" "$dist/orig/$f"
done
cp "$src/Android.patch" "$dist/Android.patch"
rm -rf "${tmp:?}"
echo "==> external/sqlite now has $SQLITE_VERSION"
