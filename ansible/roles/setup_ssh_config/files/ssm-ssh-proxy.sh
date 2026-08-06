#!/bin/bash
# ssm-ssh-proxy.sh – AWS SSM Session Manager 経由で SSH 接続するための ProxyCommand 用スクリプト
#
# 使い方 (~/.ssh/config の ProxyCommand から呼び出される):
#   ssm-ssh-proxy.sh <ComputerName> <port>
#
# 環境変数 AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY には Switch Only
# (AssumeRole 専用で他の権限を持たない) IAM ユーザーのキーが入っている前提。
# SSM を操作する権限を得るため、AWS_ROLE_ARN のロールを一時的に AssumeRole し、
# その一時クレデンシャルでのみ SSM API を呼び出す (このスクリプトのプロセス内
# だけで有効なため、呼び出し元シェルの環境変数は変更されない)。

set -euo pipefail

COMPUTER_NAME="$1"
PORT="$2"

if [ -z "${AWS_ROLE_ARN:-}" ]; then
  echo "ssm-ssh-proxy.sh: 環境変数 AWS_ROLE_ARN が設定されていません" >&2
  exit 1
fi

_creds=$(aws sts assume-role \
  --role-arn "${AWS_ROLE_ARN}" \
  --role-session-name "ssm-ssh-proxy" \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
  --output text)

read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "${_creds}"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

INSTANCE_ID=$(aws ssm describe-instance-information \
  --filters "Key=PingStatus,Values=Online" \
  --query "InstanceInformationList[?ComputerName=='${COMPUTER_NAME}'].InstanceId" \
  --output text)

if [ -z "${INSTANCE_ID}" ] || [ "${INSTANCE_ID}" = "None" ]; then
  echo "ssm-ssh-proxy.sh: SSM Managed Instance が見つかりません (ComputerName=${COMPUTER_NAME})" >&2
  exit 1
fi

exec aws ssm start-session \
  --target "${INSTANCE_ID}" \
  --document-name AWS-StartSSHSession \
  --parameters "portNumber=${PORT}"
