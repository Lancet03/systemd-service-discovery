#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SRC_DIR="${PROJECT_DIR}/src"
BUILD_DIR="${PROJECT_DIR}/build"
# Можно передавать тип сборки: ./build.sh Debug или ./build.sh Release
BUILD_TYPE="${1:-Debug}"


echo "[*] Configuring build (${BUILD_TYPE}) in ${BUILD_DIR} ..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"

echo "[*] Building..."
cmake --build .

echo "[+] Build finished. Binary is here: ${BUILD_DIR}/discovery"
