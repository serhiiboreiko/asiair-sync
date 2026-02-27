#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${ROOT_DIR}/assets"
ICONSET_DIR="${ASSETS_DIR}/AppIcon.iconset"
SOURCE_PNG="${ASSETS_DIR}/AppIcon-1024.png"
ICNS_PATH="${ASSETS_DIR}/ASIAIRSync.icns"
SOURCE_INPUT="${ICON_SOURCE_PATH:-}"

mkdir -p "${ASSETS_DIR}"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

if [[ -n "${SOURCE_INPUT}" ]]; then
  SOURCE_FILE=""

  if [[ -d "${SOURCE_INPUT}" && "${SOURCE_INPUT}" == *.icon ]]; then
    while IFS= read -r file; do
      SOURCE_FILE="${file}"
      break
    done < <(find "${SOURCE_INPUT}/Assets" -maxdepth 1 -type f \( -name "*.png" -o -name "*.PNG" \) | sort)

    if [[ -z "${SOURCE_FILE}" ]]; then
      echo "No PNG file found in ${SOURCE_INPUT}/Assets" >&2
      exit 1
    fi
  elif [[ -f "${SOURCE_INPUT}" ]]; then
    SOURCE_FILE="${SOURCE_INPUT}"
  else
    echo "ICON_SOURCE_PATH must be a PNG file or .icon directory: ${SOURCE_INPUT}" >&2
    exit 1
  fi

  # Re-encode to a normalized 1024x1024 PNG; this avoids iconutil failures with some exported PNG metadata.
  swift "${ROOT_DIR}/scripts/normalize_icon_source.swift" "${SOURCE_FILE}" "${SOURCE_PNG}"
  echo "Using icon source: ${SOURCE_FILE}"
else
  swift "${ROOT_DIR}/scripts/generate_icon.swift" "${SOURCE_PNG}"
fi

for size in 16 32 128 256 512; do
  sips -z "${size}" "${size}" "${SOURCE_PNG}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
  size2x=$((size * 2))
  sips -z "${size2x}" "${size2x}" "${SOURCE_PNG}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"

echo "Generated icns: ${ICNS_PATH}"
