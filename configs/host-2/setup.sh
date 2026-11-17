#!/bin/bash
set -e

ip link add bond0 type bond mode 802.3ad lacp_rate fast miimon 100 xmit_hash_policy layer3+4
ip link set eth1 down
ip link set eth1 master bond0
ip link set eth2 down
ip link set eth2 master bond0
ip link set bond0 mtu 9000 up
ip addr add 10.10.20.2/24 dev bond0
ip route del default
ip route add default via 10.10.20.254

