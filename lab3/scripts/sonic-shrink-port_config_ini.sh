#!/bin/bash
sudo tee /usr/share/sonic/device/x86_64-kvm_x86_64-r0/Force10-S6000/port_config.ini > /dev/null <<'EOF'
# name          lanes             alias             index       speed
Ethernet0       25,26,27,28       fortyGigE0/0      0           40000
Ethernet4       29,30,31,32       fortyGigE0/4      1           40000
Ethernet8       33,34,35,36       fortyGigE0/8      2           40000
Ethernet12      37,38,39,40       fortyGigE0/12     3           40000
Ethernet16      45,46,47,48       fortyGigE0/16     4           40000
EOF