terraform {
  required_version = ">= 1.7"

  required_providers {
    sakuracloud = {
      source  = "sacloud/sakuracloud"
      version = "~> 2.25"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    omni = {
      source = "siderolabs/omni"
      # Registry には現時点で 0.1.0-alpha.3 のみ公開されている。
      # プレリリース版はバージョン制約演算子にマッチしないため厳密指定する。
      version = "0.1.0-alpha.3"
    }
    # Cilium Helm chart を terraform apply 時にレンダリングして
    # omni_config_patch の inline manifest に埋め込むために使用する。
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    # ArgoCD 本体のインストールマニフェストを GitHub から取得するために使用する。
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "helm" {}

provider "sakuracloud" {
  token  = var.sakura_access_token
  secret = var.sakura_access_token_secret
  zone   = var.sakura_region
}

provider "cloudflare" {
  api_token = var.cloudflare_access_token
}
