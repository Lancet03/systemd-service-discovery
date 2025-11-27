#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"

# Можно передавать тип сборки: ./build.sh Debug или ./build.sh Release
BUILD_TYPE="${1:-Debug}"

echo "[*] Configuring build (${BUILD_TYPE}) in ${BUILD_DIR} ..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" "${PROJECT_DIR}"

echo "[*] Building..."
cmake --build .

echo "[+] Build finished. Binary is here: ${BUILD_DIR}/discovery"
