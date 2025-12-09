## 本リポジトリの使い方

PostgreSQL での UPDATE 実行について、以下のケースで簡単にベンチマークできる環境を作成しました。

- ORM ([bob](https://github.com/stephenafamo/bob)) を使用した場合の実行時間
- 生の SQL を実行した場合の実行時間

各ケースで、以下の実行時間を 5 回分計測し、結果を csv に出力します。

- トランザクションを張らずに 1 万回 UPDATE する
- トランザクションを張って 1 万回 UPDATE する
- bulk uPDATE で、1発だけ UPDATE する

## 検証環境のセットアップ

#### DB 立ち上げ

```bash
docker compose up # PostgreSQL を立ち上げる
make seed-db # テーブル作成
```

#### Go, uv (Python) 環境用意

(skip)

## 比較項目

## 検証方法

### 生の SQL 

```bash
uv run scripts/benchmark_sql.py
```

実行される具体的な SQL については、 `sql` 下を確認してください。

`output/raw_sql_benchmark_results.csv` に結果が出力されます。

### ORM

```bash
go run . benchmark
```

`output/go_sql_benchmark_results.csv` に結果が出力されます。