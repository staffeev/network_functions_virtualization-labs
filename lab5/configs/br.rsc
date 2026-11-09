# Identity
/system identity set name=br-stafeev

# Адресация
/ip address add address=100.64.2.2/30 interface=ether2 comment="WAN"
/ip address add address=10.26.200.1/24 interface=ether3 comment="LAN"
/ip route add dst-address=0.0.0.0/0 gateway=100.64.2.1 comment="ISP default"