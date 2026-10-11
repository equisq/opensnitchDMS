#!/usr/bin/env bash
# Builds the OpenSnitch UI backend (bin/opensnitch-dmsd).
#
# CGO is disabled; the executable is still built for the current OS/architecture.
set -euo pipefail

cd "$(dirname "$0")/backend"
mkdir -p ../bin
flags=()
[ -d vendor ] && flags+=(-mod=vendor)
echo "building the OpenSnitch backend..."
CGO_ENABLED=0 go build "${flags[@]}" -buildvcs=false -trimpath -ldflags='-s -w' -o ../bin/opensnitch-dmsd .
echo "built: $(cd .. && pwd)/bin/opensnitch-dmsd"
echo ""
echo "Next steps:"
echo "1. Make sure the original OpenSnitch UI is not active"
echo "2. In Settings → Plugins, enable OpenSnitch."
echo "3. Then in Settings → Bar → Widgets, click on Add widget, then select OpenSnitch."
echo "4. Enjoy!"
