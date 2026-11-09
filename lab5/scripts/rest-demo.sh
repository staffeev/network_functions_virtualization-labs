#!/bin/bash
HQ=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clab-stafeev-l5-hq)

echo "=== GET /system/identity ==="
curl -s -u admin:admin http://$HQ/rest/system/identity | jq

echo -e "\n=== GET /ip/address ==="
curl -s -u admin:admin http://$HQ/rest/ip/address | jq -r '.[] | "\(.address)\t\(.interface)"'

echo -e "\n=== GET /routing/bgp/session ==="
curl -s -u admin:admin http://$HQ/rest/routing/bgp/session | jq

echo -e "\n=== PUT (create address-list) ==="
curl -s -u admin:admin -X PUT http://$HQ/rest/ip/firewall/address-list \
  -H "content-type: application/json" -d '{"list":"lab","address":"192.0.2.26","comment":"stafeev"}' | jq

echo -e "\n=== GET (find created entry) ==="
ID=$(curl -s -u admin:admin "http://$HQ/rest/ip/firewall/address-list?list=lab" | jq -r '.[0].".id"')
echo "Created ID: $ID"

echo -e "\n=== PATCH (update comment) ==="
curl -s -u admin:admin -X PATCH http://$HQ/rest/ip/firewall/address-list/$ID \
  -H "content-type: application/json" -d '{"comment":"patched by REST"}' | jq

echo -e "\n=== DELETE ==="
curl -s -u admin:admin -X DELETE http://$HQ/rest/ip/firewall/address-list/$ID -w "HTTP Status: %{http_code}\n"