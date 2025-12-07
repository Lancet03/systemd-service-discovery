#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SRC_DIR="${PROJECT_DIR}/src"
BUILD_DIR="${PROJECT_DIR}/build"
BUILD_TYPE="${1:-Release}"

echo "[*] Configure CMake (${BUILD_TYPE})..."
mkdir -p "${BUILD_DIR}"
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"

echo "[*] Build..."
cmake --build "${BUILD_DIR}" --config "${BUILD_TYPE}" -j"$(nproc)"

echo "[+] Binary: ${BUILD_DIR}/worker"
