#!/usr/bin/env python3

"""Учебный мини-NFVO: читает описание цепочек (VNFFG) из YAML и программирует
OVS через OpenDaylight (RESTCONF RFC 8040).

  python3 nfvo.py apply  vnffg.yaml   # создать/обновить потоки всех цепочек
  python3 nfvo.py show   vnffg.yaml   # потоки и счётчики пакетов
  python3 nfvo.py delete vnffg.yaml   # удалить все потоки, созданные nfvo (id начинается с sfc-)
  python3 nfvo.py watch vnffg.yaml   # автоматическое восстановление VNF

Роль в архитектуре ETSI NFV MANO: упрощённый NFVO, который по описанию VNFFG
программирует сеть через SDN-контроллер (OpenDaylight).
"""

import os
import sys
import time
import subprocess
import requests
import yaml


PRIORITY = 300


def load(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(os.path.expandvars(f.read()))


class Odl:
    def __init__(self, cfg):
        c = cfg["controller"]
        self.base = c["url"].rstrip("/") + "/rests/data/opendaylight-inventory:nodes"
        self.auth = (c["user"], c["password"])
        self.node = cfg["switch"]
        self.node_q = self.node.replace(":", "%3A")
        self.headers = {"Accept": "application/json"}
        self.proxies = {"http": None, "https": None}

    def table_url(self, flow_id=None):
        url = f"{self.base}/node={self.node_q}/flow-node-inventory:table=0"
        return url + (f"/flow={flow_id}" if flow_id else "")

    def put_flow(self, flow):
        for attempt in range(3):
            try:
                r = requests.put(self.table_url(flow["id"]), auth=self.auth, timeout=10,
                                 headers=self.headers, json={"flow-node-inventory:flow": [flow]},
                                 proxies=self.proxies)
                r.raise_for_status()
                return r.status_code
            except requests.exceptions.HTTPError as e:
                if e.response.status_code == 503 and attempt < 2:
                    print(f"    [!] ODL returned 503, waiting 2s and retrying... (attempt {attempt+1}/3)")
                    time.sleep(2)
                else:
                    raise

    def list_flows(self, content="config"):
        r = requests.get(self.table_url() + f"?content={content}", auth=self.auth, timeout=10,
                         headers=self.headers, proxies=self.proxies)
        if r.status_code in (409, 204):
            return []
        r.raise_for_status()
        if not r.text or not r.text.strip():
            return []
        try:
            data = r.json()
            return data.get("flow-node-inventory:table", [{}])[0].get("flow", [])
        except Exception:
            return []

    def delete_flow(self, flow_id):
        requests.delete(self.table_url(flow_id), auth=self.auth, timeout=10,
                        headers=self.headers, proxies=self.proxies).raise_for_status()


def make_flow(flow_id, in_port, node, out_port, ip, ip_field, arp_field):
    out = {"instructions": {"instruction": [{"order": 0, "apply-actions": {"action": [
        {"order": 0, "output-action": {"output-node-connector": str(out_port)}}]}}]}}

    ipv4 = {"id": flow_id + "-ip", "table_id": 0, "priority": PRIORITY,
            "match": {"in-port": f"{node}:{in_port}",
                      "ethernet-match": {"ethernet-type": {"type": 2048}},
                      ip_field: f"{ip}/32"}, **out}

    arp = {"id": flow_id + "-arp", "table_id": 0, "priority": PRIORITY,
           "match": {"in-port": f"{node}:{in_port}",
                     "ethernet-match": {"ethernet-type": {"type": 2054}},
                     arp_field: f"{ip}/32"}, **out}

    return [ipv4, arp]


def build_flows(cfg):
    node, vnfs, ends = cfg["switch"], cfg["vnfs"], cfg["endpoints"]
    flows = []

    for ch in cfg["chains"]:
        src = ends[ch["from"]]
        dst = ends[ch["to"]]
        hops = [vnfs[name] for name in ch["path"]]

        fwd = [src["port"]] + [p for h in hops for p in (h["in"], h["out"])] + [dst["port"]]

        for i in range(0, len(fwd), 2):
            flows += make_flow(f"sfc-{ch['name']}-fwd{i // 2}", fwd[i], node, fwd[i + 1],
                               src["ip"], "ipv4-source", "arp-source-transport-address")

        rev = list(reversed(fwd))

        for i in range(0, len(rev), 2):
            flows += make_flow(f"sfc-{ch['name']}-rev{i // 2}", rev[i], node, rev[i + 1],
                               src["ip"], "ipv4-destination", "arp-target-transport-address")

    return flows


def is_port_up(odl, port_num):
    url = f"{odl.base}/node={odl.node_q}/node-connector=openflow%3A1%3A{port_num}?content=nonconfig"

    try:
        r = requests.get(url, auth=odl.auth, timeout=2, headers=odl.headers, proxies=odl.proxies)
        if r.status_code == 404:
            return False

        r.raise_for_status()
        data = r.json()
        connectors = data.get("opendaylight-inventory:node-connector", [])

        if not connectors:
            connectors = data.get("node-connector", [])

        if not connectors:
            return False

        state = connectors[0].get("flow-node-inventory:state", {})
        return state.get("live", True) and not state.get("link-down", False) and not state.get("blocked", False)

    except Exception:
        return False


def is_vnf_up(vnf_name):
    try:
        names = subprocess.check_output(["docker", "ps", "-a", "--format", "{{.Names}}"], text=True).splitlines()
        name = next((x for x in names if x.endswith(f"-l6-{vnf_name}")), None)

        if not name:
            return False

        return subprocess.check_output(["docker", "inspect", "-f", "{{.State.Running}}", name],
                                       text=True).strip() == "true"
    except Exception:
        return False


def watch_loop(cfg_path, odl, cfg):
    print(f"[*] Starting automatic monitoring (interval 2 sec)...")
    print(f"[*] Watching VNFs with 'standby' field in {cfg_path}")

    watched = {}

    for vnf_name, vnf_data in cfg.get("vnfs", {}).items():
        if "standby" in vnf_data:
            watched[vnf_name] = {"in_port": vnf_data["in"], "standby": vnf_data["standby"]}

    if not watched:
        print("[!] No VNFs with 'standby' field found in vnffg.yaml.")
        return

    failed_vnfs = set()

    try:
        while True:
            for vnf_name, info in watched.items():
                if vnf_name in failed_vnfs:
                    continue

                port = info["in_port"]
                standby = info["standby"]

                if not is_vnf_up(vnf_name) or not is_port_up(odl, port):
                    print(f"\n[!] FAILURE DETECTED: VNF '{vnf_name}' (port {port} is down)!")
                    print(f"[*] Starting automatic Heal: switching chains to '{standby}'...")

                    heal_cfg = load(cfg_path)
                    changed = False

                    for chain in heal_cfg.get("chains", []):
                        if vnf_name in chain["path"]:
                            idx = chain["path"].index(vnf_name)
                            chain["path"][idx] = standby
                            changed = True
                            print(f"    -> Chain '{chain['name']}' updated: path={chain['path']}")

                    if changed:
                        print("[*] Reprogramming OpenFlow flows...")

                        for f in odl.list_flows():
                            if f["id"].startswith("sfc-"):
                                odl.delete_flow(f["id"])

                        wanted = build_flows(heal_cfg)

                        for f in wanted:
                            odl.put_flow(f)

                        print(f"[+] Heal completed! Applied {len(wanted)} flows.")
                        failed_vnfs.add(vnf_name)

            time.sleep(2)

    except KeyboardInterrupt:
        print("\n[*] Monitoring stopped by user.")


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("apply", "show", "delete", "watch"):
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]
    cfg_path = sys.argv[2] if len(sys.argv) > 2 else "vnffg.yaml"
    cfg = load(cfg_path)
    odl = Odl(cfg)

    if cmd == "apply":
        wanted = build_flows(cfg)
        wanted_ids = {f["id"] for f in wanted}

        for f in wanted:
            odl.put_flow(f)

        stale = [f["id"] for f in odl.list_flows()
                 if f["id"].startswith("sfc-") and f["id"] not in wanted_ids]

        for fid in stale:
            odl.delete_flow(fid)

        print(f"applied: {len(wanted)} flows, removed stale: {len(stale)}")

    elif cmd == "show":
        for f in sorted(odl.list_flows("nonconfig"), key=lambda x: x.get("id", "")):
            st = f.get("opendaylight-flow-statistics:flow-statistics", {})
            m = f.get("match", {})
            print(f"{f.get('id', '?'):28} prio={f.get('priority')} in={m.get('in-port', '*'):14} "
                  f"pkts={st.get('packet-count', '0')}")

    elif cmd == "delete":
        ids = [f["id"] for f in odl.list_flows() if f["id"].startswith("sfc-")]

        for fid in ids:
            odl.delete_flow(fid)

        print(f"deleted: {len(ids)} flows")

    elif cmd == "watch":
        watch_loop(cfg_path, odl, cfg)


if __name__ == "__main__":
    main()