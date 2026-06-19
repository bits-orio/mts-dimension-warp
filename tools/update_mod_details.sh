#!/usr/bin/env bash
# Sync the mod portal's editable details (DESCRIPTION + source_url) from the repo
# so the portal page never drifts from README.md. Run on each release.
#
# This is a PARTIAL update (only the fields we send change), so category / license
# / tags / title / summary set on the portal are left untouched.
#
# Usage: tools/update_mod_details.sh <mod_name> <readme_path> [source_url]
# Env:   FACTORIO_API_KEY (required) — token with "ModPortal: Edit Mods" scope
#        (separate from the "Upload Mods" scope used by upload_mod_portal.sh)
#
# API: https://wiki.factorio.com/Mod_details_API  (POST /api/v2/mods/edit_details)
set -euo pipefail

MOD="${1:?mod name required}"
README="${2:?readme path required}"
SOURCE_URL="${3:-}"

: "${FACTORIO_API_KEY:?FACTORIO_API_KEY env var not set}"
[[ -f "$README" ]] || { echo "readme not found: $README" >&2; exit 1; }

# Read the field values from files / args. `description=<file` makes curl read the
# field VALUE from the file, so markdown with quotes/newlines needs no escaping.
ARGS=( -F "mod=${MOD}" -F "description=<${README}" )
[[ -n "$SOURCE_URL" ]] && ARGS+=( -F "source_url=${SOURCE_URL}" )

echo "::group::edit_details (${MOD}) — sync description from ${README}"
RESP=$(curl -sS -w $'\nHTTP_CODE:%{http_code}' \
    -H "Authorization: Bearer ${FACTORIO_API_KEY}" \
    "${ARGS[@]}" \
    "https://mods.factorio.com/api/v2/mods/edit_details")

HTTP=$(echo "$RESP" | tail -n1 | cut -d: -f2)
BODY=$(echo "$RESP" | sed '$d')
echo "edit_details HTTP ${HTTP}"
echo "$BODY"

if [[ "$HTTP" -lt 200 ]] || [[ "$HTTP" -ge 300 ]]; then
    echo "edit_details failed — a 403 usually means the API key lacks the 'ModPortal: Edit Mods' scope" >&2
    exit 1
fi

echo "synced mod portal description for ${MOD}"
echo "::endgroup::"
