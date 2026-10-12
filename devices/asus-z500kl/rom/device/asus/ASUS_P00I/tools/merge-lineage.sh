#!/bin/sh
#
# Bring the LineageOS-UL forks in the tree up to LineageOS' lineage-20.0.
#
# Run from the device directory inside the tree, after `repo sync` and before
# apply-tree-patches.sh:
#   cd <tree>/device/asus/ASUS_P00I && ./tools/merge-lineage.sh
#
# LineageOS-UL is LineageOS with forks of the projects that have to change for a kernel
# without eBPF. The forks stopped on 4 April 2025. Everything UL does not fork still
# follows LineageOS, security patches included, and by now some of it uses framework
# code the forks never received: against the frameworks/base of April 2025,
# ContactsProvider, Settings, Telephony, MmsService, IntentResolver and Trebuchet do
# not compile.
#
# LineageOS-UL itself moved forward by merging LineageOS' branch into each fork; the
# last commit of a fork is such a merge. This does the next one. tools/lineage-merges.txt
# names the forks and, for each, the LineageOS commit to merge: a commit and not the
# branch, so that the result is the same on another day.
#
# The merge is a local commit on top of what `repo sync` checked out. A later
# `repo sync` puts the project back on the fork's own head: run this again.
#
# A merge that conflicts is left as it stopped, for whoever runs this to look at;
# `git merge --abort` in the project goes back.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tree=$(CDPATH= cd -- "$here/../../../.." && pwd)
[ -d "$tree/.repo" ] || { echo "error: $tree is not the top of a repo tree" >&2; exit 1; }

export GIT_TERMINAL_PROMPT=0

grep -v '^#' "$here/lineage-merges.txt" | while read -r path name commit since; do
    [ -n "$path" ] || continue
    cd "$tree/$path"

    if git merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
        echo "    already merged $path: $commit"
        continue
    fi
    if [ -n "$(git status --porcelain)" ]; then
        echo "error: $path has local changes; run this before apply-tree-patches.sh" >&2
        exit 1
    fi

    echo "==> $path: fetching"
    # `repo sync --depth=1` left one commit. Its parents are enough: one of them is the
    # LineageOS commit the fork merged last, which is where the two histories meet.
    git fetch -q --no-tags --depth=2 "https://github.com/LineageOS-UL/$name" lineage-20.0
    git fetch -q --no-tags --shallow-since="$since" "https://github.com/LineageOS/$name" lineage-20.0
    if ! git merge-base --is-ancestor "$commit" FETCH_HEAD; then
        echo "error: $commit is not in LineageOS' lineage-20.0 of $name" >&2
        exit 1
    fi
    if ! git merge-base HEAD "$commit" > /dev/null; then
        echo "error: $path: no common ancestor in the history fetched since $since" >&2
        exit 1
    fi

    echo "==> $path: merging $(git rev-list --count "HEAD..$commit") commits"
    if ! git -c user.name=merge-lineage -c user.email=merge-lineage@localhost \
            merge -q --no-ff -m "Merge LineageOS lineage-20.0 ($commit) into the LineageOS-UL fork" "$commit"; then
        echo "error: $path: the merge stopped on conflicts" >&2
        git status --short | grep -E '^(UU|AA|DU|UD|AU|UA|DD)' >&2 || true
        exit 1
    fi
    echo "    merged $path: $commit"
done
