#!/bin/bash
# lat-busy.sh: three xe-lattest runs, each after a CPU snapshot of the Claude apps' busiest processes, into
# ~/lat-TAG.txt; prints the kernel->gpu lines. Start the load first (Claude 2 and 3 writing long answers).
#   bash tools/hybrid/lat-busy.sh TAG
set -uo pipefail
tag=${1:?usage: $0 TAG}
out=$HOME/lat-$tag.txt
if [ ! -x /tmp/xe-lattest ]; then
    clang -fobjc-arc -O2 -framework Metal -framework Foundation -o /tmp/xe-lattest "$(dirname "$0")/xe-lattest.m" \
        || { echo "could not build /tmp/xe-lattest"; exit 1; }
fi
: > "$out"
for r in 1 2 3; do
    {
        echo "== run $r $(date '+%H:%M:%S'), busiest Claude processes (%CPU):"
        ps axo pcpu,command | grep -E 'Claude( [23])?\.app/Contents/(Frameworks/Claude Helper|MacOS/Claude)' \
            | grep -v grep | sort -rn | head -6 | sed -E 's#/Users/[^ ]*/Applications/##; s#/Applications/##' | cut -c1-110
        /tmp/xe-lattest
    } >> "$out" 2>&1
done
grep -E '^== |kernel->gpu' "$out"
echo "full output: $out"
