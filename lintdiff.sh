#!/bin/bash
# Checks if new lint messages have appeared

FETCH_ORIGIN=origin
REF_BRANCH=origin/develop
CURRENT_BRANCH=$(git symbolic-ref --short -q HEAD)

REF_OUT=/tmp/ref-lint.out
CURRENT_OUT=/tmp/current-lint.out
FETCH=true

usage() {
    echo "Usage: $0 [-b branch] [-o] [-f origin] command"
    echo "    -h                show this help message"
    echo "    -b branch         use branch \`branch\` for comparison. Default: origin/develop"
    echo "    -o                offline mode, do not fetch origin"
    echo "    -f origin         fetch the changes from origin if in online mode. Default: origin"
    exit 1
}

check_errcode() {
    # Exitcodes >= 126 have special meaning:
    # http://www.tldp.org/LDP/abs/html/exitcodes.html
    if [ "$1" -ge 126 ]; then
        echo "Fatal: command exited with code: $1. Aborting!"
        exit 1
    fi
}

if [ $# -eq 0 ]; then
    usage
fi

# Check if diff supports colored output
# Ubuntu Trusty has an ancient version of diffutils, 3.3,
# which doesn't handle that yet
if diff --color /dev/null /dev/null &>/dev/null; then
    DIFF="diff --color"
elif which colordiff &>/dev/null; then
    DIFF=colordiff
else
    DIFF=diff
fi

while getopts "b:of:h" opt; do
    case $opt in
        b)
            REF_BRANCH=$OPTARG
            ;;
        o)
            FETCH=false
            ;;
        f)
            FETCH_ORIGIN=$OPTARG
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND - 1))

# get new changes from develop, GitHub doesn't integrate them on its own
if $FETCH; then
    echo "Fetching new changes from develop..."
    git fetch "$FETCH_ORIGIN" || exit 1
fi

cleanup_artifacts() {
    git reset --hard HEAD
    git checkout "$CURRENT_BRANCH" || exit 1
}

# we checkout the reference branch first in case there are
# uncommitted changes to be overwritten by the merge
git checkout "$REF_BRANCH" || exit 1
trap cleanup_artifacts EXIT
commit=$(git rev-parse HEAD)
# We need to take files responsible for the linting configuration from
# the new commit.
git checkout "$CURRENT_BRANCH" .pylintrc setup.cfg
echo "Checking branch $REF_BRANCH, commit: $commit..."
echo $@
$@ >$REF_OUT
check_errcode $?

# Now take back the checked out config, go back to the new branch
git reset --hard HEAD
git checkout "$CURRENT_BRANCH" || exit 1
# The trap is no longer needed
trap - EXIT
commit=$(git rev-parse HEAD)
echo "Checking branch $CURRENT_BRANCH, commit: $commit..."
echo $@
$@ >$CURRENT_OUT
check_errcode $?

diff=$(diff --old-line-format="" --unchanged-line-format="" -w <(sort $REF_OUT) <(sort $CURRENT_OUT))
# There's always a newline, so -gt 1
if [ -n "$diff" ]; then
    echo "New findings! The error diff is:"
    $DIFF --unified $REF_OUT $CURRENT_OUT
    exit 1
else
    echo "Check OK, no new findings..."
fi
