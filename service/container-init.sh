#!/usr/bin/env bash
set -e

env > /etc/worker.env || true

exec /sbin/init
