#!/bin/bash
# Refresh Apple's iCloud Private Relay egress ranges (deduped IPv4 CIDR column only —
# RelayRanges.containsIPv4 only ever matches IPv4, so IPv6 lines are dead weight).
set -euo pipefail
cd "$(dirname "$0")/.."
curl -fsSL "https://mask-api.icloud.com/egress-ip-ranges.csv" \
  | cut -d, -f1 | sort -u | grep -v ':' \
  | sed 's/$/,,,/' > Sources/WhereAmIPCore/Resources/relay-ranges.csv
echo "relay-ranges.csv: $(wc -l < Sources/WhereAmIPCore/Resources/relay-ranges.csv) CIDRs"
