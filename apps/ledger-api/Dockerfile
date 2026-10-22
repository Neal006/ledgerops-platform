# syntax=docker/dockerfile:1.7
# Build context is the repository root so the pnpm workspace lockfile is available.

ARG NODE_VERSION=22.22.1

FROM node:${NODE_VERSION}-bookworm-slim AS build
ENV PNPM_HOME=/pnpm PATH=/pnpm:$PATH CI=true
RUN corepack enable
WORKDIR /repo

# Fetch dependencies using only lockfile + manifests so this layer caches across source changes.
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json .npmrc ./
COPY apps/ledger-api/package.json apps/ledger-api/
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm fetch --frozen-lockfile

COPY tsconfig.base.json ./
COPY apps/ledger-api apps/ledger-api
RUN --mount=type=cache,id=pnpm,target=/pnpm/store \
    pnpm install --frozen-lockfile --offline --filter @ledgerops/ledger-api... \
 && pnpm --filter @ledgerops/ledger-api build \
 && pnpm --filter @ledgerops/ledger-api deploy --prod --legacy /out

# RDS presents certificates from its own CA; ship the bundle so TLS can be fully verified.
ADD --chmod=644 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /out/certs/rds-global-bundle.pem

# Distroless: no shell, no package manager, runs as uid 65532.
FROM gcr.io/distroless/nodejs22-debian12:nonroot AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    NODE_EXTRA_CA_CERTS=/app/certs/rds-global-bundle.pem \
    PORT=3000
COPY --from=build --chown=nonroot:nonroot /out/package.json ./
COPY --from=build --chown=nonroot:nonroot /out/node_modules ./node_modules
COPY --from=build --chown=nonroot:nonroot /out/dist ./dist
COPY --from=build --chown=nonroot:nonroot /out/migrations ./migrations
COPY --from=build --chown=nonroot:nonroot /out/certs ./certs

ARG GIT_SHA=unknown
LABEL org.opencontainers.image.source="https://github.com/Neal006/ledgerops-platform" \
      org.opencontainers.image.revision="${GIT_SHA}"
ENV GIT_SHA=${GIT_SHA}

EXPOSE 3000
USER nonroot
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/nodejs/bin/node", "-e", "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
# The same image runs migrations as a one-off task: command override ["dist/migrate.js"].
CMD ["dist/server.js"]
