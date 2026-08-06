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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "sakuracloud" {
  token  = var.sakura_access_token
  secret = var.sakura_access_token_secret
  zone   = var.sakura_region
}

provider "cloudflare" {
  api_token = var.cloudflare_access_token
}

provider "aws" {
  region = "ap-northeast-1"

  assume_role {
    role_arn     = var.aws_role_arn
    session_name = "CodespacesTerraform"
  }
}
