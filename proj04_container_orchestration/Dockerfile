# syntax=docker/dockerfile:1

# ---- Stage 1: builder — no external deps, kept for structure/future deps ----
FROM node:24-alpine AS builder

WORKDIR /build
COPY app/server.js .

# ---- Stage 2: runtime — minimal image, non-root user ----
FROM node:24-alpine AS runtime

# Non-root user/group to run the app (no shell, no home dir needed).
# The app has no dependencies, so package managers are removed from the
# runtime image: smaller attack surface and fewer CVEs reported by Trivy.
RUN addgroup -S app && adduser -S -G app -H app \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx \
              /usr/local/bin/corepack /usr/local/lib/node_modules/corepack \
              /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg

COPY --from=builder /build/server.js /app/server.js

WORKDIR /app
USER app

EXPOSE 8080

CMD ["node", "server.js"]
