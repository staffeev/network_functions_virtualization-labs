#!/bin/bash
set -e

STUDENT=${STUDENT:-stafeev}
N=${N:-26}
ODL="http://10.104.${N}.100:8181"

echo "==========================="
echo "[ TO REACTIVE SWITCHING ]"
echo "==========================="

# 1. Отключаем контроллер от коммутаторов
echo "1. Disconnecting OVS from ODL..."
docker exec clab-${STUDENT}-l4-s1 ovs-vsctl del-controller br0
docker exec clab-${STUDENT}-l4-s2 ovs-vsctl del-controller br0

# 2. Жесткий перезапуск OpenDaylight для очистки состояния
echo "2. Restarting OpenDaylight container (wait ~45s)..."
docker restart clab-${STUDENT}-l4-odl
sleep 45

# 3. Устанавливаем нужные фичи для реактивного режима
echo "3. Installing reactive features..."
docker exec -t clab-${STUDENT}-l4-odl /opt/odl/bin/client \
  "feature:install odl-openflowplugin-flow-services-rest odl-restconf-openapi odl-l2switch-switch-rest"

# 4. Подключаем коммутаторы обратно
echo "4. Reconnecting OVS to ODL..."
docker exec clab-${STUDENT}-l4-s1 ovs-vsctl set-controller br0 tcp:10.104.${N}.100:6653
docker exec clab-${STUDENT}-l4-s2 ovs-vsctl set-controller br0 tcp:10.104.${N}.100:6653

# 5. Ждем установления OpenFlow сессии
echo "5. Waiting for OpenFlow handshake (15s)..."
sleep 15

# 6. Тестовый пинг для инициализации MAC-обучения
echo "6. Triggering MAC learning (ping h1 -> h2)..."
docker exec clab-${STUDENT}-l4-h1 ping -c 2 -W 1 10.${N}.4.2 || true

# 7. Показываем результат
echo "=================================================="
echo "Reactive flows on s1:"
docker exec clab-${STUDENT}-l4-s1 ovs-ofctl -O OpenFlow13 dump-flows br0
echo "=================================================="
echo "DONE! Reactive mode is active."