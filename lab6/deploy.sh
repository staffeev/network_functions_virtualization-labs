#!/bin/bash
set -e

STUDENT="${STUDENT:-stafeev}"
N="${N:-26}"
FW_PORT=$((8000 + N))
SHAPER_RATE=$((10 + N % 10))

VNFFG_FILE="${1:-vnffg_only_fw1.yaml}"

if [ ! -f "$VNFFG_FILE" ]; then
    echo "[ERROR] File '$VNFFG_FILE' not found!"
    echo "[INFO] Usage: ./deploy.sh [vnffg_file.yaml]"
    exit 1
fi

echo "[0/7] Destroying existing topology if it exists..."
containerlab destroy -t lab6.clab.yml --cleanup >/dev/null 2>&1 || true
sleep 2

echo "[1/7] Deploying topology..."
containerlab deploy -t lab6.clab.yml

echo "[2/7] Starting services on server (iperf3 + HTTP on port 80 and $FW_PORT)..."
docker exec -d clab-$STUDENT-l6-server iperf3 -s
docker exec -d clab-$STUDENT-l6-server python3 -m http.server 80 >/dev/null 2>&1 || true
docker exec -d clab-$STUDENT-l6-server python3 -m http.server $FW_PORT >/dev/null 2>&1 || true
sleep 3

echo "[3/7] Waiting for OpenDaylight controller to boot (~40 sec)..."
sleep 40

echo "[4/7] Installing ODL plugins and configuring OVS switch..."
docker exec -t clab-$STUDENT-l6-odl /opt/odl/bin/client \
  "feature:install odl-openflowplugin-flow-services-rest odl-openflowplugin-app-table-miss-enforcer" >/dev/null 2>&1 || true
sleep 5

docker exec -i -e ODL_IP=10.106.$N.100 clab-$STUDENT-l6-sw sh < scripts/sw-setup.sh >/dev/null 2>&1
sleep 10

ODL_STATUS=$(docker exec clab-$STUDENT-l6-sw ovs-vsctl show | grep -A1 Controller | grep "is_connected" | grep -o "true\|false" || echo "false")
if [ "$ODL_STATUS" = "true" ]; then
    echo "  ODL controller connected: OK"
else
    echo "  WARNING: ODL controller not connected (status: $ODL_STATUS)"
fi

echo "[5/7] Configuring VNFs (fw1 + shaper1)..."
./vnfm.sh configure fw1 fw
./vnfm.sh configure shaper1 shaper

if [[ "$VNFFG_FILE" == *"fw2"* ]] || [[ "$VNFFG_FILE" == *"healing"* ]]; then
    echo "  Instantiating fw2 automatically based on VNFFG file..."
    ./vnfm.sh instantiate fw2 fw 5 6
fi

echo "  Checking fw1 rules (should block port $FW_PORT)..."
docker exec clab-$STUDENT-l6-fw1 nft list ruleset | grep -q "dport $FW_PORT" && echo "    fw1: OK" || echo "    fw1: WARNING"

echo "  Checking shaper1 rate (should be ${SHAPER_RATE}Mbit)..."
docker exec clab-$STUDENT-l6-shaper1 tc qdisc show dev eth2 | grep -q "${SHAPER_RATE}Mbit" && echo "    shaper1: OK" || echo "    shaper1: WARNING"

echo "[6/7] Applying service chains via NFVO ($VNFFG_FILE)..."
python3 nfvo.py apply "$VNFFG_FILE" 2>/dev/null
sleep 3

echo "[7/7] Verifying connectivity..."
echo "  Testing ping (client1 -> server)..."
if docker exec clab-$STUDENT-l6-client1 ping -c 2 -W 1 10.$N.6.100 2>/dev/null | grep -q "0% packet loss"; then
    echo "    Ping: OK"
else
    echo "    Ping: FAILED (may need ARP cache flush)"
fi

echo "  Testing HTTP (port 80)..."
HTTP_CODE=$(docker exec clab-$STUDENT-l6-client1 curl -s -o /dev/null -w "%{http_code}" http://10.$N.6.100/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "    HTTP: OK (code $HTTP_CODE)"
else
    echo "    HTTP: FAILED or not ready (code $HTTP_CODE)"
fi

echo "  Testing blocked port ($FW_PORT)..."
BLOCK_CODE=$(docker exec clab-$STUDENT-l6-client1 curl -s -m 2 -o /dev/null -w "%{http_code}" http://10.$N.6.100:$FW_PORT/ 2>/dev/null || echo "000")
if [ "$BLOCK_CODE" = "000" ]; then
    echo "    Blocked port: OK (code $BLOCK_CODE)"
else
    echo "    Blocked port: FAILED (code $BLOCK_CODE)"
fi

echo ""
echo "=== Final Status ==="
./vnfm.sh list
echo ""
echo "=== OpenFlow flows for stafeev-c1 ==="
python3 nfvo.py show "$VNFFG_FILE" 2>/dev/null | grep "stafeev-c1.*ip" | head -6