#!/usr/bin/env bash
# Sets the gallery of the mod portal page: uploads every image in tools/portal/images/ (in the order of the file names)
# and makes them the gallery, in that order. The id of an image is the SHA1 of its file: an image the portal already has
# is not uploaded again (the portal refuses it), and an image removed from the folder leaves the gallery.
# Needs an API key with "ModPortal: Edit Mods" in FACTORIO_TOKEN. https://wiki.factorio.com/Mod_images_API
#   gh workflow run portal.yml               run with the repository secret (.github/workflows/portal.yml)
#   FACTORIO_TOKEN=... tools/portal/images.sh
#   tools/portal/images.sh --dry-run         list the images without sending them
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
mod=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["name"])' "$repo/info.json")

shopt -s nullglob
images=("$here"/images/*.png "$here"/images/*.jpg)
IFS=$'\n' images=($(printf '%s\n' "${images[@]}" | sort))
unset IFS
if [ ${#images[@]} -eq 0 ]; then
  echo "no images in $here/images" >&2
  exit 1
fi

if [ "${1:-}" = "--dry-run" ]; then
  printf '%s\n' "${images[@]##*/}"
  exit 0
fi
if [ -z "${FACTORIO_TOKEN:-}" ]; then
  echo "error: FACTORIO_TOKEN is not set" >&2
  exit 1
fi

# prints the value of a field of a JSON response, or fails with its error
field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
response = json.loads(sys.argv[1])
if sys.argv[2] in response:
    print(response[sys.argv[2]])
else:
    print(f"error: {response.get('error')}: {response.get('message')}", file=sys.stderr)
    sys.exit(1)
PY
}

# the ids of the images the portal has for the mod
existing=$(curl -sS "https://mods.factorio.com/api/mods/$mod/full" | python3 -c '
import json, sys
print(" ".join(image["id"] for image in json.load(sys.stdin).get("images") or []))')

ids=()
for image in "${images[@]}"; do
  sha=$(shasum -a 1 "$image" | cut -d" " -f1)
  if [[ " $existing " == *" $sha "* ]]; then
    echo "on the portal already ${image##*/}: $sha"
    ids+=("$sha")
    continue
  fi
  response=$(curl -sS -X POST https://mods.factorio.com/api/v2/mods/images/add \
    -H "Authorization: Bearer $FACTORIO_TOKEN" -F "mod=$mod")
  upload_url=$(field "$response" upload_url)
  response=$(curl -sS -X POST "$upload_url" -F "image=@$image")
  id=$(field "$response" id)
  echo "uploaded ${image##*/}: $id"
  ids+=("$id")
done

list=$(IFS=,; echo "${ids[*]}")
response=$(curl -sS -X POST https://mods.factorio.com/api/v2/mods/images/edit \
  -H "Authorization: Bearer $FACTORIO_TOKEN" -F "mod=$mod" -F "images=$list")
field "$response" success >/dev/null
echo "gallery of https://mods.factorio.com/mod/$mod: ${#ids[@]} images"
