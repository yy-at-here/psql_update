#!/bin/bash
set -e

# ログファイル設定
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting user data script..."

# システムアップデートと基本パッケージインストール
yum update -y
yum install -y git postgresql17 make

# Go のインストール（システム全体）
GO_VERSION="1.24.2"
cd /tmp
wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile.d/go.sh

# ec2-user として以下を実行
EC2_USER_HOME="/home/ec2-user"

# Python (uv) のインストール（ec2-user 用）
sudo -u ec2-user bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'

# リポジトリのクローン（ec2-user のホームディレクトリに）
sudo -u ec2-user bash -c "
  export PATH=\$PATH:/usr/local/go/bin
  cd ${EC2_USER_HOME}
  git clone https://github.com/yy-at-here/psql_update.git
  cd psql_update
  go mod download
  go mod vendor
"

# Python 依存関係のセットアップ（ec2-user として）
sudo -u ec2-user bash -c "
  source ${EC2_USER_HOME}/.local/bin/env
  cd ${EC2_USER_HOME}/psql_update
  if [ -f 'pyproject.toml' ]; then
    uv sync
  fi
"

echo "User data script completed successfully"
