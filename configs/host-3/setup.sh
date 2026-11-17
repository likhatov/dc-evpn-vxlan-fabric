#!/bin/bash
set -e

ip link set eth1 mtu 9000 up
ip addr add 10.10.10.1/24 dev eth1
ip route del default
ip route add default via 10.10.10.254

