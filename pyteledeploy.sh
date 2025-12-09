#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "=== pyteledeploy.sh START ==="
echo "Date: $(date)"
echo "REPO_URL=${REPO_URL:-<not set>}"
echo "REPO_BRANCH=${REPO_BRANCH:-main}"
echo "START_CMD=${START_CMD:-<not set>}"

PY=python3
if ! command -v $PY >/dev/null 2>&1; then
  PY=python
fi
echo "Using python: $($PY --version 2>&1 || true)"

WORKDIR="$(pwd)/target_repo"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

if [ -z "${REPO_URL:-}" ]; then
  echo "ERROR: REPO_URL not set in env. Exiting."
  exit 1
fi

echo "Cloning target repo..."
git clone --depth 1 --branch "${REPO_BRANCH:-main}" "$REPO_URL" "$WORKDIR"

echo "Contents of target repo:"
ls -la "$WORKDIR"

cd "$WORKDIR"

if [ -f requirements.txt ]; then
  echo "---- requirements.txt ----"
  sed -n '1,200p' requirements.txt || true
  echo "---- end requirements ----"
  echo "Installing requirements..."
  $PY -m pip install --upgrade pip setuptools wheel || true
  $PY -m pip install -r requirements.txt || {
    echo "pip install failed; retrying with --no-cache-dir -v..."
    $PY -m pip install -r requirements.txt --no-cache-dir -v || true
  }
else
  echo "WARNING: requirements.txt not found at target repo root ($WORKDIR)."
fi

echo "Verifying python-dotenv import (clean heredoc) ..."
$PY - <<'PY_CHECK'
import importlib, sys
try:
    importlib.import_module('dotenv')
    print("dotenv import OK")
    sys.exit(0)
except Exception as e:
    print("dotenv import FAILED:", e)
    sys.exit(2)
PY_CHECK

# check exit status of that python check
if [ $? -ne 0 ]; then
  echo "python-dotenv not importable; forcing install python-dotenv..."
  $PY -m pip install python-dotenv || true
  echo "After forced install, verify import again:"
  $PY - <<'PY_CHECK2'
import importlib, sys
try:
    importlib.import_module('dotenv')
    print("dotenv import OK after forced install")
except Exception as e:
    print("Still failing to import dotenv:", e)
    sys.exit(3)
PY_CHECK2
fi

echo "=== Installed packages (top) ==="
$PY -m pip freeze | sed -n '1,120p' || true

if [ -z "${START_CMD:-}" ]; then
  echo "ERROR: START_CMD not set. Exiting."
  exit 1
fi

echo "Running START_CMD: $START_CMD"
# run from target repo root
bash -lc "$START_CMD"
echo "=== pyteledeploy.sh END ==="
