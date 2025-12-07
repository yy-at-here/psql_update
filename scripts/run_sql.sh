#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_sql.sh -f <sql_file> [-d <database_url>]

Execute a SQL file with psql and report the elapsed time.

Options:
  -f, --file    Path to the SQL file to execute (required)
  -d, --dsn     PostgreSQL connection string (defaults to postgres://postgres:postgres@localhost:15432/app_db?sslmode=disable)
  -h, --help    Show this help message
EOF
}

SQL_FILE=""
DATABASE_URL="postgres://postgres:postgres@localhost:15432/app_db?sslmode=disable"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      shift
      SQL_FILE="${1:-}"
      ;;
    --)
      shift
      break
      ;;
    *)
      if [[ -z "$SQL_FILE" ]]; then
        SQL_FILE="$1"
      else
        echo "Unknown argument: $1" >&2
        usage
        exit 1
      fi
      ;;
  esac
  shift || true
done

if [[ -z "$SQL_FILE" ]]; then
  echo "Error: SQL file must be specified with -f." >&2
  usage
  exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "Error: SQL file '$SQL_FILE' does not exist." >&2
  exit 1
fi

if [[ ! -r "$SQL_FILE" ]]; then
  echo "Error: SQL file '$SQL_FILE' is not readable." >&2
  exit 1
fi

START_TIME=$(python3 -c 'import time; print(time.time())')
psql --set ON_ERROR_STOP=1 "$DATABASE_URL" -f "$SQL_FILE" >/dev/null
END_TIME=$(python3 -c 'import time; print(time.time())')

python3 - "$START_TIME" "$END_TIME" <<'PY'
import sys
start, end = map(float, sys.argv[1:3])
print(f"elapsed_seconds={end - start:.6f}")
PY
