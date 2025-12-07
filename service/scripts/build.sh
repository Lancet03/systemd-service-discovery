#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
BUILD_TYPE="${1:-Release}"

echo "[*] Configure CMake (${BUILD_TYPE})..."
mkdir -p "${BUILD_DIR}"
cmake -S "${PROJECT_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"

echo "[*] Build..."
cmake --build "${BUILD_DIR}" --config "${BUILD_TYPE}" -j"$(nproc)"

echo "[+] Binary: ${BUILD_DIR}/worker"
