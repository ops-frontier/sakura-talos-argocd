terraform {
  required_version = ">= 1.7"

  required_providers {
    sakuracloud = {
      source  = "sacloud/sakuracloud"
      version = "~> 2.25"
    }
  }
}

provider "sakuracloud" {
  token  = var.sakura_access_token
  secret = var.sakura_access_token_secret
  zone   = var.sakura_region
}