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
    # "update_10000_without_tx.sql",
    # "update_10000_with_tx.sql",
    # "update_10000_each_tx.sql",
    "bulk_update.sql",
]
RUNS = 5
OUTPUT = ROOT / "sql" / "sql_benchmark_results.csv"
DATABASE_URL_DEFAULT = "postgres://postgres:postgres@localhost:15432/app_db?sslmode=disable"


def run_case(sql_file: Path, database_url: str) -> list[float]:
    times: list[float] = []
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
        times.append(elapsed)
    return times


def main() -> int:
    if not SQL_DIR.exists():
        raise SystemExit(f"sql directory not found at {SQL_DIR}")
    if shutil.which("psql") is None:
        raise SystemExit("psql command not found in PATH")

    database_url = os.environ.get("DATABASE_URL", DATABASE_URL_DEFAULT)

    records: list[tuple[str, str, float]] = []

    for filename in TARGET_FILES:
        sql_path = SQL_DIR / filename
        if not sql_path.exists():
            raise SystemExit(f"SQL file not found: {sql_path}")
        times = run_case(sql_path, database_url)
        for idx, value in enumerate(times, start=1):
            records.append((filename, str(idx), value))
        avg = statistics.mean(times)
        records.append((filename, "avg", avg))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["file", "run", "elapsed_seconds"])
        writer.writerows(records)

    print(f"Wrote results to {OUTPUT}")
    return 0


if __name__ == "__main__":  # pragma: no branch
    raise SystemExit(main())
