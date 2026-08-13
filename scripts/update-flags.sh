#!/bin/bash
# Download menu-bar-size PNG flags from flagcdn.com (public domain per flagpedia.net/about).
# w40 ≈ 40px wide → crisp at 21pt in a Retina menu bar.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="Sources/WhereAmIPUI/Resources/flags"
mkdir -p "$DEST"
codes=$(curl -fsSL "https://flagcdn.com/en/codes.json" | /usr/bin/python3 -c \
  "import json,sys; print('\n'.join(k for k in json.load(sys.stdin) if len(k)==2))")
count=0
for code in $codes; do
  curl -fsSL "https://flagcdn.com/w40/${code}.png" -o "$DEST/${code}.png" && count=$((count+1)) || echo "skip $code"
  sleep 0.05
done
echo "Downloaded $count flags to $DEST"
