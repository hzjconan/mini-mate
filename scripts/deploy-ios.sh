#!/usr/bin/env bash
set -euo pipefail

# One-click build, install, and launch MiniMate onto a paired physical iPhone.
# Zero LLM / token cost — invoke directly from terminal, zsh alias, or shortcut.
#
# Usage:
#   ./scripts/deploy-ios.sh [--device <UDID>] [--configuration Debug|Release] [--no-launch] [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT="${REPO_ROOT}/App/MiniMate.xcodeproj"
SCHEME="MiniMate"
CONFIGURATION="Debug"
DEVICE_ID="${MINIMATE_IOS_DEVICE:-}"
NO_LAUNCH=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: deploy-ios.sh [options]

Options:
  --device <UDID>            Target iPhone UDID (default: auto-detect paired available iPhone;
                             also respects MINIMATE_IOS_DEVICE env var)
  --configuration <cfg>      Build configuration: Debug (default) or Release
  --no-launch                Install app without launching it
  --dry-run                  Detect device and resolve build paths without building/installing
  -h, --help                 Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      [[ $# -ge 2 ]] || { echo "Error: --device requires a UDID" >&2; exit 2; }
      DEVICE_ID="$2"
      shift 2
      ;;
    --configuration)
      [[ $# -ge 2 ]] || { echo "Error: --configuration requires a value" >&2; exit 2; }
      CONFIGURATION="$2"
      shift 2
      ;;
    --no-launch)
      NO_LAUNCH=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

detect_device() {
  local tmp_json
  tmp_json="$(mktemp -t minimate-devices.XXXXXX.json)"
  trap 'rm -f "${tmp_json:-}"' RETURN

  xcrun devicectl list devices --json-output "${tmp_json}" >/dev/null
  python3 - "${tmp_json}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

candidates = []
for dev in data.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {})
    conn = dev.get("connectionProperties", {})
    props = dev.get("deviceProperties", {})
    if hw.get("platform") != "iOS" or hw.get("deviceType") != "iPhone":
        continue
    if conn.get("pairingState") != "paired":
        continue
    if conn.get("tunnelState") == "unavailable":
        continue
    udid = hw.get("udid")
    if not udid:
        continue
    # Prefer wired over wireless when multiple iPhones are reachable.
    rank = 0 if conn.get("transportType") == "wired" else 1
    candidates.append((rank, udid, props.get("name", "iPhone"), conn.get("transportType") or "unknown"))

if not candidates:
    sys.exit(1)

candidates.sort(key=lambda item: item[0])
_, udid, name, transport = candidates[0]
print(f"{udid}\t{name}\t{transport}")
PY
}

DEVICE_NAME="specified"
DEVICE_TRANSPORT="manual"
if [[ -z "${DEVICE_ID}" ]]; then
  echo "[1/4] 正在检测已配对的可用 iPhone..."
  if ! DETECTED="$(detect_device)"; then
    echo "错误：未找到可用的已配对 iPhone。请确认手机已解锁并连接至 Mac，或使用 --device <UDID> 指定。" >&2
    exit 1
  fi
  IFS=$'\t' read -r DEVICE_ID DEVICE_NAME DEVICE_TRANSPORT <<< "${DETECTED}"
  echo "      命中设备：${DEVICE_NAME} (${DEVICE_ID}, ${DEVICE_TRANSPORT})"
else
  echo "[1/4] 使用指定设备：${DEVICE_ID}"
fi

echo "[2/4] 正在解析构建产物路径与 Bundle ID (${CONFIGURATION})..."
BUILD_SETTINGS="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -destination "id=${DEVICE_ID}" -showBuildSettings)"
TARGET_BUILD_DIR="$(printf '%s\n' "${BUILD_SETTINGS}" | awk -F ' = ' '$1 ~ /^[[:space:]]*TARGET_BUILD_DIR$/ {print $2; exit}')"
FULL_PRODUCT_NAME="$(printf '%s\n' "${BUILD_SETTINGS}" | awk -F ' = ' '$1 ~ /^[[:space:]]*FULL_PRODUCT_NAME$/ {print $2; exit}')"
BUNDLE_ID="$(printf '%s\n' "${BUILD_SETTINGS}" | awk -F ' = ' '$1 ~ /^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER$/ {print $2; exit}')"

if [[ -z "${TARGET_BUILD_DIR}" || -z "${FULL_PRODUCT_NAME}" || -z "${BUNDLE_ID}" ]]; then
  echo "错误：无法从 xcodebuild -showBuildSettings 解析产物路径或 Bundle ID。" >&2
  exit 1
fi
APP_PATH="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
echo "      App 路径：${APP_PATH}"
echo "      Bundle ID：${BUNDLE_ID}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[dry-run] 检查通过，未执行构建与安装。"
  exit 0
fi

echo "[3/4] 正在签名编译 ${SCHEME} (${CONFIGURATION})..."
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "id=${DEVICE_ID}" \
  -allowProvisioningUpdates \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "错误：构建完成但未找到 ${APP_PATH}" >&2
  exit 1
fi

echo "[4/4] 正在安装到设备 ${DEVICE_NAME} (${DEVICE_ID})..."
xcrun devicectl device install app --device "${DEVICE_ID}" "${APP_PATH}"

if [[ "${NO_LAUNCH}" -eq 0 ]]; then
  echo "      正在启动 ${BUNDLE_ID}..."
  xcrun devicectl device process launch --device "${DEVICE_ID}" "${BUNDLE_ID}"
fi

echo "✅ 部署完成：${DEVICE_NAME} (${BUNDLE_ID})"
