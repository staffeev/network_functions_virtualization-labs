#!/bin/bash
set -e

STUDENT="${STUDENT:-stafeev}"
N="${N:-26}"
VNFFG_FILE="${1:-vnffg_only_fw1.yaml}"

if [ ! -f "$VNFFG_FILE" ]; then
    echo "Error: file '$VNFFG_FILE' not found."
    echo "Usage: ./switch_vnffg.sh [vnffg_only_fw1.yaml|vnffg_fw1_fw2.yaml|vnffg_healing.yaml]"
    exit 1
fi

SW="clab-$STUDENT-l6-sw"
FW1="clab-$STUDENT-l6-fw1"
FW2="clab-$STUDENT-l6-fw2"

echo "[1/4] Cleaning up existing VNF containers and ports..."
# Always clean up fw1
docker rm -f $FW1 >/dev/null 2>&1 || true
docker exec $SW ovs-vsctl --if-exists del-port br0 eth3 -- --if-exists del-port br0 eth4 >/dev/null 2>&1 || true

# Always clean up fw2 to prevent Docker name conflicts
docker rm -f $FW2 >/dev/null 2>&1 || true
docker exec $SW ovs-vsctl --if-exists del-port br0 eth5 -- --if-exists del-port br0 eth6 >/dev/null 2>&1 || true

echo "[2/4] Instantiating required VNFs..."
echo "  Instantiating fw1..."
./vnfm.sh instantiate fw1 fw 3 4

if grep -q "fw2" "$VNFFG_FILE"; then
    echo "  Instantiating fw2..."
    ./vnfm.sh instantiate fw2 fw 5 6
else
    echo "  fw2 not required for this config, left removed."
fi

echo "[3/4] Applying configuration: $VNFFG_FILE..."
python3 nfvo.py apply "$VNFFG_FILE" 2>/dev/null

echo "[4/4] Verifying applied flows for stafeev-c1..."
python3 nfvo.py show "$VNFFG_FILE" 2>/dev/null | grep "stafeev-c1.*ip" | head -6

echo "Switch complete."