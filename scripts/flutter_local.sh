#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_binary="${VETDOSIS_FLUTTER_BIN:-flutter}"
if [ ! -f supabase/config.local.json ]; then
  echo 'Falta supabase/config.local.json; copia config.example.json y configura URL/clave publicable.' >&2
  exit 1
fi
if [ "$#" -eq 0 ]; then
  echo 'Uso: scripts/flutter_local.sh run -d chrome | scripts/flutter_local.sh build web' >&2
  exit 1
fi
exec "$flutter_binary" "$@" --dart-define-from-file=supabase/config.local.json
