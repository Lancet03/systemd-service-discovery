#!/usr/bin/env bash
set -e

# Сохраняем переменные DISCOVERY_/SERVICE_ в файл для systemd
env | grep -E '^(DISCOVERY_|SERVICE_)' > /etc/worker.env || true

exec /sbin/init
