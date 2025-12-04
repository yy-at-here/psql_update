.PHONY: psql bob-generate seed-db

COMPOSE_CMD ?= docker compose
DATABASE_URL ?= postgres://postgres:postgres@localhost:15432/app_db?sslmode=disable

psql:
	$(COMPOSE_CMD) exec postgres psql -U postgres -d app_db

bob-generate:
	DATABASE_URL=$(DATABASE_URL) bob generate

seed-db:
	cat initdb/seed_updates.sql | $(COMPOSE_CMD) exec -T postgres psql -U postgres -d app_db