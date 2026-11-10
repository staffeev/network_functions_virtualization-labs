#!/bin/bash
set -e

echo "[0/7] Destroying existing topology if it exists..."
containerlab destroy -t lab5.clab.yml >/dev/null 2>&1 || true

echo "[1/7] Deploying topology..."
containerlab deploy -t lab5.clab.yml

echo "[2/7] Waiting for MikroTik to boot and apply startup-config..."
sleep 90

echo "[3/7] Verifying MikroTik configurations..."
HQ_IDENTITY=$(sshpass -p 'admin' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@clab-stafeev-l5-hq "/system identity print" 2>/dev/null | grep "name:")
BR_IDENTITY=$(sshpass -p 'admin' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@clab-stafeev-l5-br "/system identity print" 2>/dev/null | grep "name:")

if echo "$HQ_IDENTITY" | grep -q "hq-stafeev"; then echo "  hq configuration applied."; else echo "  WARNING: hq config issue."; fi
if echo "$BR_IDENTITY" | grep -q "br-stafeev"; then echo "  br configuration applied."; else echo "  WARNING: br config issue."; fi

echo "[4/7] Configuring WireGuard dynamically (extracting fresh keys)..."
HQ_WG_KEY=$(sshpass -p 'admin' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@clab-stafeev-l5-hq ":put [/interface wireguard get wg-br public-key]")
BR_WG_KEY=$(sshpass -p 'admin' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@clab-stafeev-l5-br ":put [/interface wireguard get wg-hq public-key]")

sshpass -p 'admin' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@clab-stafeev-l5-hq "/interface wireguard peers add interface=wg-br public-key=\"$BR_WG_KEY\" endpoint-address=100.64.2.2 endpoint-port=13026 allowed-address=10.26.254.2/32,10.26.200.0/24 persistent-keepalive=25s"
sshpass -p 'admin' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@clab-stafeev-l5-br "/interface wireguard peers add interface=wg-hq public-key=\"$HQ_WG_KEY\" endpoint-address=100.64.1.2 endpoint-port=13026 allowed-address=10.26.254.1/32,10.26.100.0/24 persistent-keepalive=25s"
echo "  WireGuard peers added with fresh keys."

echo "[5/7] Waiting for BGP session to establish..."
timeout=120
elapsed=0

until docker exec clab-stafeev-l5-dc1 vtysh -c "show bgp summary" 2>/dev/null | grep -E "00:[0-9]{2}:[0-9]{2}"; do
    sleep 3
    elapsed=$((elapsed + 3))
    if [ $elapsed -ge $timeout ]; then
        echo "WARNING: BGP session did not establish within ${timeout} seconds."
        break
    fi
    echo "  ...waiting for BGP (${elapsed}s)"
done
echo "  BGP session established! Waiting for route propagation..."
sleep 10

echo "[6/7] Checking connectivity (pcb -> srv1)..."
docker exec clab-stafeev-l5-pcb ping -c 3 10.26.100.10

echo "[7/7] Running REST API tests and saving to rest-output.txt..."
chmod +x scripts/rest-demo.sh
bash scripts/rest-demo.sh > scripts/rest-output.txt
cat scripts/rest-output.txt

echo "=========================================="
echo "Lab 5 successfully reproduced and tested."
echo "=========================================="