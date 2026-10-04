#!/bin/bash
sudo tee /usr/share/sonic/device/x86_64-kvm_x86_64-r0/Force10-S6000/port_config.ini > /dev/null <<'EOF'
# name          lanes             alias             index       speed
Ethernet0       25,26,27,28       fortyGigE0/0      0           40000
Ethernet4       29,30,31,32       fortyGigE0/4      1           40000
Ethernet8       33,34,35,36       fortyGigE0/8      2           40000
Ethernet12      37,38,39,40       fortyGigE0/12     3           40000
Ethernet16      45,46,47,48       fortyGigE0/16     4           40000
EOF
sudo python3 - <<'PY'
import json

path = "/etc/sonic/config_db.json"

keep = {
    "Ethernet0",
    "Ethernet4",
    "Ethernet8",
    "Ethernet12",
    "Ethernet16",
}

with open(path) as f:
    d = json.load(f)

d.pop("BGP_NEIGHBOR", None)

ports = d.get("PORT", {})

d["PORT"] = {
    name: value
    for name, value in ports.items()
    if name in keep
}

d.pop("INTERFACE", None)

with open(path, "w") as f:
    json.dump(d, f, indent=4)
    f.write("\n")

print("PORT:")
for name in d["PORT"]:
    print(" ", name)

print("\nPORT count:", len(d["PORT"]))
print("\nINTERFACE:", "removed")
print("\nBGP_NEIGHBOR:", "removed")
PY
sudo config interface ip add Ethernet0 10.0.0.1/24
sudo config interface startup Ethernet0
sudo config vlan add 10
sudo config vlan member add -u 10 Ethernet4
sudo config vxlan add Vxlan1 10.0.0.1
sudo config vxlan map add Vxlan1 10 1000
sudo bridge fdb append 00:00:00:00:00:00 dev Vxlan1-10 dst 10.0.0.2 self permanent
sudo config save -y