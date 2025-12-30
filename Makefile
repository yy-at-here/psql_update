include .env
export

.PHONY: psql bob-generate seed-db

COMPOSE_CMD ?= docker compose

# 環境変数から DATABASE_URL を組み立て（デフォルト値はローカル開発用）
DATABASE_URL ?= postgres://$(POSTGRES_USER):$(PGPASSWORD)@$(POSTGRES_ENDPOINT)/$(POSTGRES_DB)?sslmode=disable

psql-local:
	$(COMPOSE_CMD) exec postgres psql -U postgres -d app_db

psql-ec2:
	psql -h $(POSTGRES_ENDPOINT) -U $(POSTGRES_USER) -d $(POSTGRES_DB)

bob-generate:
	DATABASE_URL=$(DATABASE_URL) bob generate

seed-db-local:
	cat initdb/seed_updates.sql | $(COMPOSE_CMD) exec -T postgres psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

seed-db-ec2:
	cat initdb/seed_updates.sql | psql -h $(POSTGRES_ENDPOINT) -U $(POSTGRES_USER) -d $(POSTGRES_DB)

get-aurora-password:
	@./scripts/get_aurora_password.sh

create-ec2-env:
	echo 'POSTGRES_USER="postgres"' > .env
	echo 'POSTGRES_DB="app_db"' >> .env
	echo 'POSTGRES_ENDPOINT="aurora.local:5432"' >> .env
