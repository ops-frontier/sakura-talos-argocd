# ---------------------------------------------------------------
# さくらのクラウド ロードバランサ (L4)
# ---------------------------------------------------------------

# ルータ + スイッチ (LB 用グローバルIP)
resource "sakuracloud_internet" "lb_router" {
  name        = "${var.sakura_label_prefix}-lb-router"
  netmask     = 28
  band_width  = 100
  description = "LB 用 グローバル IP ルータ"
}

locals {
  lb_cidr    = "${sakuracloud_internet.lb_router.network_address}/${sakuracloud_internet.lb_router.netmask}"
  lb_mgmt_ip = cidrhost(local.lb_cidr, 4) # LB 管理 IP
  lb_vip_ip  = cidrhost(local.lb_cidr, 5) # VIP (DNS が指すパブリック IP)
}

resource "sakuracloud_load_balancer" "lb" {
  name        = "${var.sakura_label_prefix}-lb"
  description = "HTTP/HTTPS L4 ロードバランサ"
  plan        = "standard"

  network_interface {
    switch_id    = sakuracloud_internet.lb_router.switch_id
    vrid         = 1
    ip_addresses = [local.lb_mgmt_ip]
    netmask      = sakuracloud_internet.lb_router.netmask
    gateway      = sakuracloud_internet.lb_router.gateway
  }

  # HTTPS VIP
  vip {
    vip        = local.lb_vip_ip
    port       = 443
    delay_loop = 10
    # サーバ登録は lb-controller が API 経由で動的に管理する
  }

  # HTTP VIP (HTTPS へのリダイレクトは Ingress Controller 側で実施)
  vip {
    vip        = local.lb_vip_ip
    port       = 80
    delay_loop = 10
    # サーバ登録は lb-controller が API 経由で動的に管理する
  }
}

# ---------------------------------------------------------------
# Cloudflare DNS - ゾーン確認および A レコード登録
# ---------------------------------------------------------------
data "cloudflare_zone" "main" {
  name = var.domain
}

# argocd.poc A レコード -> LB VIP グローバル IP
resource "cloudflare_record" "argocd" {
  zone_id = data.cloudflare_zone.main.id
  type    = "A"
  name    = "argocd.poc"
  content = local.lb_vip_ip
  ttl     = 300
  proxied = false
}

# grafana.poc A レコード -> LB VIP グローバル IP
resource "cloudflare_record" "grafana" {
  zone_id = data.cloudflare_zone.main.id
  type    = "A"
  name    = "grafana.poc"
  content = local.lb_vip_ip
  ttl     = 300
  proxied = false
}

# ---------------------------------------------------------------
# さくらのクラウド コンテナレジストリ
# ---------------------------------------------------------------
resource "sakuracloud_container_registry" "main" {
  name            = "${replace(var.sakura_label_prefix, "-", "")}registry"
  access_level    = "none"
  subdomain_label = var.sakura_registry_subdomain_label
  description     = "インフラ組み込み Helm チャート用コンテナレジストリ"

  user {
    name       = "k3s-pull"
    password   = random_password.registry_pull_password.result
    permission = "readonly"
  }

  user {
    name       = "ci-push"
    password   = random_password.registry_push_password.result
    permission = "readwrite"
  }
}

resource "random_password" "registry_pull_password" {
  length  = 32
  special = false
}

resource "random_password" "registry_push_password" {
  length  = 32
  special = false
}
