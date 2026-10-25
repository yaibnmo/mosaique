#!/bin/bash
# Installe (ou met à jour) Mosaïque dans /Applications depuis la dernière version publiée sur GitHub.
#   curl -fsSL https://raw.githubusercontent.com/yaibnmo/mosaique/main/install.sh | bash
set -euo pipefail
REPO="yaibnmo/mosaique"
APP="/Applications/Mosaique.app"
BUNDLE_ID="io.github.yaibnmo.mosaique"

major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 15 ]; then echo "Mosaïque demande macOS 15 Sequoia ou plus récent." >&2; exit 1; fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "› Téléchargement de la dernière version…"
curl -fsSL "https://github.com/$REPO/releases/latest/download/Mosaique.zip" -o "$tmp/Mosaique.zip"
ditto -x -k "$tmp/Mosaique.zip" "$tmp"

if [ -d "$APP" ]; then
  echo "› Remplacement de la version installée…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  sleep 1; pkill -x Mosaique >/dev/null 2>&1 || true
  rm -rf "$APP"
  # Une nouvelle copie a une nouvelle signature : l'ancienne autorisation Accessibilité ne vaut plus.
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
fi
ditto "$tmp/Mosaique.app" "$APP"
# L'app n'est pas notarisée par Apple : on retire la quarantaine du téléchargement.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "› Ouverture de Mosaïque…"
open "$APP"
echo "✓ Installé. Suis la visite de bienvenue et autorise Mosaïque dans Réglages Système › Confidentialité et sécurité › Accessibilité."
