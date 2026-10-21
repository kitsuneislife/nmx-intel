#!/bin/bash
# gputests.sh: Julio's headless Metal tests (xps tools/diagnostics), run on the Iris Xe during a hybrid boot.
#   bash tools/hybrid/gputests.sh build          compile them into ~/nmx-build/hybrid/xps/build/tests (GPU-only is fine)
#   bash gputests.sh run <dir> <out>             run them, 15 s limit each, appending to <out> with a sync per test
#                                                (efi.sh boot-once does this as the console user)
set -u
case "${1:-}" in
build)
    X=$HOME/nmx-build/hybrid/xps/tools/diagnostics; O=$HOME/nmx-build/hybrid/xps/build/tests
    mkdir -p "$O" || exit 1
    F="-framework Metal -framework IOSurface -framework CoreVideo -framework Foundation -framework AppKit -framework QuartzCore"
    for t in miptest f16test atlastest icontest carender; do
        clang -fobjc-arc -w -o "$O/xe-$t" "$X/xe-$t.m" $F || { echo "build failed: xe-$t"; exit 1; }
    done
    clang -fobjc-arc -w -o "$O/xe-tex-tests" "$X/gpu-tests/xe-tex-tests.m" $F || { echo "build failed: xe-tex-tests"; exit 1; }
    clang -fobjc-arc -w -o "$O/xe-a8test" "$(dirname "$0")/xe-a8test.m" $F || { echo "build failed: xe-a8test"; exit 1; }
    cp "$0" "$O/gputests.sh" && ls "$O"
    ;;
run)
    D=$2; OUT=$3
    echo "== $(date '+%F %T') $(id -un) $(sysctl -n kern.osversion)" >> "$OUT"
    # the safe copy/upload tests first; xe-tex-tests last (Julio: wu_ios hung the GPU, so it is left out)
    for t in xe-a8test xe-miptest xe-f16test xe-atlastest xe-icontest xe-carender "xe-tex-tests bufu" "xe-tex-tests r8" \
             "xe-tex-tests rgba8" "xe-tex-tests amostra" "xe-tex-tests wf_plano" "xe-tex-tests wu4_tex" \
             "xe-tex-tests wu_tex" "xe-tex-tests wu_plano"; do
        echo "--- $t" >> "$OUT"; sync
        $D/$t >> "$OUT" 2>&1 & p=$!; n=0
        while kill -0 $p 2>/dev/null && [ $n -lt 150 ]; do sleep 0.1; n=$((n + 1)); done
        kill -0 $p 2>/dev/null && { kill -9 $p; echo "HUNG (>15 s): stopping" >> "$OUT"; sync; exit 2; }
        sync
    done
    echo "== end" >> "$OUT"; sync
    ;;
*) echo "usage: bash $0 build | run <dir> <out>"; exit 1 ;;
esac
