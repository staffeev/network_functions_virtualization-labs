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

d["INTERFACE"] = {
    name: value
    for name, value in d.get("INTERFACE", {}).items()
    if name.split("|")[0] in keep
}

with open(path, "w") as f:
    json.dump(d, f, indent=4)
    f.write("\n")

print("PORT:")
for name in d["PORT"]:
    print(" ", name)

print("\nPORT count:", len(d["PORT"]))

print("\nINTERFACE:")
for name in d["INTERFACE"]:
    print(" ", name)

print("\nINTERFACE count:", len(d["INTERFACE"]))
