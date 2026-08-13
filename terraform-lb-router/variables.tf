variable "sakura_access_token" {
  description = "さくらのクラウド API アクセストークン"
  type        = string
  sensitive   = true
}

variable "sakura_access_token_secret" {
  description = "さくらのクラウド API アクセストークン シークレット"
  type        = string
  sensitive   = true
}

variable "sakura_label_prefix" {
  description = "サーバのラベルプリフィックス (ホスト名と一致させる)"
  type        = string
  default     = "ops-frontier"
}

variable "sakura_region" {
  description = "さくらのクラウドのリージョン"
  type        = string
  default     = "is1c"
}