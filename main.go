package main

import (
	"context"
	"fmt"
	"time"

	_ "github.com/lib/pq"
	"github.com/spf13/cobra"
	"github.com/stephenafamo/bob"
	"github.com/yy-at-here/psql_update/bobmodels/models"
)

func main() {

	var mode string
	rootCommand := &cobra.Command{
		Use: "app",
		RunE: func(cmd *cobra.Command, args []string) error {
			return exec(cmd.Context(), cmd, mode)
		},
	}

	rootCommand.Flags().StringVar(&mode, "mode", "without-tx", "Update mode: without-tx, with-tx, bulk, raw-sql-without-tx, raw-sql-with-tx")
	if err := rootCommand.Execute(); err != nil {
		panic(err)
	}

}

type Result struct {
	Name     string
	Duration time.Duration
	Err      error
}

func exec(ctx context.Context, cmd *cobra.Command, mode string) error {
	var db bob.DB
	var err error
	if db, err = bob.Open("postgres", "postgres://postgres:postgres@localhost:15432/app_db?sslmode=disable"); err != nil {
		panic(err)
	}
	defer db.Close()

	result := runScenario(ctx, mode, db)
	fmt.Fprintf(cmd.OutOrStdout(),
		"[%s] seconds=%f\n",
		result.Name,
		result.Duration.Seconds(),
	)
	return nil
}

func runScenario(ctx context.Context, name string, db bob.DB) Result {
	benchmarkAccounts, err := models.BenchmarkAccounts.Query().All(ctx, db)
	if err != nil {
		panic(err)
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
		panic("unknown mode: " + name)
	}

	return Result{
		Name:     name,
		Duration: time.Since(start),
		Err:      err,
	}
}
