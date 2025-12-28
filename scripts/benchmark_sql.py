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
from urllib.parse import quote_plus
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
SQL_DIR = ROOT / "sql"
TARGET_FILES = [
    "roundtrip.sql",
    "update_10000_without_tx.sql",
    "update_10000_with_tx.sql",
    "update_10000_with_tx_prepare.sql",
    "update_10000_without_tx_prepare.sql",
    "update_10000_each_tx.sql",
    "bulk_update.sql",
]
RUNS = 5
OUTPUT_DIR = ROOT / "output" / "csv"
OUTPUT_PREFIX = "raw_sql_benchmark_results"


def get_database_url() -> str:
    """環境変数から DATABASE_URL 組み立てる"""
    dotenv_path = os.path.join(ROOT, '.env')
    load_dotenv(dotenv_path=dotenv_path)

    user = os.environ.get("POSTGRES_USER", "postgres")
    password = os.environ.get("PGPASSWORD", "postgres")
    endpoint = os.environ.get("POSTGRES_ENDPOINT", "localhost:15432")
    db = os.environ.get("POSTGRES_DB", "app_db")
    sslmode = os.environ.get("PGSSLMODE", "disable")

    # パスワードに特殊文字が含まれる場合に備えて URL エンコード
    encoded_password = quote_plus(password)

    return f"postgres://{user}:{encoded_password}@{endpoint}/{db}?sslmode={sslmode}"


def _run_psql_command(database_url: str, sql: str, ignore_error: bool = False) -> tuple[str, bool]:
    """
    psql コマンドを実行する。
    戻り値: (出力, 成功したか)
    ignore_error=True の場合、エラーでも終了せずに (出力, False) を返す
    """
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
        if ignore_error:
            return proc.stderr.strip(), False
        if proc.stderr:
            sys.stderr.write(proc.stderr)
        raise SystemExit(proc.returncode)
    return proc.stdout.strip(), True


def reset_wal_stats(database_url: str) -> bool:
    """WAL 統計をリセット。成功したら True、失敗したら False"""
    _, success = _run_psql_command(
        database_url,
        "SELECT pg_stat_reset_shared('wal');",
        ignore_error=True,
    )
    if not success:
        print("Warning: failed to reset WAL stats (may not be supported on Aurora)", file=sys.stderr)
    return success


def reset_stats(database_url: str) -> bool:
    """統計情報をリセット。失敗しても処理は続行する"""
    _, success = _run_psql_command(
        database_url,
        "SELECT pg_stat_reset();",
        ignore_error=True,
    )
    if not success:
        print("Warning: failed to reset stats (pg_stat_reset)", file=sys.stderr)
    return success


def fetch_commit_latency_ms(database_url: str, datname: str) -> int | None:
    """aurora_stat_get_db_commit_latency を ms(切り捨て)で取得。失敗時は None。"""
    sql = (
        "SELECT aurora_stat_get_db_commit_latency(oid) "
        f"FROM pg_database WHERE datname='{datname}';"
    )
    result, success = _run_psql_command(database_url, sql, ignore_error=True)
    if not success:
        print(
            "Warning: failed to fetch commit latency (aurora_stat_get_db_commit_latency may be unsupported)",
            file=sys.stderr,
        )
        return None

    result = result.strip()
    if not result:
        return None
    try:
        micros = int(float(result))
    except ValueError:
        print(f"Warning: failed to parse commit latency: {result!r}", file=sys.stderr)
        return None
    return micros // 1000


def fetch_wal_metrics(database_url: str) -> tuple[float, int] | None:
    """WAL メトリクスを取得。失敗したら None を返す"""
    result, success = _run_psql_command(
        database_url,
        "SELECT wal_sync_time, wal_sync FROM pg_stat_wal;",
        ignore_error=True,
    )
    if not success:
        print("Warning: failed to fetch WAL metrics (may not be supported on Aurora)", file=sys.stderr)
        return None
    parts = [item.strip() for item in result.split("|") if item.strip()]
    if len(parts) != 2:
        print(f"Warning: failed to parse WAL metrics from output: {result!r}", file=sys.stderr)
        return None
    wal_sync_time_str, wal_sync_str = parts
    try:
        return float(wal_sync_time_str), int(wal_sync_str)
    except ValueError:
        print(
            f"Warning: failed to convert WAL metrics to numbers: time={wal_sync_time_str!r}, sync={wal_sync_str!r}",
            file=sys.stderr,
        )
        return None


def run_case(sql_file: Path, database_url: str, dbname: str) -> list[tuple[float, float, int, int | None]]:
    measurements: list[tuple[float, float, int, int | None]] = []
    reset_wal_stats(database_url)
    reset_stats(database_url)
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

        wal_metrics = fetch_wal_metrics(database_url)
        if wal_metrics is not None:
            wal_sync_time, wal_sync = wal_metrics
        else:
            wal_sync_time, wal_sync = 0.0, 0

        commit_latency_ms = fetch_commit_latency_ms(database_url, dbname)
        measurements.append((elapsed, wal_sync_time, wal_sync, commit_latency_ms))
        reset_wal_stats(database_url)
        reset_stats(database_url)
    return measurements


def next_output_path() -> Path:
    timestamp = time.strftime("%Y%m%d%H%M%S")
    return OUTPUT_DIR / f"{OUTPUT_PREFIX}_{timestamp}.csv"


def main() -> int:
    if not SQL_DIR.exists():
        raise SystemExit(f"sql directory not found at {SQL_DIR}")
    if shutil.which("psql") is None:
        raise SystemExit("psql command not found in PATH")

    database_url = get_database_url()
    dbname = os.environ.get("POSTGRES_DB", "app_db")

    records: list[tuple[str, str, float, float, int, int]] = []

    for filename in TARGET_FILES:
        sql_path = SQL_DIR / filename
        if not sql_path.exists():
            raise SystemExit(f"SQL file not found: {sql_path}")
        measurements = run_case(sql_path, database_url, dbname)
        elapsed_values = [item[0] for item in measurements]
        wal_sync_time_values = [item[1] for item in measurements]
        wal_sync_counts = [item[2] for item in measurements]
        commit_latency_values = [item[3] for item in measurements if item[3] is not None]
        for idx, (elapsed, wal_sync_time, wal_sync, commit_latency_ms) in enumerate(measurements, start=1):
            records.append((filename, str(idx), elapsed, wal_sync_time, wal_sync, commit_latency_ms or 0))
        avg_elapsed = statistics.mean(elapsed_values)
        avg_wal_sync_time = statistics.mean(wal_sync_time_values)
        avg_wal_sync = statistics.mean(wal_sync_counts)
        avg_commit_latency_ms = statistics.mean(commit_latency_values) if commit_latency_values else 0
        records.append((filename, "avg", avg_elapsed, avg_wal_sync_time, avg_wal_sync, int(avg_commit_latency_ms)))

    output_path = next_output_path()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["file", "run", "elapsed_seconds", "wal_sync_time", "wal_sync_count", "commit_latency_ms"])
        writer.writerows(records)

    print(f"Wrote results to {output_path}")
    return 0


if __name__ == "__main__":  # pragma: no branch
    raise SystemExit(main())
