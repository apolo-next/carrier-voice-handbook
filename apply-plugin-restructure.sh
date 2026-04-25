#!/usr/bin/env bash
# ============================================================
# apply-plugin-restructure.sh
#
# Applies the validated plugin restructure to your repo:
#
#   BEFORE (current):
#     skill/voip-engineering/
#     ├── .claude-plugin/plugin.json
#     ├── SKILL.md
#     ├── references/
#     ├── assets/
#     └── scripts/
#
#   AFTER (Claude Code v2.1+ convention):
#     skill/voip-engineering/
#     ├── .claude-plugin/plugin.json
#     └── skills/
#         └── voip-engineering/
#             ├── SKILL.md
#             ├── references/
#             ├── assets/
#             └── scripts/
#
# Verified working with Claude Code v2.1.109 — tested via
# --plugin-dir before applying to the public repo.
#
# Run from the root of your carrier-voice-handbook clone.
# ============================================================

set -euo pipefail

# Sanity checks
if [[ ! -d ".git" ]]; then
    echo "ERROR: run this from the root of carrier-voice-handbook (no .git/ found)"
    exit 1
fi

if [[ ! -f "skill/voip-engineering/SKILL.md" ]]; then
    echo "ERROR: skill/voip-engineering/SKILL.md not found at expected location"
    echo "Either you're in the wrong directory, or the restructure already happened."
    exit 1
fi

if [[ -d "skill/voip-engineering/skills" ]]; then
    echo "ERROR: skill/voip-engineering/skills/ already exists"
    echo "The restructure may have already been applied. Aborting."
    exit 1
fi

# Verify clean working tree
if ! git diff-index --quiet HEAD --; then
    echo "WARNING: you have uncommitted changes in the repo."
    echo "Commit or stash them first to keep this restructure as a clean atomic change."
    echo
    read -p "Continue anyway? (yes/no): " confirm
    [[ "$confirm" == "yes" ]] || exit 1
fi

echo "==> Working in: $(pwd)"
echo

cd skill/voip-engineering

echo "==> Step 1: creating skills/voip-engineering/ subdirectory"
mkdir -p skills/voip-engineering

echo "==> Step 2: moving content with git mv (preserves history)"
git mv SKILL.md   skills/voip-engineering/SKILL.md
git mv references skills/voip-engineering/references
git mv assets     skills/voip-engineering/assets
git mv scripts    skills/voip-engineering/scripts

echo "==> Step 3: updating .claude-plugin/plugin.json (bump version, no path changes needed)"
cat > .claude-plugin/plugin.json <<'JSON'
{
  "name": "voip-engineering",
  "version": "1.0.1",
  "description": "Production-tested expertise for open-source carrier-class voice infrastructure with Kamailio, FreeSWITCH, RTPEngine, and Asterisk. Distilled from 20 years in LATAM telecom networks.",
  "author": {
    "name": "Jesús Bazán",
    "url": "https://github.com/apolo-next"
  },
  "homepage": "https://github.com/apolo-next/carrier-voice-handbook",
  "repository": "https://github.com/apolo-next/carrier-voice-handbook",
  "license": "Apache-2.0"
}
JSON

cd - >/dev/null

echo "==> Step 4: bump marketplace.json version to 1.0.2"
# We bump version so users who already added the marketplace get a refresh prompt
python3 - <<'PY'
import json
path = '.claude-plugin/marketplace.json'
with open(path) as f:
    data = json.load(f)
data['metadata']['version'] = '1.0.2'
data['plugins'][0]['version'] = '1.0.2'
with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
print(f"  Updated {path} to version 1.0.2")
PY

echo
echo "============================================================"
echo "  Restructure complete."
echo "============================================================"
echo
echo "Inspect changes with:"
echo "    git status"
echo "    git diff --stat"
echo "    find skill/voip-engineering -maxdepth 4 -type f -not -path '*/.git/*' | sort"
echo
echo "If everything looks right, commit and push:"
cat <<'COMMIT'

    git add -A
    git commit -m "fix(plugin): restructure to skills/<name>/SKILL.md convention

Claude Code v2.1+ requires plugins to follow the layout:
  plugin-root/
  ├── .claude-plugin/plugin.json
  └── skills/
      └── <skill-name>/
          └── SKILL.md

Previously SKILL.md was directly under skill/voip-engineering/,
which caused /plugin marketplace info to return empty and
/plugin install to fail with 'plugin not found'.

Verified working with Claude Code v2.1.109 via --plugin-dir
before applying to the public repo.

Bumped versions to 1.0.2 to trigger marketplace refresh for
existing users."

    git push origin main
COMMIT
echo