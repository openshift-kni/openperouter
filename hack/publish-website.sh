#!/bin/bash

set -euo pipefail

if [ -n "$(git status --porcelain)" ]; then
    echo "[ERROR] Working directory has uncommitted changes. Please commit or stash them first."
    exit 1
fi

echo "[INFO] Building website..."
make build-website

echo "[INFO] Creating temporary directory for repository clone..."
TEMP_DIR=$(mktemp -d)
ORIGINAL_DIR=$(pwd)
trap "rm -rf $TEMP_DIR" EXIT

DOCS_REPO_URL="https://github.com/openperouter/openperouter.github.io"

echo "[INFO] Cloning repository to temporary directory..."
git clone "$DOCS_REPO_URL" "$TEMP_DIR/repo"

cd "$TEMP_DIR/repo"
echo $(pwd)

echo "[INFO] Clearing existing content..."
git rm -rf . 2>/dev/null || true

echo "[INFO] Copying new website content..."
cp -r "$ORIGINAL_DIR/website/public/"* .

echo "[INFO] Adding all files to git..."
git add .

if [ -n "$(git status --porcelain)" ]; then
    echo "[INFO] Committing website changes..."
    SOURCE_COMMIT=$(cd "$ORIGINAL_DIR" && git rev-parse --short HEAD)
    SOURCE_BRANCH=$(cd "$ORIGINAL_DIR" && git rev-parse --abbrev-ref HEAD)
    git commit -m "Update website from $SOURCE_COMMIT on $SOURCE_BRANCH" || true
    
    echo "[INFO] Pushing to remote..."
    git push origin main
    
    echo "[INFO] Website published successfully!"
else
    echo "[WARNING] No changes to publish."
fi

echo "[INFO] Website publishing complete!" 
