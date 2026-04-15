#!/bin/bash

set -e

VPS="root@72.60.57.85"
LOCAL="$(dirname "$0")/backend/"
REMOTE="/root/backend"

echo "→ Sincronizando backend al VPS..."
rsync -avz --delete \
  --exclude='.dart_tool/' \
  --exclude='.DS_Store' \
  "$LOCAL" "$VPS:$REMOTE"

echo "→ Instalando dependencias y reiniciando servicio..."
ssh "$VPS" "cd $REMOTE && dart pub get && systemctl restart agrodata-backend.service"

echo "✓ Deploy completado."
