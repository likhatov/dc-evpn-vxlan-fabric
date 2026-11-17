#!/bin/bash
set -e
ip addr add 10.255.0.101/32 dev lo
ip link add lo1 type dummy && ip link set lo1 up
ip addr add 10.255.1.101/32 dev lo1

ip link set eth1 mtu 9216 up && ip addr add 10.0.0.0/31 dev eth1
ip link set eth2 mtu 9216 up && ip addr add 10.0.0.2/31 dev eth2

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.fib_multipath_hash_policy=1

