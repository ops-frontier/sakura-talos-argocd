# ------------------------------------------------------------------------------
# 1. SSM Agent 用の IAM ロールを作成
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "ssm_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_hybrid_role" {
  name               = "ssm-hybrid-activation-role"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume_role.json
}

# オンプレ/他社クラウド管理に必要なポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "ssm_hybrid_policy" {
  role       = aws_iam_role.ssm_hybrid_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ------------------------------------------------------------------------------
# 2. SSM Activation（アクティベーションコード）を発行
# ------------------------------------------------------------------------------
resource "aws_ssm_activation" "k3s_activation" {
  name               = "sakura-flatcar-k3s-nodes"
  description        = "Activation code for Sakura Cloud Flatcar nodes"
  iam_role           = aws_iam_role.ssm_hybrid_role.name
  registration_limit = 3 # 登録を許可する上限台数（例: 3台）
  
  # 有効期限（デフォルトは24時間。最長30日まで設定可能）
  expiration_date    = timeadd(timestamp(), "24h")

  depends_on = [aws_iam_role_policy_attachment.ssm_hybrid_policy]
}
