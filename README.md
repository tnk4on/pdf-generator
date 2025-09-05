# pdf-generator

A small container image that builds Antora sites and produces PDF output using the `@antora/pdf-extension` (which requires the Ruby `asciidoctor-pdf` gem).

This repository contains:

- `Containerfile` - builds an image with Node.js, Ruby, Antora, and the Antora PDF extension preinstalled.
- `entrypoint.sh` - container entrypoint: clone a git repository, run Antora to build HTML and PDF, and copy resulting PDF(s) to `/out`.

## Quick usage

Build locally and run (from the `pdf-generator/` directory):

```bash
podman build -t pdf-generator:latest .
mkdir -p out
podman run --rm -v "$PWD/out":/out pdf-generator:latest https://github.com/rhpds/showroom-lb1136-rhel-10-hol
# output will be in ./out/<repo-name>.pdf
```

Use remote image (example image pushed to Quay):

```bash
podman pull quay.io/tnk4on/pdf-generator:latest
podman run --rm -v "$PWD/out":/out quay.io/tnk4on/pdf-generator:latest https://github.com/rhpds/showroom-lb1136-rhel-10-hol
```

## Notes

- The Antora PDF extension requires Ruby's `asciidoctor-pdf`. The image installs the gem at build time.
- The script derives the output filename from the repository name in the provided git URL (for example `https://github.com/foo/bar.git` -> `bar.pdf`). If multiple PDFs are produced, subsequent files get `-1`, `-2` suffixes.
- Antora may emit warnings about missing attributes; these are content warnings and do not usually prevent PDF creation.

## License

See `LICENSE` for the full license text.
