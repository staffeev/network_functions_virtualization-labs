# Identity
/system identity set name=hq-stafeev

# Адресация
/ip address add address=10.26.1.2/30 interface=ether2 comment="to DC"
/ip address add address=100.64.1.2/30 interface=ether3 comment="WAN"
/ip route add dst-address=0.0.0.0/0 gateway=100.64.1.1 comment="ISP default"