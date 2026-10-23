SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
ENV ?= staging

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

## ---- Local development ----
.PHONY: install up down seed recon logs
install: ## Install Node and Python dependencies
	pnpm install --frozen-lockfile
	cd apps/recon-worker && uv sync

up: ## Start the local stack (Postgres, migrations, API, observability)
	docker compose up -d --build

down: ## Stop the local stack and delete volumes
	docker compose down -v

seed: ## Seed the local ledger with sample data
	./scripts/seed-local.sh

recon: ## Run one reconciliation pass locally
	docker compose --profile jobs run --rm recon-worker

logs: ## Tail API logs
	docker compose logs -f ledger-api

## ---- Quality gates (same as CI) ----
.PHONY: test lint
test: ## Run all tests
	pnpm turbo run test
	cd apps/recon-worker && uv run pytest -q

lint: ## Lint and typecheck everything
	pnpm turbo run lint typecheck
	cd apps/recon-worker && uv run ruff check . && uv run ruff format --check .
