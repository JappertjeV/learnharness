# LearnHarness as a web server (browser-only mode), plus the Claude Code CLI as model provider.
#
# Upstream ships an Electron app; it runs the server on 127.0.0.1 with a per-launch secret, so a
# phone can't reach it. This image runs the same standalone server behind Caddy + Authelia
# (LearnHarness has no login of its own).
#
# Pinned via LH_REF. Updating = bump the tag, rebuild, and update the iOS app with it
# (the app uses the internal API of this exact version).

ARG NODE_IMAGE=node:26-trixie-slim

FROM ${NODE_IMAGE} AS build
ARG LH_REF=v0.6.1
ARG LH_REPO=https://github.com/amosblomqvist/learnharness.git
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates python3 make g++ \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${LH_REF}" "${LH_REPO}" /src
WORKDIR /src
# The Next build needs plenty of memory; without a cap Node takes too little or too much.
ENV NODE_OPTIONS=--max-old-space-size=3072 NEXT_TELEMETRY_DISABLED=1
# Order from docs/development.md: plugins:setup before build; build-server.mjs copies public/,
# .next/static and core-plugins into the standalone folder.
RUN npm ci \
 && npm run plugins:setup \
 && npm run build \
 && node scripts/build-server.mjs

FROM ${NODE_IMAGE}
ARG CLAUDE_CODE_VERSION=2.1.325
# git: Claude Code uses it when present; tini: clean signals, no zombies from the CLI children
# LearnHarness starts per turn.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git tini \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && npm cache clean --force
# Fixed uid so the volumes on the host have a predictable owner (upload service uses it too).
RUN groupadd -g 1500 lh && useradd -u 1500 -g lh -m -d /home/lh -s /bin/bash lh
COPY --from=build --chown=lh:lh /src/.next/standalone /app
WORKDIR /app
USER lh
# HOSTNAME=0.0.0.0 is safe here: the port isn't published, only Caddy on the internal compose
# network can reach it. LH_ALLOWED_HOSTS comes from compose (the domain name).
ENV NODE_ENV=production \
    PORT=3000 \
    HOSTNAME=0.0.0.0 \
    LH_DATA_DIR=/data/data \
    LH_AUTH_FILE=/data/auth/auth.json \
    NEXT_TELEMETRY_DISABLED=1
EXPOSE 3000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "server.js"]
