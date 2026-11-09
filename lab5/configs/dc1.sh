docker exec -it clab-stafeev-l5-dc1 bash
supervisorctl start zebra mgmtd staticd bgpd >/dev/null 2>&1
sudo config interface startup Ethernet0
sudo config interface startup Ethernet4
sudo config interface ip add Ethernet0 10.26.100.1/24
sudo config interface ip add Ethernet4 10.26.1.1/30
ping -c 3 10.26.1.2
