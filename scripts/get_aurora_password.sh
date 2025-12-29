#!/bin/bash
# Aurora のマスターパスワードを Secrets Manager から取得するスクリプト

set -e

CLUSTER_ID="${1:-psql-update-aurora-cluster}"

# Secret ARN を取得
SECRET_ARN=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].MasterUserSecret.SecretArn' \
  --output text)

if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
  echo "Error: Could not find secret ARN for cluster $CLUSTER_ID" >&2
  exit 1
fi

# パスワードを取得
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text | jq -r '.password'
