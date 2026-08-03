#!/bin/bash

set -e

VPS="agrodata-codex"
LOCAL="$(dirname "$0")/backend/"
REMOTE="/srv/agrodata/backend"

echo "→ Sincronizando backend al VPS..."
rsync -avz --delete \
  --exclude='.dart_tool/' \
  --exclude='.DS_Store' \
  "$LOCAL" "$VPS:$REMOTE"

echo "→ Instalando dependencias y reiniciando servicio..."
ssh "$VPS" "cd $REMOTE && dart pub get && sudo systemctl restart agrodata-backend.service"

echo "✓ Deploy completado."
