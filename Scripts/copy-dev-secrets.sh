#!/bin/sh
# Copy gitignored dev secrets into the app bundle. Never echo values.
set -e
JSON_SRC="$SRCROOT/Config/dev-endpoint.json"
ENV_SRC="$SRCROOT/.env"
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"

if [ -f "$JSON_SRC" ]; then
  cp "$JSON_SRC" "$DEST/dev-endpoint.json"
fi

if [ ! -f "$ENV_SRC" ] && [ -f "$JSON_SRC" ]; then
  /usr/bin/python3 - "$SRCROOT" <<'PY'
import json, pathlib, sys

root = pathlib.Path(sys.argv[1])
env_path = root / ".env"
json_path = root / "Config/dev-endpoint.json"
if env_path.exists():
    raise SystemExit(0)
try:
    data = json.loads(json_path.read_text())
except Exception:
    raise SystemExit(0)
key = str(data.get("apiKey") or "").strip()
if not key:
    raise SystemExit(0)
env_path.write_text("AXIOM_API_KEY=" + key + "\n")
PY
fi

if [ -f "$ENV_SRC" ]; then
  cp "$ENV_SRC" "$DEST/dev.env"
fi
