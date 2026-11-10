#!/bin/bash
set -e

echo "Waiting for SONiC services (Redis) to be ready..."
until redis-cli ping > /dev/null 2>&1; do
    sleep 2
done
sleep 15

echo "Starting FRR daemons..."
supervisorctl start zebra mgmtd staticd bgpd >/dev/null 2>&1 || true

echo "Configuring interfaces..."
config interface startup Ethernet0
config interface startup Ethernet4
config interface ip add Ethernet0 10.26.100.1/24
config interface ip add Ethernet4 10.26.1.1/30

echo "Removing default management route..."
ip route del default dev eth0 2>/dev/null || true

echo "Applying BGP configuration..."
if [ -f /tmp/dc1-frr.conf ]; then
    vtysh -f /tmp/dc1-frr.conf
    echo "BGP configuration applied successfully."
else
    echo "File /tmp/dc1-frr.conf not found."
    exit 1
fi

echo "dc1 configuration completed."