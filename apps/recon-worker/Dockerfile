# syntax=docker/dockerfile:1.7
FROM ghcr.io/astral-sh/uv:0.9.5 AS uv

FROM python:3.13-slim-bookworm AS build
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PROJECT_ENVIRONMENT=/venv
WORKDIR /src
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev --no-install-project
COPY recon recon
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev

FROM python:3.13-slim-bookworm AS runtime
RUN useradd --system --uid 10001 --no-create-home recon
COPY --from=build /venv /venv
COPY --from=build /src/recon /app/recon
ADD --chmod=644 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /app/certs/rds-global-bundle.pem
ENV PATH=/venv/bin:$PATH PYTHONUNBUFFERED=1 PYTHONPATH=/app \
    PGSSLROOTCERT=/app/certs/rds-global-bundle.pem
WORKDIR /app
USER recon
ENTRYPOINT ["python", "-m", "recon.main"]
