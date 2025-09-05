#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: container <git-repo-url> [playbook]"
  exit 1
fi

REPO_URL="$1"
PLAYBOOK="${2:-default-site.yml}"

WORKDIR=/work/repo
OUTDIR=/out

# derive repo name from git URL (strip .git and any fragment)
REPO_NAME=$(basename -s .git "${REPO_URL%%#*}")

# clone repo (shallow)
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd /work

echo "Cloning $REPO_URL ..."
git clone --depth 1 "$REPO_URL" repo
cd repo

# If playbook path provided, use it; otherwise try to find a playbook
if [ "$PLAYBOOK" = "default-site.yml" ] && [ ! -f "$PLAYBOOK" ]; then
  if [ -f site.yml ]; then PLAYBOOK=site.yml; fi
  if [ -f antora-playbook.yml ]; then PLAYBOOK=antora-playbook.yml; fi
fi

echo "Using playbook: $PLAYBOOK"

# Build site and PDF
npx antora "$PLAYBOOK"

# generate PDF
mkdir -p "$OUTDIR"
# default Antora pdf extension writes into build/pdf
npx antora --extension=@antora/pdf-extension --to-dir build/pdf "$PLAYBOOK"

# debug: show build/pdf contents
echo "--- DEBUG: listing build/pdf ---"
ls -la build/pdf || true
echo "--- DEBUG: glob expansion ---"
shopt -s globstar || true
printf '%s\n' build/pdf/**/*.pdf || true

# copy PDFs to mounted out dir
shopt -s globstar || true
# use ls to detect files (works reliably in non-interactive shells)
PDFS=$(ls build/pdf/**/*.pdf 2>/dev/null || true)
if [ -n "$PDFS" ]; then
  i=0
  for f in $PDFS; do
    # if multiple PDFs exist, append index: repo.pdf, repo-1.pdf, repo-2.pdf...
    if [ $i -eq 0 ]; then
      dest="$OUTDIR/${REPO_NAME}.pdf"
    else
      dest="$OUTDIR/${REPO_NAME}-$i.pdf"
    fi
    cp -v "$f" "$dest"
    i=$((i+1))
  done
else
  echo "No PDFs found in build/pdf"
  exit 2
fi

echo "Done. PDFs copied to $OUTDIR"
