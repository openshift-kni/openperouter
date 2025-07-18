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

DOCS_REPO_OWNER="openperouter"
DOCS_REPO_NAME="openperouter.github.io"

if [ -n "${GITHUB_TOKEN:-}" ]; then
    DOCS_REPO_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${DOCS_REPO_OWNER}/${DOCS_REPO_NAME}.git"
else
    DOCS_REPO_URL="https://github.com/${DOCS_REPO_OWNER}/${DOCS_REPO_NAME}.git"
fi

echo "[INFO] Cloning repository to temporary directory..."
git clone "$DOCS_REPO_URL" "$TEMP_DIR/repo"

cd "$TEMP_DIR/repo"

if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "[INFO] Configuring git user for CI..."
    git config user.name "${GITHUB_ACTOR:-"github-actions[bot]"}"
    git config user.email "${GITHUB_ACTOR:-"github-actions[bot]"}@users.noreply.github.com"
fi

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
