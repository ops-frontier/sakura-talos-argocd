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
# コンテナレジストリ
# CR_FQDN / CR_USER / CR_PASSWORD
# 環境変数で外部のコンテナレジストリを指定するため、terraform では構築しない
# ---------------------------------------------------------------
