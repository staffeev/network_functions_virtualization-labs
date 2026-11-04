#!/bin/bash
set -e

STUDENT=${STUDENT:-stafeev}
N=${N:-26}
ODL="http://10.104.${N}.100:8181"
FLOWS_DIR="$(dirname "$0")/../flows"

# По умолчанию ACL не применяется. Если передан флаг --with-acl, применяем.
APPLY_ACL=false
if [ "$1" == "--with-acl" ]; then
    APPLY_ACL=true
fi

echo "=================================================="
echo "[ TO PROACTIVE SWITCHING ]"
if [ "$APPLY_ACL" = true ]; then
    echo "[!] MODE: With ACL (ping to h3 will be blocked)"
else
    echo "[-] MODE: Clean connectivity (ping to h3 will work)"
fi
echo "=================================================="

# 1. Отключаем контроллер от коммутаторов
echo "1. Disconnecting OVS from ODL..."
docker exec clab-${STUDENT}-l4-s1 ovs-vsctl del-controller br0
docker exec clab-${STUDENT}-l4-s2 ovs-vsctl del-controller br0

# 2. Жесткий перезапуск OpenDaylight
echo "2. Restarting OpenDaylight container (wait ~45s)..."
docker restart clab-${STUDENT}-l4-odl
sleep 45

# 3. Устанавливаем фичи для проактивного режима
echo "3. Installing proactive features..."
docker exec -t clab-${STUDENT}-l4-odl /opt/odl/bin/client \
  "feature:install odl-openflowplugin-flow-services-rest odl-openflowplugin-app-table-miss-enforcer odl-restconf-openapi"

# 4. Подключаем коммутаторы обратно
echo "4. Reconnecting OVS to ODL..."
docker exec clab-${STUDENT}-l4-s1 ovs-vsctl set-controller br0 tcp:10.104.${N}.100:6653
docker exec clab-${STUDENT}-l4-s2 ovs-vsctl set-controller br0 tcp:10.104.${N}.100:6653

# 5. Ждем установления OpenFlow сессии
echo "5. Waiting for OpenFlow handshake (15s)..."
sleep 15

# 6. Применяем все JSON-файлы из папки flows/
echo "6. Applying proactive flows..."
for flow_file in "$FLOWS_DIR"/*.json; do
    if [ -f "$flow_file" ]; then
        # Пропускаем реактивный table-miss, если он там завалялся
        if [[ "$(basename "$flow_file")" == *"table-miss-reactive"* ]]; then
            continue
        fi
        
        flow_id=$(jq -r '.["flow-node-inventory:flow"][0].id' "$flow_file")
        
        # Логика определения узла и обработки ACL
        if [[ "$flow_id" == "stafeev-acl-icmp-h3" ]]; then
            if [ "$APPLY_ACL" = true ]; then
                node=1
                echo "  [!] Applying ACL: $flow_id to node $node..."
            else
                echo "  [-] Skipping ACL: $flow_id (use --with-acl to enable)"
                continue
            fi
        elif [[ "$flow_id" == *"-s1-"* ]]; then
            node=1
        elif [[ "$flow_id" == *"-s2-"* ]]; then
            node=2
        else
            continue
        fi
        
        echo -n "  Putting $flow_id to node $node... "
        http_code=$(curl -s -u admin:admin -X PUT -H "Content-Type: application/json" -d @"$flow_file" -o /dev/null -w "%{http_code}" \
            "$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A${node}/flow-node-inventory:table=0/flow=$flow_id")
        
        if [[ "$http_code" == "201" ]] || [[ "$http_code" == "204" ]]; then
            echo "OK ($http_code)"
        else
            echo "FAILED ($http_code)"
        fi
    fi
done

# 7. Финальная проверка
echo "7. Verifying connectivity (ping h1 -> h3)..."
sleep 2
docker exec clab-${STUDENT}-l4-h1 ping -c 2 -W 1 10.${N}.4.3

echo "=================================================="
echo "DONE! Proactive mode is active and verified."
echo "=================================================="