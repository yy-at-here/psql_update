-- Seed data for PostgreSQL update benchmark scenarios
-- This script is idempotent and can be rerun to reset the benchmark dataset.

CREATE TABLE IF NOT EXISTS benchmark_accounts (
    id BIGSERIAL PRIMARY KEY,
    status TEXT NOT NULL,
    balance NUMERIC(12,2) NOT NULL DEFAULT 0,
    last_accessed TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    version INTEGER NOT NULL DEFAULT 0,
    note TEXT NOT NULL DEFAULT ''
);

-- Start from a clean state before inserting seed rows
TRUNCATE TABLE benchmark_accounts RESTART IDENTITY;

WITH source_rows AS (
    SELECT
        gs AS account_id,
        CASE WHEN gs % 5 = 0 THEN 'suspended'
             WHEN gs % 2 = 0 THEN 'active'
             ELSE 'inactive'
        END AS status,
        ROUND((random() * 10000)::numeric, 2) AS balance,
        (NOW() - (gs % 365) * INTERVAL '1 day') AS last_accessed,
        (gs % 100) AS version,
        'seed row ' || gs AS note
    FROM generate_series(1, 10000) AS gs
)
INSERT INTO benchmark_accounts (id, status, balance, last_accessed, version, note)
SELECT
    account_id,
    status,
    balance,
    last_accessed,
    version,
    note
FROM source_rows
ORDER BY account_id;

-- Ensure the sequence aligns with the highest seeded id for future inserts
SELECT setval(
    pg_get_serial_sequence('benchmark_accounts', 'id'),
    COALESCE((SELECT MAX(id) FROM benchmark_accounts), 1),
    true
);

-- Optional index to reflect typical lookup patterns
CREATE INDEX IF NOT EXISTS idx_benchmark_accounts_status
    ON benchmark_accounts (status);

-- Reset statistics to have clean measurements

SELECT pg_stat_reset_shared('bgwriter');
SELECT pg_stat_reset_shared('wal');
