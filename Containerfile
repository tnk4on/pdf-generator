# Containerfile for PDF generator (Antora + Asciidoctor PDF)
# Builds an image that accepts a git repo URL as first arg and writes PDFs to /out
FROM ubuntu:22.04

LABEL maintainer="Shion Tanaka / X(@tnk4on)"

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/bin:/usr/local/lib/node_modules/.bin:/usr/bin:/bin

# Install build dependencies, Node.js 22, Ruby and native PDF tools (qpdf, ghostscript)
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates gnupg build-essential git \
  && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs ruby-full ruby-dev qpdf ghostscript \
  && gem install bundler asciidoctor-pdf \
  && npm install -g antora @antora/pdf-extension \
  && rm -rf /var/lib/apt/lists/*

# Create workspace and output directory
WORKDIR /work
RUN mkdir -p /work/out

# Copy entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--help"]
