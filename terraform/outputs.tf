output "node_public_ips" {
  description = "各ノードのパブリック IP アドレス"
  value = {
    for name in local.node_names :
    name => try(sakuracloud_server.nodes[name].ip_address, null)
  }
}

output "node_private_ips" {
  description = "各ノードの内部 IP アドレス"
  value = {
    for name in local.node_names :
    name => try(sakuracloud_server.nodes[name].network_interface[1].user_ip_address, null)
  }
}

output "lb_global_ip" {
  description = "ロードバランサのグローバル IP (VIP)"
  value       = local.lb_vip_ip
}

output "packet_filter_id" {
  description = "パブリック NIC 用パケットフィルタ ID (packet_filter_ssh_allow/deny ロールで SSH 許可ルールの追加・削除に使用)"
  value       = sakuracloud_packet_filter.public.id
}

output "ssh_public_key_openssh" {
  description = "Terraform が生成した SSH 公開鍵 (OpenSSH 形式)"
  value       = tls_private_key.ssh_key.public_key_openssh
}

output "lb_gateway" {
  description = "LB ルータのデフォルトゲートウェイ IP"
  value       = data.sakuracloud_internet.lb_router.gateway
}

output "lb_netmask" {
  description = "LB ルータのプレフィックス長"
  value       = data.sakuracloud_internet.lb_router.netmask
}

output "domain" {
  description = "Cloudflare で管理するゾーン名"
  value       = var.domain
}

output "auto_shutdown_at_utc" {
  description = "自動シャットダウンの時刻 (UTC)。空文字列の場合は無効。"
  value       = var.auto_shutdown_at_utc
}

output "lb_id" {
  description = "さくらのクラウド ロードバランサ ID"
  value       = sakuracloud_load_balancer.lb.id
}

output "sakura_region" {
  description = "さくらのクラウド リージョン"
  value       = var.sakura_region
}
