#!/usr/bin/env bash
# Sets the mod portal page of the mod in info.json: title, summary, description (tools/portal/description.md),
# category, tags, license, homepage and source URL. semantic-release-factorio uploads releases but never sets these.
# Needs an API key with "ModPortal: Edit Mods" in FACTORIO_TOKEN, and the mod must already be on the portal
# (the first release creates it). https://wiki.factorio.com/Mod_details_API
#   gh workflow run portal.yml               run with the repository secret (.github/workflows/portal.yml)
#   FACTORIO_TOKEN=... tools/portal/details.sh
#   tools/portal/details.sh --dry-run        print the fields without sending them
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
info() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$repo/info.json" "$1"; }

mod=$(info name)
fields=(
  -F "mod=$mod"
  -F "title=$(info title)"
  -F "summary=Nine summonable bosses in three circles on Nexus. Craft a summon beacon, light it on Nexus and defend your base. Beating a circle opens the next one; beating all three opens the warp drive."
  -F "description=<$here/description.md"
  -F "category=content"
  -F "tags=combat"
  -F "tags=enemies"
  -F "tags=planets"
  -F "license=default_gnugplv3"
  -F "homepage=https://github.com/GreenTech-Solutions/nexus-bosses"
  -F "source_url=https://github.com/GreenTech-Solutions/nexus-bosses"
)

if [ "${1:-}" = "--dry-run" ]; then
  printf '%s\n' "${fields[@]}" | grep -v '^-F$'
  exit 0
fi
if [ -z "${FACTORIO_TOKEN:-}" ]; then
  echo "error: FACTORIO_TOKEN is not set" >&2
  exit 1
fi

response=$(curl -sS -X POST https://mods.factorio.com/api/v2/mods/edit_details \
  -H "Authorization: Bearer $FACTORIO_TOKEN" "${fields[@]}")
python3 - "$response" "$mod" <<'PY'
import json, sys
response = json.loads(sys.argv[1])
if response.get("success"):
    print(f"updated https://mods.factorio.com/mod/{sys.argv[2]}")
else:
    print(f"error: {response.get('error')}: {response.get('message')}", file=sys.stderr)
    sys.exit(1)
PY
