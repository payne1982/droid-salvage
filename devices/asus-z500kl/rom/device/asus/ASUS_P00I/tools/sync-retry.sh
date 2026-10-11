#!/bin/sh
# Finish a `repo sync` that GitHub's rate limit keeps cutting short.
#
# Run it from the top of the tree, after `repo init`:
#
#   sync-retry.sh              up to 20 passes, 3 minutes apart
#   sync-retry.sh 40 300       40 passes, 5 minutes apart
#   sync-retry.sh --count      only say how many projects are still missing
#
# GitHub limits git downloads that carry no authentication. A tree of 700 projects
# runs into the limit a few minutes in, and repo reports the refusals as "git requires
# authentication", which is not what is wrong (rom/README.md has the real message).
# Asking again later works, a few more projects each time, so this asks again: two
# jobs at a time, with a pause between passes, until nothing is missing.
#
# repo's exit status is no guide, since it fails on the first refused project and says
# nothing about the rest. What is counted is what is on disk: a project that has not
# been downloaded is a git directory under .repo/projects with no refs in it.
set -eu

[ -d .repo ] || { echo "error: run this from the top of a repo tree" >&2; exit 1; }

missing() {
    n=0
    [ -d .repo/projects ] || { echo unknown; return; }
    for d in $(find .repo/projects -name '*.git'); do
        [ -n "$(git --git-dir="$d" for-each-ref --count=1 2>/dev/null)" ] || n=$((n + 1))
    done
    echo "$n"
}

if [ "${1:-}" = --count ]; then
    missing
    exit 0
fi

passes=${1:-20}
pause=${2:-180}
export GIT_TERMINAL_PROMPT=0

pass=1
while [ "$pass" -le "$passes" ]; do
    echo "pass $pass of $passes, $(date +%H:%M): missing before: $(missing)"
    repo sync -c -j2 --no-clone-bundle --force-sync --retry-fetches=2 >/dev/null 2>&1 && synced=yes || synced=no
    left=$(missing)
    if [ "$synced" = yes ] && [ "$left" = 0 ]; then
        echo "complete"
        exit 0
    fi
    echo "pass $pass done: missing after: $left"
    pass=$((pass + 1))
    [ "$pass" -le "$passes" ] && sleep "$pause"
done

echo "still missing $(missing) project(s) after $passes passes: authenticate instead (rom/README.md)" >&2
exit 1
