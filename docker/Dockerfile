# Minimal OpenClaw Gateway image for OrbStack/Docker
# هدف: run `openclaw gateway` inside container with a mounted config+state.

FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git jq tini \
  && rm -rf /var/lib/apt/lists/*

# Install OpenClaw CLI (includes gateway)
RUN npm install -g openclaw@2026.2.9 \
  && openclaw --version

# Default locations (can be overridden by env)
ENV OPENCLAW_STATE_DIR=/root/.openclaw
ENV OPENCLAW_CONFIG_PATH=/root/.openclaw/openclaw.json

# Gateway default port inside container
EXPOSE 18789

WORKDIR /work

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["sh","-lc","openclaw gateway"]
