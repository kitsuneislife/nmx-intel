#!/bin/bash
# install-skills.sh: installs the Claude Code skills used in this project, globally (~/.claude/skills), from pinned
# commits that were reviewed. Re-running updates them to these pins. No Node.js needed (prompt files only).
#   graphify  - knowledge graph of the docs (CLI via uv; installs uv if missing)
#   ponytail  - smallest complete change; reviews and audits     (prompt files only; plugin hooks not installed)
#   caveman   - terse replies, code/commands kept verbatim       (prompt files only; installer/proxy not installed)
set -euo pipefail
PONYTAIL_REV=6f1c2bf     # dietrichgebert/ponytail, 2026-10-16
CAVEMAN_REV=d262ab3      # JuliusBrussee/caveman, 2026-10-13
GRAPHIFY_VER=0.9.92      # graphifyy on PyPI (Graphify-Labs/graphify 86c57be)
SK=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$SK"

fetch() {   # fetch <owner/repo> <rev> <dir>
    git clone -q https://github.com/$1 "$TMP/$3"
    git -C "$TMP/$3" checkout -q "$2"
}

fetch dietrichgebert/ponytail "$PONYTAIL_REV" ponytail
for s in ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help; do
    mkdir -p "$SK/$s" && cp "$TMP/ponytail/skills/$s/SKILL.md" "$SK/$s/SKILL.md"
done

fetch JuliusBrussee/caveman "$CAVEMAN_REV" caveman
for s in caveman ultracave megacave caveman-help; do
    mkdir -p "$SK/$s" && cp "$TMP/caveman/skills/$s/SKILL.md" "$SK/$s/SKILL.md"
done

export PATH=$HOME/.local/bin:$PATH
command -v uv >/dev/null || { curl -LsSf https://astral.sh/uv/install.sh -o "$TMP/uv.sh"; sh "$TMP/uv.sh"; }
uv tool install --force "graphifyy==$GRAPHIFY_VER" >/dev/null
graphify install --platform claude >/dev/null

ls -d "$SK"/{graphify,ponytail*,caveman*,ultracave,megacave}
echo "graphify $(graphify --version 2>&1 | awk '{print $2}') at $(command -v graphify)"
