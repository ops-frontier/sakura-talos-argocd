# AWS SSM Agent の導入

AWS SSM Agent を導入する。現在はパケットフィルタに Codesapces の IPアドレスを送信元として SSH の接続を許可しているが、これを廃止して SSM Agent 経由の接続に変更する。また、 k3s API への接続を SSH トンネルによって行っているがこれも SSM Agent 経由での接続に変更する

## AWS へのアクセス

Terraform から SSM Agent のアクティベーションコードを発行するためには、 AmazonSSMFullAccess ポリシーが許可された状態でアクセスする必要があります。
このため、Codespaces 用の IAMユーザのアクセスキーで AssumeRole する方式を取ります。

### 1. アクセスキーの発行

Codespaces 用の IAMユーザを作成し、そのユーザのアクセスキーを発行します。

1. AWSコンソールでIAM > IAM ユーザーの画面から「ユーザの作成」をクリック
2. ユーザ名に `codespace-access` を入力して、「次へ」をクリック
3. 「許可の設定」で「次へ」をクリック
4. 「確認して作成」で「ユーザの作成」をクリック
5. IAMユーザの検索に`codespace-access`を入力し、表示された`codespace-access` をクリック
6. ARNの値をロールの作成の手順のために控えておく
7. 「セキュリティ認証情報」タブを開き、「アクセスキーを作成」をクリック
8. 「コマンドラインインターフェイス (CLI)」を選択し、「上記のレコメンデーションを理解し、アクセスキーを作成します。」をチェックして「次へ」をクリック
9. 「アクセスキーを作成」をクリック
10. 「アクセスキー」、「シークレットアクセスキー」について、コピーアイコンで値をコピーし、Github のリポジトリ設定のために控えておく
11. 「完了」をクリック

### 2. ポリシーの追加

1. AWSコンソールでIAM > ポリシーの画面から「ポリシーの作成」をクリック
2. 「ポリシーエディタ」で「JSON」をクリックして、内容を以下の JSON に入れ替え

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "iam:GetRole",
                "iam:ListRoleTags",
                "iam:RemoveRoleFromInstanceProfile",
                "iam:UpdateRoleDescription",
                "iam:DeletePolicy",
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:AttachRolePolicy",
                "iam:AddRoleToInstanceProfile",
                "iam:CreatePolicy",
                "iam:ListInstanceProfilesForRole",
                "iam:GetServiceLinkedRoleDeletionStatus",
                "iam:PassRole",
                "iam:CreateServiceLinkedRole",
                "iam:DetachRolePolicy",
                "iam:ListAttachedRolePolicies",
                "iam:UpdateRole",
                "iam:DeleteServiceLinkedRole",
                "iam:ListRolePolicies",
                "iam:GetRolePolicy"
            ],
            "Resource": [
                "arn:aws:iam::878518084785:policy/*",
                "arn:aws:iam::878518084785:role/*",
                "arn:aws:iam::878518084785:instance-profile/*"
            ]
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "iam:ListRoles",
            "Resource": "*"
        }
    ]
}
```

3. 「ポリシー名」に`IAMRoleFullAccess`を入力し、「ポリシーを作成」をクリック

### 2. ロールの作成

Codespaces からアクセスするときに使用するロールを作成します。
1. AWSコンソールでIAM > ロールの画面から「ロールを作成」をクリック
2. 「信頼されたエンティティタイプ」で「カスタム信頼ポリシー」を選択し、表示されたJSONの Principal の項目に `"AWS": "`*codespace-accessユーザのARN*`"`「次へ」をクリック
3. 「許可ポリシー」の検索に`AmazonSSMFullAccess`を入力し、表示された`AmazonSSMFullAccess`のチェックボックスをチェック
4. 「許可ポリシー」の検索に`IAMRoleFullAccess`を入力し、表示された`IAMRoleFullAccess`のチェックボックスをチェックして、「次へ」をクリック
5. 「ロール名」に`SSMAgentProvisioner`を入力し、「ロールを作成」をクリック
6. ロールの検索に`SSMAgentProvisioner`を入力し、表示された`SSMAgentProvisioner` をクリック
7. ARNの値をGithub のリポジトリ設定のために控えておく

### 3. GitHub Codespaces Secrets の設定

Gtihub リポジトリの **Settings ＞ Secrets and variables ＞ Codespaces** に、上記 IAM ユーザーのアクセスキーと引き受けるロール ARN を登録します。

* **`AWS_ACCESS_KEY_ID`**: （IAM ユーザーのアクセスキー）
* **`AWS_SECRET_ACCESS_KEY`**: （IAM ユーザーのシークレット）
* **`AWS_ROLE_ARN`**: `arn:aws:iam::123456789012:role/CodespacesTerraformRole`
* **`AWS_REGION`**: `ap-northeast-1`

### 4. Codespaces（Terraform / CLI）側での実行方法

Codespaces が起動すると、上記の環境変数が自動セットされます。

**A. AWS CLI の場合**
`assume-role` コマンドで一時クレデンシャルを取得します。

```bash
eval $(aws sts assume-role \
  --role-arn "$AWS_ROLE_ARN" \
  --role-session-name "codespaces-session" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text | awk '{print "export AWS_ACCESS_KEY_ID="$1"\nexport AWS_SECRET_ACCESS_KEY="$2"\nexport AWS_SESSION_TOKEN="$3}')

```

**B. Terraform の場合**
Terraform は `assume_role` ブロックを解釈できるため、シェルで入れ替えなくても `provider` 設定だけで自動的にロールを引き受けてくれます。

```hcl
provider "aws" {
  region = "ap-northeast-1"

  assume_role {
    role_arn     = var.aws_role_arn # 環境変数 AWS_ROLE_ARN を読み込ませる
    session_name = "CodespacesTerraform"
  }
}

```

## SSMエージェントのインストール

IaC 実装済み

# クライアント側からの接続

以下のコマンドでクライアントからのトンネル開始に成功した。
```
# Assume Role （環境変数を上書きする方式なので、このシェルの中だけで有効）
eval $(aws sts assume-role \
  --role-arn "$AWS_ROLE_ARN" \
  --role-session-name "codespaces-session" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text | awk '{print "export AWS_ACCESS_KEY_ID="$1"\nexport AWS_SECRET_ACCESS_KEY="$2"\nexport AWS_SESSION_TOKEN="$3}')
# 「k3s-node」という名前のタグや名前を持つオンラインの SSM インスタンス ID を 1 台自動取得
TARGET_ID=$(aws ssm describe-instance-information --filters "Key=PingStatus,Values=Online" \
  --query "InstanceInformationList[?ComputerName == 'dis-poc-sv1'].InstanceId" --output text)

# 自動取得した ID に対してトンネルを開始
aws ssm start-session \
  --target "$TARGET_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6443"],"localPortNumber":["6443"]}'
```

以下のコマンドでトンネル経由でサーバの k3s API に接続できることを確認した。
```
allow-ssh
mkdir ~/.kube
scp dis-poc-sv1:/etc/rancher/k3s/k3s.yaml ~/.kube/config
kubectl get pods --namespace argocd
```