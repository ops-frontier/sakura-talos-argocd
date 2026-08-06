#!/usr/bin/env python3
"""さくらのクラウド LB CNI コントローラ

Traefik Pod の起動・停止に連動して、さくらのクラウド LB のサーバ登録を動的に管理する。

【設計方針】
  Traefik は NodePort + externalIPs で動作しており、Cilium の kube-proxy replacement が
  全 Ready ノードで VIP / 実 IP 宛のトラフィックを Traefik pod へルーティングする。
  したがって LB には「全 Ready ノードの実 IP」を登録し、
  - ノードが Ready になったら LB に追加 (ヘルスチェック即時成功)
  - ノードが NotReady / cordon されたら LB から削除 (計画停止時のヘルスチェック失敗を防止)

環境変数:
  SAKURA_TOKEN           さくらのクラウド API アクセストークン (必須)
  SAKURA_SECRET          さくらのクラウド API アクセスシークレット (必須)
  SAKURA_REGION          さくらのクラウドリージョン (default: is1c)
  LB_ID                  ロードバランサ ID (必須)
  LB_VIP                 ロードバランサ VIP アドレス (必須)
  NODE_IPS_CONFIG_MAP    ノード名→公開 IP マッピング ConfigMap 名 (default: lb-controller-node-ips)
  NODE_IPS_NAMESPACE     ConfigMap の namespace (default: lb-controller)
  RECONCILE_INTERVAL     定期調整間隔(秒) (default: 30)
"""

import base64
import json
import logging
import os
import time
import urllib.error as urllib_error
import urllib.request as urllib_request
from threading import Event, Thread

from kubernetes import client as k8s_client
from kubernetes import config as k8s_config
from kubernetes import watch as k8s_watch

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("lb-controller")

# ── 設定 ──────────────────────────────────────────────────────────────
SAKURA_TOKEN = os.environ["SAKURA_TOKEN"]
SAKURA_SECRET = os.environ["SAKURA_SECRET"]
SAKURA_REGION = os.environ.get("SAKURA_REGION", "is1c")
LB_ID = os.environ["LB_ID"]
LB_VIP = os.environ["LB_VIP"]
NODE_IPS_CONFIG_MAP = os.environ.get("NODE_IPS_CONFIG_MAP", "lb-controller-node-ips")
NODE_IPS_NAMESPACE = os.environ.get("NODE_IPS_NAMESPACE", "lb-controller")
RECONCILE_INTERVAL = int(os.environ.get("RECONCILE_INTERVAL", "30"))

API_BASE = (
    f"https://secure.sakura.ad.jp/cloud/zone/{SAKURA_REGION}/api/cloud/1.1"
)

# VIP ポートごとのヘルスチェック設定 (Terraform の vip ブロックと一致させる)
_VIP_HC: dict[str, dict] = {
    "443": {"Protocol": "tcp",  "Path": "",  "Status": ""},
    "80":  {"Protocol": "http", "Path": "/", "Status": "301"},
}


# ── さくらのクラウド API ──────────────────────────────────────────────

def _sakura_request(
    method: str,
    path: str,
    payload: dict | None = None,
    retries: int = 5,
    retry_interval: int = 10,
) -> dict:
    """さくらのクラウド API へリクエストを送る。HTTP 423 はリトライする。"""
    url = f"{API_BASE}{path}"
    creds = base64.b64encode(
        f"{SAKURA_TOKEN}:{SAKURA_SECRET}".encode()
    ).decode()
    headers = {"Authorization": f"Basic {creds}"}
    data: bytes | None = None
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"

    for attempt in range(retries + 1):
        req = urllib_request.Request(
            url, data=data, headers=headers, method=method
        )
        try:
            with urllib_request.urlopen(req, timeout=60) as resp:
                body = resp.read()
                return json.loads(body) if body else {}
        except urllib_error.HTTPError as exc:
            if exc.code == 423 and attempt < retries:
                log.warning(
                    "API locked (423), retry %d/%d in %ds",
                    attempt + 1, retries, retry_interval,
                )
                time.sleep(retry_interval)
                continue
            body = exc.read().decode(errors="replace")
            raise RuntimeError(
                f"Sakura API {method} {url} → HTTP {exc.code}\n{body}"
            ) from exc
    raise RuntimeError(f"Sakura API {method} {url} → max retries reached")


def _get_lb_vip_settings() -> list[dict]:
    """LB の Settings.LoadBalancer リストを返す。"""
    # さくらのクラウドの LB は /appliance/{id} エンドポイントで管理される
    resp = _sakura_request("GET", f"/appliance/{LB_ID}")
    return resp["Appliance"]["Settings"]["LoadBalancer"]


def _sync_lb_servers(active_ips: frozenset[str]) -> bool:
    """LB_VIP の全ポートのサーバ一覧を active_ips に一致させる。変更時 True を返す。"""
    vip_settings = _get_lb_vip_settings()
    changed = False

    for vip_conf in vip_settings:
        if vip_conf["VirtualIPAddress"] != LB_VIP:
            continue

        port = str(vip_conf["Port"])
        hc = _VIP_HC.get(port, {"Protocol": "tcp", "Path": "", "Status": ""})

        current_ips = frozenset(
            s["IPAddress"] for s in vip_conf.get("Servers", [])
        )
        if current_ips == active_ips:
            log.debug("VIP %s:%s unchanged: %s", LB_VIP, port, sorted(active_ips))
            continue

        log.info(
            "VIP %s:%s update: %s → %s",
            LB_VIP, port, sorted(current_ips), sorted(active_ips),
        )
        vip_conf["Servers"] = [
            {
                "IPAddress": ip,
                "Port": port,
                "HealthCheck": hc,
                "Enabled": "True",
            }
            for ip in sorted(active_ips)
        ]
        changed = True

    if changed:
        _sakura_request(
            "PUT",
            f"/appliance/{LB_ID}",
            {"Appliance": {"Settings": {"LoadBalancer": vip_settings}}},
        )
        # 設定をハードウェアに適用 (POST ではなく PUT)
        _sakura_request("PUT", f"/appliance/{LB_ID}/config", {})
        log.info("LB config applied: active_ips=%s", sorted(active_ips))

    return changed


# ── Kubernetes ───────────────────────────────────────────────────────

def _get_node_ip_map(v1: k8s_client.CoreV1Api) -> dict[str, str]:
    """lb-controller-node-ips ConfigMap からノード名 → 公開 IP のマッピングを返す。"""
    try:
        cm = v1.read_namespaced_config_map(NODE_IPS_CONFIG_MAP, NODE_IPS_NAMESPACE)
        return dict(cm.data or {})
    except Exception:
        log.exception("Failed to read ConfigMap %s/%s", NODE_IPS_NAMESPACE, NODE_IPS_CONFIG_MAP)
        return {}


def _get_ready_node_ips(v1: k8s_client.CoreV1Api) -> frozenset[str]:
    """LB に登録すべき Ready ノードの公開 IP セットを返す。

    Cilium の kube-proxy replacement により、全 Ready ノードが Traefik へのトラフィックを
    ルーティングできる。cordon (unschedulable) ノードは計画停止中とみなし除外する。
    """
    nodes = v1.list_node()
    node_ip_map = _get_node_ip_map(v1)
    active_ips: set[str] = set()

    for node in nodes.items:
        # cordon (kubectl cordon) されているノードは計画停止中 → LB から除外
        if node.spec.unschedulable:
            log.debug("Node %s is cordoned, excluding from LB", node.metadata.name)
            continue

        # Ready 条件チェック
        is_ready = any(
            c.type == "Ready" and c.status == "True"
            for c in (node.status.conditions or [])
        )
        if not is_ready:
            log.debug("Node %s is not Ready, excluding from LB", node.metadata.name)
            continue

        node_name = node.metadata.name
        public_ip = node_ip_map.get(node_name)
        if public_ip:
            active_ips.add(public_ip)
        else:
            log.warning("Node %s not found in node-ips ConfigMap, skipping", node_name)

    return frozenset(active_ips)


# ── 調整ループ ──────────────────────────────────────────────────────

def _reconcile(v1: k8s_client.CoreV1Api) -> None:
    """LB の状態を Kubernetes の実態に一致させる。"""
    try:
        active_ips = _get_ready_node_ips(v1)
        log.debug("Ready node IPs: %s", sorted(active_ips))
        _sync_lb_servers(active_ips)
    except Exception:
        log.exception("Reconcile error (will retry on next cycle)")


def _watch_nodes(v1: k8s_client.CoreV1Api, trigger: Event) -> None:
    """Node の状態変化を監視し、変化があれば trigger をセットする。

    resourceVersion を追跡することで Watch 再接続時の重複イベントを防ぐ。
    """
    try:
        node_list = v1.list_node()
        resource_version = node_list.metadata.resource_version or ""
    except Exception:
        log.exception("Failed to list nodes for initial resourceVersion, starting from beginning")
        resource_version = ""

    while True:
        w = k8s_watch.Watch()
        try:
            for event in w.stream(
                v1.list_node,
                timeout_seconds=RECONCILE_INTERVAL,
                resource_version=resource_version,
            ):
                etype: str = event["type"]
                node = event["object"]
                if node.metadata.resource_version:
                    resource_version = node.metadata.resource_version
                ready = next(
                    (c.status for c in (node.status.conditions or []) if c.type == "Ready"),
                    "Unknown",
                )
                log.info(
                    "Node event: %s %s (Ready=%s, unschedulable=%s)",
                    etype, node.metadata.name, ready, node.spec.unschedulable,
                )
                trigger.set()
        except k8s_client.exceptions.ApiException as exc:
            if exc.status == 410:
                log.warning("Watch resourceVersion expired (410 Gone), resetting to current")
                resource_version = ""
            else:
                log.exception("Watch API error, restarting in 5s")
                time.sleep(5)
        except Exception:
            log.exception("Watch stream error, restarting in 5s")
            time.sleep(5)


def main() -> None:
    # クラスタ内外どちらでも動作するよう設定を自動選択
    try:
        k8s_config.load_incluster_config()
        log.info("Kubernetes: using in-cluster config")
    except k8s_config.ConfigException:
        k8s_config.load_kube_config()
        log.info("Kubernetes: using kubeconfig")

    v1 = k8s_client.CoreV1Api()
    trigger = Event()

    # Node 監視スレッドを起動
    watcher = Thread(target=_watch_nodes, args=(v1, trigger), daemon=True)
    watcher.start()

    log.info(
        "LB CNI controller started (LB_ID=%s, VIP=%s, interval=%ds)",
        LB_ID, LB_VIP, RECONCILE_INTERVAL,
    )

    # 起動直後に初回調整
    _reconcile(v1)

    while True:
        triggered = trigger.wait(timeout=RECONCILE_INTERVAL)
        trigger.clear()
        if triggered:
            log.debug("Triggered reconcile by node event")
        else:
            log.debug("Periodic reconcile")
        _reconcile(v1)


if __name__ == "__main__":
    main()
