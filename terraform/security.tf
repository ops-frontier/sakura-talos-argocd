# ---------------------------------------------------------------
# SSH 鍵ペア (オンデマンド生成)
# ---------------------------------------------------------------
resource "tls_private_key" "ssh_key" {
  algorithm = "ED25519"
}

# 秘密鍵をローカルに保存 (gitignore 対象)
resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.ssh_key.private_key_openssh
  filename        = "${path.module}/../.ssh/id_ed25519"
  file_permission = "0600"
}

resource "local_file" "ssh_public_key" {
  content         = tls_private_key.ssh_key.public_key_openssh
  filename        = "${path.module}/../.ssh/id_ed25519.pub"
  file_permission = "0644"
}

# さくらのクラウドに SSH 公開鍵を登録 (ディスク修正で使用)
resource "sakuracloud_ssh_key" "main" {
  name       = "${var.sakura_label_prefix}-ssh-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# ---------------------------------------------------------------
# Firewall Group
# ---------------------------------------------------------------
resource "sakuracloud_packet_filter" "public" {
  name        = "${var.sakura_label_prefix}-public"
  description = "パブリックNIC用 パケットフィルタ。インバウンドは HTTP/HTTPS のみ許可"
  # サーバに搭載される仮想NICに**着信**するパケットのみを制御する。つまり、サーバからの発信パケットは制御できない。

  # インバウンド HTTPS
  expression {
    protocol         = "tcp"
    destination_port = "443"
    allow            = true
    description      = "Inbound HTTPS"
  }

  # インバウンド HTTP
  expression {
    protocol         = "tcp"
    destination_port = "80"
    allow            = true
    description      = "Inbound HTTP"
  }

  # SSH は build-infra / boot 実行時に packet_filter_ssh_allow ロールが動的に追加し、
  # 完了後 packet_filter_ssh_deny ロールで解除する。デフォルトは閉じる。

  # IP フラグメントを許可 (大きなパケットの断片化対応)
  expression {
    protocol    = "fragment"
    allow       = true
    description = "IP fragment allow"
  }

  # ソフトウェアダウンロード用アウトバウンド HTTPS (レスポンス)
  expression {
    protocol         = "tcp"
    source_port      = "443"
    destination_port = "32768-60999"
    allow            = true
    description      = "outbound HTTPS"
  }

  # ソフトウェアダウンロード用アウトバウンド HTTP (レスポンス)
  expression {
    protocol         = "tcp"
    source_port      = "80"
    destination_port = "32768-60999"
    allow            = true
    description      = "outbound HTTP"
  }

  # DNS TCP outbound (レスポンス)
  expression {
    protocol         = "tcp"
    source_port      = "53"
    destination_port = "32768-60999"
    allow            = true
    description      = "DNS TCP outbound"
  }

  # DNS UDP outbound (レスポンス)
  expression {
    protocol         = "udp"
    source_port      = "53"
    destination_port = "32768-60999"
    allow            = true
    description      = "DNS UDP outbound"
  }

  # NTP UDP outbound (レスポンス)
  expression {
    protocol         = "udp"
    source_port      = "123"
    destination_port = "32768-60999"
    allow            = true
    description      = "NTP outbound"
  }

  # SideroLink (Omni WireGuard) アウトバウンド (レスポンス)
  # omnictl get connectionparams で確認した実際の WireGuard エンドポイント
  # ポート (UDP 49298) への戻りパケットを許可する。talos.events.sink 等の
  # [fdae:...]:8090 はこの WireGuard トンネル内部の仮想アドレスであり、
  # 物理NIC上のパケットフィルタには現れない。
  expression {
    protocol         = "udp"
    source_port      = "49298"
    destination_port = "32768-60999"
    allow            = true
    description      = "SideroLink (Omni WireGuard) outbound"
  }

  # ICMP 双方向
  expression {
    protocol    = "icmp"
    allow       = true
    description = "ICMP"
  }

  # その他すべて拒否
  expression {
    protocol    = "ip"
    allow       = false
    description = "default deny"
  }
}

# パブリックNICにパケットフィルタを適用 (各サーバの network_interface[0] に packet_filter_id を設定)
# → servers.tf の sakuracloud_server.nodes 内 NIC 0 ブロックで参照する
