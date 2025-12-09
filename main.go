package main

import (
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"

	_ "github.com/lib/pq"
	"github.com/spf13/cobra"
	"github.com/stephenafamo/bob"
	"github.com/yy-at-here/psql_update/bobmodels/models"
)

const (
	defaultMode         = "without-tx"
	benchmarkRuns       = 5
	benchmarkOutputPath = "output/go_sql_benchmark_results.csv"
	postgresDriver      = "postgres"
	defaultDatabaseURL  = "postgres://postgres:postgres@localhost:15432/app_db?sslmode=disable"
)

var allModes = []string{
	"without-tx",
	"with-tx",
	"with-multi-tx",
	"bulk",
	"raw-sql-with-tx",
	"raw-sql-without-tx",
}

type Result struct {
	Name         string
	Duration     time.Duration
	WalSyncTime  float64
	WalSyncCount int64
	Err          error
}

func main() {
	rootCmd := &cobra.Command{Use: "app"}
	rootCmd.AddCommand(newExecOnceCommand(), newBenchmarkCommand())

	if err := rootCmd.Execute(); err != nil {
		panic(err)
	}
}

func newExecOnceCommand() *cobra.Command {
	var mode string

	cmd := &cobra.Command{
		Use:   "exec-once",
		Short: "1回だけ更新処理を実行します",
		RunE: func(cmd *cobra.Command, args []string) error {
			res, err := runOnce(cmd.Context(), mode)
			if err == nil {
				fmt.Fprintf(
					cmd.OutOrStdout(),
					"[%s] seconds=%.6f wal_sync_time=%.3f wal_sync=%d\n",
					res.Name,
					res.Duration.Seconds(),
					res.WalSyncTime,
					res.WalSyncCount,
				)
			}
			return err
		},
	}

	cmd.Flags().StringVar(&mode, "mode", defaultMode, "Update mode: without-tx, with-tx, with-multi-tx, bulk, raw-sql-with-tx, raw-sql-without-tx")

	return cmd
}

func newBenchmarkCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "benchmark",
		Short: "全モードを複数回実行し、結果をCSVに保存します",
		RunE: func(cmd *cobra.Command, args []string) error {
			records, err := runBenchmark(cmd.Context())
			if err != nil {
				return err
			}
			if err := writeBenchmarkCSV(records, benchmarkOutputPath); err != nil {
				return err
			}
			fmt.Fprintf(cmd.OutOrStdout(), "Wrote benchmark results to %s\n", benchmarkOutputPath)
			return nil
		},
	}

	return cmd
}

func runOnce(ctx context.Context, mode string) (Result, error) {
	if ctx == nil {
		ctx = context.Background()
	}

	db, err := bob.Open(postgresDriver, defaultDatabaseURL)
	if err != nil {
		return Result{}, err
	}
	defer db.Close()

	if err := resetWalStats(ctx, db); err != nil {
		return Result{}, err
	}

	res, err := runScenario(ctx, mode, db)
	if err != nil {
		return Result{}, err
	}

	walSyncTime, walSyncCount, err := fetchWalMetrics(ctx, db)
	if err != nil {
		return Result{}, err
	}
	res.WalSyncTime = walSyncTime
	res.WalSyncCount = walSyncCount
	return res, nil
}

func runScenario(ctx context.Context, name string, db bob.DB) (Result, error) {
	if ctx == nil {
		ctx = context.Background()
	}

	benchmarkAccounts, err := models.BenchmarkAccounts.Query().All(ctx, db)
	if err != nil {
		return Result{}, err
	}

	start := time.Now()

	switch name {
	case "without-tx":
		err = updateWithoutTx(benchmarkAccounts, db, ctx)
	case "with-tx":
		err = updateWithTx(benchmarkAccounts, db, ctx)
	case "with-multi-tx":
		err = updateWithMultiTx(benchmarkAccounts, db, ctx)
	case "bulk":
		err = bulkUpdate(benchmarkAccounts, db, ctx)
	case "raw-sql-with-tx":
		err = updateRawSQLWithTx(benchmarkAccounts, db, ctx)
	case "raw-sql-without-tx":
		err = updateRawSQLWithoutTx(benchmarkAccounts, db, ctx)
	default:
		return Result{}, fmt.Errorf("unknown mode: %s", name)
	}

	duration := time.Since(start)

	if err != nil {
		return Result{Name: name, Duration: duration, Err: err}, err
	}

	return Result{Name: name, Duration: duration}, nil
}

func runBenchmark(ctx context.Context) ([][]string, error) {
	if ctx == nil {
		ctx = context.Background()
	}

	var records [][]string

	for _, mode := range allModes {
		durations := make([]float64, 0, benchmarkRuns)
		walSyncTimes := make([]float64, 0, benchmarkRuns)
		walSyncCounts := make([]float64, 0, benchmarkRuns)

		for run := 1; run <= benchmarkRuns; run++ {
			res, err := runOnce(ctx, mode)
			if err != nil {
				return nil, fmt.Errorf("mode %s run %d: %w", mode, run, err)
			}
			seconds := res.Duration.Seconds()
			durations = append(durations, seconds)
			walSyncTimes = append(walSyncTimes, res.WalSyncTime)
			walSyncCounts = append(walSyncCounts, float64(res.WalSyncCount))
			records = append(
				records,
				[]string{
					mode,
					strconv.Itoa(run),
					fmt.Sprintf("%.6f", seconds),
					fmt.Sprintf("%.3f", res.WalSyncTime),
					strconv.FormatInt(res.WalSyncCount, 10),
				},
			)
		}

		avgDuration := average(durations)
		avgWalSyncTime := average(walSyncTimes)
		avgWalSyncCount := average(walSyncCounts)
		records = append(
			records,
			[]string{
				mode,
				"avg",
				fmt.Sprintf("%.6f", avgDuration),
				fmt.Sprintf("%.3f", avgWalSyncTime),
				fmt.Sprintf("%.1f", avgWalSyncCount),
			},
		)
	}

	return records, nil
}

func resetWalStats(ctx context.Context, db bob.DB) error {
	if ctx == nil {
		ctx = context.Background()
	}
	_, err := db.ExecContext(ctx, "SELECT pg_stat_reset_shared('wal');")
	return err
}

func fetchWalMetrics(ctx context.Context, db bob.DB) (float64, int64, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	rows, err := db.QueryContext(ctx, `
		SELECT
			COALESCE(wal_sync_time, 0),
			COALESCE(wal_sync, 0)
		FROM pg_stat_wal;
	`)
	if err != nil {
		return 0, 0, err
	}
	defer rows.Close()

	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return 0, 0, err
		}
		return 0, 0, errors.New("pg_stat_wal returned no rows")
	}

	var walSyncTime float64
	var walSyncCount int64
	if err := rows.Scan(&walSyncTime, &walSyncCount); err != nil {
		return 0, 0, err
	}

	return walSyncTime, walSyncCount, nil
}

func writeBenchmarkCSV(records [][]string, path string) error {
	if len(records) == 0 {
		return errors.New("no benchmark records to write")
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}

	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := csv.NewWriter(file)
	if err := writer.Write([]string{"mode", "run", "elapsed_seconds", "wal_sync_time", "wal_sync_count"}); err != nil {
		return err
	}
	if err := writer.WriteAll(records); err != nil {
		return err
	}

	return writer.Error()
}

func average(values []float64) float64 {
	if len(values) == 0 {
		return 0
	}
	var total float64
	for _, v := range values {
		total += v
	}
	return total / float64(len(values))
}
