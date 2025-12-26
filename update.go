package main

import (
	"context"
	"fmt"
	"time"

	"github.com/aarondl/opt/omit"
	"github.com/stephenafamo/bob"
	"github.com/yy-at-here/psql_update/bobmodels/models"
)

func updateWithoutTx(ba models.BenchmarkAccountSlice, db bob.DB, ctx context.Context) error {
	setter := &models.BenchmarkAccountSetter{
		Status: omit.From("active"),
	}
	for _, benchmarkAccount := range ba {
		if err := benchmarkAccount.Update(ctx, db, setter); err != nil {
			return err
		}
	}

	return nil
}

func updateWithMultiTx(ba models.BenchmarkAccountSlice, db bob.DB, ctx context.Context) error {
	setter := &models.BenchmarkAccountSetter{
		Status: omit.From("active"),
	}
	for _, benchmarkAccount := range ba {
		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if err := benchmarkAccount.Update(ctx, tx, setter); err != nil {
			return tx.Rollback(ctx)
		}
		if err := tx.Commit(ctx); err != nil {
			return err
		}
	}
	return nil
}

func updateWithTx(ba models.BenchmarkAccountSlice, db bob.DB, ctx context.Context) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}

	setter := &models.BenchmarkAccountSetter{
		Status: omit.From("active"),
	}
	start := time.Now()
	for _, benchmarkAccount := range ba {
		if err := benchmarkAccount.Update(ctx, tx, setter); err != nil {
			return tx.Rollback(ctx)
		}
	}
	fmt.Printf("In Transaction, took %s\n", time.Since(start))
	return tx.Commit(ctx)
}

func bulkUpdate(ba models.BenchmarkAccountSlice, db bob.DB, ctx context.Context) error {
	setter := models.BenchmarkAccountSetter{
		Status: omit.From("active"),
	}
	if err := ba.UpdateAll(ctx, db, setter); err != nil {
		return err
	}
	return nil
}

func updateRawSQLWithTx(ba models.BenchmarkAccountSlice, db bob.DB, ctx context.Context) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}

	start := time.Now()
	for _, benchmarkAccount := range ba {
		if _, err := tx.ExecContext(ctx,
			"UPDATE benchmark_accounts SET status = 'active' WHERE id = $1",
			benchmarkAccount.ID,
		); err != nil {
			return tx.Rollback(ctx)
		}
	}
	fmt.Printf("In Transaction, took %s\n", time.Since(start))
	return tx.Commit(ctx)
}

func updateRawSQLWithTxPrepare(ba models.BenchmarkAccountSlice, db bob.DB, ctx context.Context) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}

	start := time.Now()
	stmt, err := tx.PrepareContext(ctx, "UPDATE benchmark_accounts SET status = 'active' WHERE id = $1")
	if err != nil {
		return err
	}
	defer stmt.Close()
	for _, benchmarkAccount := range ba {
		if _, err := stmt.ExecContext(ctx, benchmarkAccount.ID); err != nil {
			return tx.Rollback(ctx)
		}
	}
	fmt.Printf("In Transaction, took %s\n", time.Since(start))
	return tx.Commit(ctx)
}

func updateRawSQLWithoutTx(ba models.BenchmarkAccountSlice, db bob.DB, ctx context.Context) error {
	for _, benchmarkAccount := range ba {
		if _, err := db.ExecContext(ctx,
			"UPDATE benchmark_accounts SET status = 'active' WHERE id = $1",
			benchmarkAccount.ID,
		); err != nil {
			return err
		}
	}
	return nil
}

func updateRawSQLWithoutTxPrepare(ba models.BenchmarkAccountSlice, db bob.DB, ctx context.Context) (err error) {
	var stmt bob.StdPrepared
	if stmt, err = db.PrepareContext(ctx, "UPDATE benchmark_accounts SET status = 'active' WHERE id = $1"); err != nil {
		return err
	}
	defer stmt.Close()
	for _, benchmarkAccount := range ba {
		if _, err := stmt.ExecContext(ctx, benchmarkAccount.ID); err != nil {
			return err
		}
	}
	return nil
}
