# ---------------------------------------------------------------
# さくらのクラウド ロードバランサ (L4)
# ---------------------------------------------------------------

removed {
  from = sakuracloud_internet.lb_router

  lifecycle {
    destroy = false
  }
}

# ルータ + スイッチ (LB 用グローバルIP)
data "sakuracloud_internet" "lb_router" {
  filter {
    names = ["${var.sakura_label_prefix}-lb-router"]
  }
}

locals {
  lb_cidr    = "${data.sakuracloud_internet.lb_router.network_address}/${data.sakuracloud_internet.lb_router.netmask}"
  lb_mgmt_ip = cidrhost(local.lb_cidr, 4) # LB 管理 IP
  lb_vip_ip  = cidrhost(local.lb_cidr, 5) # VIP (DNS が指すパブリック IP)
}

resource "sakuracloud_load_balancer" "lb" {
  name        = "${var.sakura_label_prefix}-lb"
  description = "HTTP/HTTPS/Kubernetes API L4 ロードバランサ"
  plan        = "standard"

  network_interface {
    switch_id    = data.sakuracloud_internet.lb_router.switch_id
    vrid         = 1
    ip_addresses = [local.lb_mgmt_ip]
    netmask      = data.sakuracloud_internet.lb_router.netmask
    gateway      = data.sakuracloud_internet.lb_router.gateway
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

  # Kubernetes API VIP
  # Cilium / lb-controller の起動前から API に接続できるよう3台を初期登録する。
  vip {
    vip        = local.lb_vip_ip
    port       = 6443
    delay_loop = 10

    dynamic "server" {
      for_each = sakuracloud_server.nodes
      content {
        ip_address = server.value.ip_address
        protocol   = "tcp"
        enabled    = true
      }
    }
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

# k8s-api A レコード -> LB VIP グローバル IP
resource "cloudflare_record" "k8s_api" {
  zone_id = data.cloudflare_zone.main.id
  type    = "A"
  name    = "k8s-api"
  content = local.lb_vip_ip
  ttl     = 300
  proxied = false
}

# ---------------------------------------------------------------
# コンテナレジストリ
# CR_FQDN / CR_USER / CR_PASSWORD
# 環境変数で外部のコンテナレジストリを指定するため、terraform では構築しない
# ---------------------------------------------------------------
