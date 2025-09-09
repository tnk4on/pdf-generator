#!/bin/bash
# set -euo pipefail
#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: container <git-repo-url> [playbook]"
  exit 1
}

log() { echo "[info] $*"; }
err() { echo "[error] $*" >&2; }

if [ "$#" -lt 1 ]; then
  usage
fi

REPO_URL="$1"
PLAYBOOK="${2:-default-site.yml}"

WORKDIR=/work/repo
OUTDIR=/out

# derive repo name from git URL (strip .git and any path)
REPO_NAME=$(basename -s .git "${REPO_URL%%#*}")

ensure_no_source_mount() {
  # refuse when caller bind-mounts a host directory into $WORKDIR; only /out should be mounted
  if grep -q " $WORKDIR " /proc/mounts 2>/dev/null || mountpoint -q "$WORKDIR" 2>/dev/null; then
    err "Detected a mount at $WORKDIR. This container expects only /out to be mounted."
    err "Run the container without binding the source into /work/repo; mount only /out for outputs."
    exit 3
  fi
}

clone_repo() {
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"
  cd /work
  log "Cloning $REPO_URL ..."
  git clone --depth 1 "$REPO_URL" repo
  cd repo
}

detect_playbook() {
  if [ "$PLAYBOOK" = "default-site.yml" ] && [ ! -f "$PLAYBOOK" ]; then
    if [ -f site.yml ]; then PLAYBOOK=site.yml; fi
    if [ -f antora-playbook.yml ]; then PLAYBOOK=antora-playbook.yml; fi
  fi
  log "Using playbook: $PLAYBOOK"
}

build_site() {
  log "Running Antora site build"
  npx antora "$PLAYBOOK"
}

generate_pdf_with_antora() {
  mkdir -p "$OUTDIR"
  log "Running Antora PDF extension"
  npx antora --extension=@antora/pdf-extension --to-dir build/pdf "$PLAYBOOK"
}

debug_list_pdf() {
  echo "--- DEBUG: listing build/pdf ---"
  #!/bin/bash
  set -euo pipefail

  usage() {
    echo "Usage: container <git-repo-url> [playbook]"
    exit 1
  }

  log() { echo "[info] $*"; }
  err() { echo "[error] $*" >&2; }

  if [ "$#" -lt 1 ]; then
    usage
  fi

  REPO_URL="$1"
  PLAYBOOK="${2:-default-site.yml}"

  WORKDIR=/work/repo
  OUTDIR=/out

  # derive repo name from git URL (strip .git and any path)
  REPO_NAME=$(basename -s .git "${REPO_URL%%#*}")

  ensure_no_source_mount() {
    # refuse when caller bind-mounts a host directory into $WORKDIR; only /out should be mounted
    if grep -q " $WORKDIR " /proc/mounts 2>/dev/null || mountpoint -q "$WORKDIR" 2>/dev/null; then
      err "Detected a mount at $WORKDIR. This container expects only /out to be mounted."
      err "Run the container without binding the source into /work/repo; mount only /out for outputs."
      exit 3
    fi
  }

  clone_repo() {
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
    cd /work
    log "Cloning $REPO_URL ..."
    git clone --depth 1 "$REPO_URL" repo
    cd repo
  }

  detect_playbook() {
    if [ "$PLAYBOOK" = "default-site.yml" ] && [ ! -f "$PLAYBOOK" ]; then
      if [ -f site.yml ]; then PLAYBOOK=site.yml; fi
      if [ -f antora-playbook.yml ]; then PLAYBOOK=antora-playbook.yml; fi
    fi
    log "Using playbook: $PLAYBOOK"
  }

  build_site() {
    log "Running Antora site build"
    npx antora "$PLAYBOOK"
  }

  generate_pdf_with_antora() {
    mkdir -p "$OUTDIR"
    log "Running Antora PDF extension"
    npx antora --extension=@antora/pdf-extension --to-dir build/pdf "$PLAYBOOK"
  }

  debug_list_pdf() {
    echo "--- DEBUG: listing build/pdf ---"
    ls -la build/pdf || true
    echo "--- DEBUG: glob expansion ---"
    shopt -s globstar || true
    printf '%s\n' build/pdf/**/*.pdf || true
  }

  find_pdfs_in_build() {
    SRC_FILES=()
    if [ -d build/pdf ]; then
      while IFS= read -r -d '' f; do
        SRC_FILES+=("$f")
      done < <(find build/pdf -type f -name '*.pdf' -print0 2>/dev/null || true)
    fi
  }

  fallback_asciidoctor() {
    log "No PDFs produced by Antora PDF extension — attempting asciidoctor-pdf fallback..."
    mkdir -p build/pdf
    found_any=false
    while IFS= read -r -d '' adoc; do
      outbn=$(basename "$adoc" .adoc)
      outp="build/pdf/${outbn}.pdf"
      log "Converting $adoc -> $outp"
      if asciidoctor-pdf "$adoc" -o "$outp" 2>/dev/null; then
        found_any=true
      else
        err "asciidoctor-pdf failed for $adoc (continuing)"
      fi
    done < <(find content -type f -name '*.adoc' -print0 2>/dev/null || true)

    if [ "$found_any" = true ]; then
      log "Fallback conversion produced PDF(s) in build/pdf"
    else
      log "Fallback did not produce any PDFs"
    fi
  }

  copy_and_merge_pdfs() {
    # copy parts to OUTDIR and merge when appropriate
    mkdir -p "$OUTDIR"
    i=0
    for f in "${SRC_FILES[@]}"; do
      dest="$OUTDIR/${REPO_NAME}-part-$i.pdf"
      cp -v "$f" "$dest"
      i=$((i+1))
    done

    if command -v qpdf >/dev/null 2>&1 && [ ${#SRC_FILES[@]} -gt 1 ]; then
      log "Merging ${#SRC_FILES[@]} PDFs into $OUTDIR/${REPO_NAME}.pdf using qpdf..."
      qpdf --empty --pages "${SRC_FILES[@]}" -- "$OUTDIR/${REPO_NAME}.pdf"
      log "Merged PDF created: $OUTDIR/${REPO_NAME}.pdf"
    else
      if [ ${#SRC_FILES[@]} -ge 1 ]; then
        cp -v "${SRC_FILES[0]}" "$OUTDIR/${REPO_NAME}.pdf" || true
        log "Single PDF copied to $OUTDIR/${REPO_NAME}.pdf"
      else
        err "No PDFs to copy"
        exit 2
      fi
      if ! command -v qpdf >/dev/null 2>&1 && [ ${#SRC_FILES[@]} -gt 1 ]; then
        err "qpdf not found in image; multiple PDFs present but not merged. Install qpdf to enable merging."
      fi
    fi
  }

  cleanup_parts() {
    shopt -s nullglob || true
    parts=( "$OUTDIR/${REPO_NAME}-part-"*.pdf )
    if [ ${#parts[@]} -gt 0 ]; then
      log "Cleaning up ${#parts[@]} intermediate part files in $OUTDIR..."
      for p in "${parts[@]}"; do
        [ -f "$p" ] && rm -f "$p" && log "removed $p"
      done
    fi
    shopt -u nullglob || true
  }

  # ---- main ----
  ensure_no_source_mount
  clone_repo
  detect_playbook
  build_site
  generate_pdf_with_antora
  debug_list_pdf

  find_pdfs_in_build
  if [ ${#SRC_FILES[@]} -eq 0 ]; then
    fallback_asciidoctor
    find_pdfs_in_build
  fi

  if [ ${#SRC_FILES[@]} -gt 0 ]; then
    copy_and_merge_pdfs
    cleanup_parts
    log "Done. PDFs copied to $OUTDIR"
  else
    err "No PDFs found in build/pdf"
    exit 2
  fi

