#!/bin/bash
set -e

STUDENT=${STUDENT:-stafeev}
N=${N:-26}
ODL="http://10.104.${N}.100:8181"
FLOWS_DIR="$(dirname "$0")/../flows"

echo "=================================================="
echo "[ DELETING ALL FLOWS ]"
echo "=================================================="
echo "Target ODL : $ODL"
echo "Flows dir  : $FLOWS_DIR"
echo "=================================================="

if [ ! -d "$FLOWS_DIR" ]; then
    echo "Error: Directory $FLOWS_DIR not found!"
    exit 1
fi

echo "Found files in directory:"
ls -1 "$FLOWS_DIR"/*.json 2>/dev/null || echo "  No .json files found!"
echo "--------------------------------------------------"

SUCCESS=0
FAILED=0

for flow_file in "$FLOWS_DIR"/*.json; do
    [ -e "$flow_file" ] || continue

    flow_id=$(basename "$flow_file" .json)

    # Пропускаем реактивный table-miss, если он вдруг там есть
    if [[ "$flow_id" == *"table-miss-reactive"* ]]; then
        echo "  [-] Skipping: $flow_id (reactive only)"
        continue
    fi

    # Определяем узел по имени файла
    if [[ "$flow_id" == *"s1"* ]] || [[ "$flow_id" == *"acl"* ]]; then
        node=1
    elif [[ "$flow_id" == *"s2"* ]]; then
        node=2
    else
        echo "  [-] Skipping: '$flow_id' (filename MUST contain 's1', 's2', or 'acl')"
        continue
    fi

    echo -n "  -> Deleting $flow_id from node $node... "
    
    http_code=$(curl -s -u admin:admin -X DELETE -o /dev/null -w "%{http_code}" \
        "$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A${node}/flow-node-inventory:table=0/flow=$flow_id")
    
    # ИСПРАВЛЕНО: безопасный инкремент, который не ломает set -e
    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "204" ]]; then
        echo "OK ($http_code)"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "FAILED ($http_code)"
        FAILED=$((FAILED + 1))
    fi
done

echo "=================================================="
echo "DONE! Successfully deleted: $SUCCESS, Failed: $FAILED"
echo "=================================================="