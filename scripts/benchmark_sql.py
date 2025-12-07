#!/usr/bin/env python3
from __future__ import annotations

import csv
import os
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
SQL_DIR = ROOT / "sql"
TARGET_FILES = [
    "update_10000_without_tx.sql",
    "update_10000_with_tx.sql",
    "update_10000_each_tx.sql",
    "bulk_update.sql",
]
RUNS = 5
OUTPUT = ROOT / "output" / "raw_sql_benchmark_results.csv"
DATABASE_URL_DEFAULT = "postgres://postgres:postgres@localhost:15432/app_db?sslmode=disable"


def _run_psql_command(database_url: str, sql: str) -> str:
    proc = subprocess.run(
        [
            "psql",
            "--set=ON_ERROR_STOP=1",
            f"--dbname={database_url}",
            "-tA",
            "-q",
            "-c",
            sql,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        if proc.stderr:
            sys.stderr.write(proc.stderr)
        raise SystemExit(proc.returncode)
    return proc.stdout.strip()


def reset_wal_stats(database_url: str) -> None:
    _run_psql_command(database_url, "SELECT pg_stat_reset_shared('wal');")


def fetch_wal_metrics(database_url: str) -> tuple[float, int]:
    result = _run_psql_command(
        database_url,
        "SELECT wal_sync_time, wal_sync FROM pg_stat_wal;",
    )
    parts = [item.strip() for item in result.split("|") if item.strip()]
    if len(parts) != 2:
        raise SystemExit(f"Failed to parse wal metrics from output: {result!r}")
    wal_sync_time_str, wal_sync_str = parts
    try:
        return float(wal_sync_time_str), int(wal_sync_str)
    except ValueError:
        raise SystemExit(
            f"Failed to convert wal metrics to numbers: time={wal_sync_time_str!r}, sync={wal_sync_str!r}"
        )


def run_case(sql_file: Path, database_url: str) -> list[tuple[float, float, int]]:
    measurements: list[tuple[float, float, int]] = []
    reset_wal_stats(database_url)
    for _ in range(RUNS):
        start = time.perf_counter()
        proc = subprocess.run(
            [
                "psql",
                "--set=ON_ERROR_STOP=1",
                f"--dbname={database_url}",
                f"--file={sql_file}",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        elapsed = time.perf_counter() - start
        if proc.returncode != 0:
            if proc.stderr:
                sys.stderr.write(proc.stderr)
            raise SystemExit(proc.returncode)
        wal_sync_time, wal_sync = fetch_wal_metrics(database_url)
        measurements.append((elapsed, wal_sync_time, wal_sync))
        reset_wal_stats(database_url)
    return measurements


def main() -> int:
    if not SQL_DIR.exists():
        raise SystemExit(f"sql directory not found at {SQL_DIR}")
    if shutil.which("psql") is None:
        raise SystemExit("psql command not found in PATH")

    database_url = os.environ.get("DATABASE_URL", DATABASE_URL_DEFAULT)

    records: list[tuple[str, str, float, float, int]] = []

    for filename in TARGET_FILES:
        sql_path = SQL_DIR / filename
        if not sql_path.exists():
            raise SystemExit(f"SQL file not found: {sql_path}")
        measurements = run_case(sql_path, database_url)
        elapsed_values = [item[0] for item in measurements]
        wal_sync_time_values = [item[1] for item in measurements]
        wal_sync_counts = [item[2] for item in measurements]
        for idx, (elapsed, wal_sync_time, wal_sync) in enumerate(measurements, start=1):
            records.append((filename, str(idx), elapsed, wal_sync_time, wal_sync))
        avg_elapsed = statistics.mean(elapsed_values)
        avg_wal_sync_time = statistics.mean(wal_sync_time_values)
        avg_wal_sync = statistics.mean(wal_sync_counts)
        records.append((filename, "avg", avg_elapsed, avg_wal_sync_time, avg_wal_sync))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["file", "run", "elapsed_seconds", "wal_sync_time", "wal_sync_count"])
        writer.writerows(records)

    print(f"Wrote results to {OUTPUT}")
    return 0


if __name__ == "__main__":  # pragma: no branch
    raise SystemExit(main())
