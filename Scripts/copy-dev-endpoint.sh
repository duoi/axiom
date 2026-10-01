#!/bin/sh
# Copy the gitignored dev endpoint into a Debug app. Never print the key or host.
set -e
if [ "$CONFIGURATION" != "Debug" ]; then
  exit 0
fi
JSON_SRC="$SRCROOT/Config/dev-endpoint.json"
if [ ! -f "$JSON_SRC" ]; then
  exit 0
fi
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$DEST"
cp "$JSON_SRC" "$DEST/dev-endpoint.json"

PLIST="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
if [ ! -f "$PLIST" ]; then
  exit 0
fi
/usr/bin/python3 - "$PLIST" "$JSON_SRC" <<'PY'
import json, plistlib, sys
from urllib.parse import urlparse

plist_path, json_path = sys.argv[1], sys.argv[2]
try:
    data = json.loads(open(json_path, encoding="utf-8").read())
except Exception:
    raise SystemExit(0)
url = urlparse(str(data.get("completionsURL") or ""))
host = (url.hostname or "").strip().lower()
if url.scheme != "http" or host in {"", "localhost", "127.0.0.1", "::1"}:
    raise SystemExit(0)
with open(plist_path, "rb") as handle:
    plist = plistlib.load(handle)
ats = plist.setdefault("NSAppTransportSecurity", {})
domains = ats.setdefault("NSExceptionDomains", {})
domains[host] = {
    "NSExceptionAllowsInsecureHTTPLoads": True,
    "NSIncludesSubdomains": False,
}
with open(plist_path, "wb") as handle:
    plistlib.dump(plist, handle)
PY
