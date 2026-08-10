# ---------------------------------------------------------------
# omni.tf
#
# Sidero Talos Omni 上にクラスタを定義する。
#
# NOTE: Terraform Registry で現在公開されている siderolabs/omni provider は
# v0.1.0-alpha.3 のみ (2026-08 時点)。この版の omni_cluster リソースには
# cni / inline_manifest ブロックが無く、omni_join_config リソースも存在しない。
# そのため当初想定していた設計から以下のとおり変更している。
#   - CNI (Cilium): omni_config_patch で Talos machine config の
#     cluster.inlineManifests に埋め込み、ノード起動時に自動適用させる。
#   - ArgoCD 本体: インストールマニフェストが CRD 込みで ~2MB あり
#     machine config patch には収まらないため、omni_kubernetes_manifest
#     (Kubernetes API 経由で適用) を使う。
#   - SideroLink Join Config / インストールイメージの取得: provider が
#     対応していないため Terraform では行わず、ansible の boot_node role
#     から omnictl (jointoken/media) を直接呼び出して取得する。
# ---------------------------------------------------------------

provider "omni" {
  endpoint            = var.omni_endpoint
  service_account_key = var.omni_service_account_key
}

resource "omni_cluster" "main" {
  name = var.sakura_label_prefix
  # provider は "v" プレフィックス無しの semver を要求するため取り除く
  kubernetes_version = trimprefix(var.kubernetes_version, "v")
  talos_version      = trimprefix(var.talos_version, "v")
}

# ---------------------------------------------------------------
# コントロールプレーン用マシンセット
# NOTE: 実際にノードを割り当てる omni_machine_set_node は、ノードが
# SideroLink 経由で Omni に参加してマシン UUID が判明した後でないと
# 作成できない (この Terraform apply の時点では ID 不明)。
# ノード参加後に別途 terraform apply するか omnictl で割り当てること。
# ---------------------------------------------------------------
resource "omni_machine_set" "control_plane" {
  # role が "controlplane" の場合、name は自動採番されるため指定不可
  cluster = omni_cluster.main.name
  role    = "controlplane"
}

# ---------------------------------------------------------------
# コントロールプレーンへのノード割り当て
# omni_join_config / データソースが provider に無いため、omnictl で
# sakura.io/hostname ラベルからマシン UUID を検索して割り当てる。
# ノードが未 join の場合 (build-infra 直後など) は空文字列を返すため
# for_each でスキップされ、エラーにはならない。ノード join 後に
# 再度 terraform apply することでこのリソースが作成される。
# ---------------------------------------------------------------
data "external" "machine_ids" {
  for_each = toset(local.node_names)

  program = ["bash", "-c", <<-EOT
    id=$(omnictl get machinestatus -l 'sakura.io/hostname=${each.key},omni.sidero.dev/connected' -o jsonpath='{.metadata.id}' 2>/dev/null | head -n 1 || true)
    if [ -z "$id" ]; then
      id=$(omnictl get machinestatus -l 'sakura.io/hostname=${each.key}' -o jsonpath='{.metadata.id}' 2>/dev/null | head -n 1 || true)
    fi
    jq -n --arg id "$id" '{id: $id}'
  EOT
  ]
}

resource "omni_machine_set_node" "control_plane" {
  for_each = { for name, ds in data.external.machine_ids : name => ds.result.id if ds.result.id != "" }

  cluster     = omni_cluster.main.name
  machine_set = omni_machine_set.control_plane.name
  machine_id  = each.value

  depends_on = [sakuracloud_server.nodes]
}

# ---------------------------------------------------------------
# Cilium (CNI) の Helm chart を Talos 公式ドキュメント推奨値
# (kube-proxy レス構成) でレンダリングし、Talos machine config の
# inline manifest として埋め込む。
# ---------------------------------------------------------------
data "helm_template" "cilium" {
  name         = "cilium"
  repository   = "https://helm.cilium.io/"
  chart        = "cilium"
  version      = "1.20.0"
  namespace    = "kube-system"
  kube_version = trimprefix(var.kubernetes_version, "v")

  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }
  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }
  set {
    name  = "k8sServiceHost"
    value = "localhost"
  }
  set {
    name  = "k8sServicePort"
    value = "7445"
  }
  set {
    name  = "cgroup.autoMount.enabled"
    value = "false"
  }
  set {
    name  = "cgroup.hostRoot"
    value = "/sys/fs/cgroup"
  }
  set {
    name  = "securityContext.capabilities.ciliumAgent"
    value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
  }
  set {
    name  = "securityContext.capabilities.cleanCiliumState"
    value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
  }
}

resource "omni_config_patch" "cilium" {
  name    = "cilium-cni"
  cluster = omni_cluster.main.name

  data = <<EOT
cluster:
  network:
    cni:
      name: none
  inlineManifests:
    - name: cilium
      contents: |
        ${indent(8, data.helm_template.cilium.manifest)}
EOT
}

resource "omni_config_patch" "internal_network" {
  name    = "internal-network"
  cluster = omni_cluster.main.name

  data = <<EOT
machine:
  kubelet:
    nodeIP:
      validSubnets:
        - 192.168.100.0/24
cluster:
  allowSchedulingOnControlPlanes: true
  etcd:
    advertisedSubnets:
      - 192.168.100.0/24
EOT
}

output "omni_cluster_id" {
  description = "Omni クラスタ名 (この provider 版では名前がリソース ID を兼ねる)"
  value       = omni_cluster.main.name
}

output "omni_endpoint" {
  description = "Omni エンドポイント URL"
  value       = var.omni_endpoint
}
