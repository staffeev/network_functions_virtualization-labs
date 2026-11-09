# 2026-11-09 23:48:07 by RouterOS 7.23.8
# system id = l2tHLzWXdtI
#
/interface ethernet set [ find default-name=ether1 ] disable-running-check=no
/interface ethernet set [ find default-name=ether2 ] disable-running-check=no
/interface ethernet set [ find default-name=ether3 ] disable-running-check=no
/interface wireguard add listen-port=13026 mtu=1420 name=wg-hq
/interface wireguard peers add allowed-address=10.26.254.1/32,10.26.100.0/24 endpoint-address=100.64.1.2 endpoint-port=13026 interface=wg-hq name=peer1 persistent-keepalive=25s public-key="370GV0rxy7dv+WRhKBiOiNhjGCoEWTIpoJzQ3WnvRGc="
/ip address add address=172.31.255.30/30 interface=ether1 network=172.31.255.28
/ip address add address=100.64.2.2/30 comment=WAN interface=ether2 network=100.64.2.0
/ip address add address=10.26.200.1/24 comment=LAN interface=ether3 network=10.26.200.0
/ip address add address=10.26.254.2/30 interface=wg-hq network=10.26.254.0
/ip dhcp-client add interface=ether1 name=client1
/ip firewall nat add action=masquerade chain=srcnat comment="branch -> Internet" out-interface=ether2
/ip route add comment="ISP default" dst-address=0.0.0.0/0 gateway=100.64.2.1
/ip route add dst-address=10.26.100.0/24 gateway=wg-hq
/system identity set name=br-stafeev
