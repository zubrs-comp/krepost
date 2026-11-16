#!/usr/bin/env bash
# Скачивает исходные 3D-модели (CC0, Quaternius) из публичных зеркал на GitHub.
# Использование: ./fetch_models.sh <папка>
set -euo pipefail
OUT="${1:-models_src}"
mkdir -p "$OUT" && cd "$OUT"
# Quaternius — Ultimate Modular Men / Women (CC0)
if [ ! -d spm ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/HamaDler/sami-park-mayhem.git spm
  (cd spm && git sparse-checkout set assets/characters/crowd/men assets/characters/crowd/women)
fi
# Quaternius — Ultimate Monsters (CC0)
if [ ! -d ec ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/flawlesshappiness/EmotionCreatures.git ec
  (cd ec && git sparse-checkout set "Assets/Quaternius/Ultimate Monsters")
fi
echo "Модели в $(pwd)"
