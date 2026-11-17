#!/bin/bash
set -e
# OOB VRF
ip link add VRF_MGMT type vrf table 1000 && ip link set VRF_MGMT up
ip link set eth0 master VRF_MGMT

# Loopbacks
ip addr add 10.255.0.2/32 dev lo
ip link add lo1 type dummy && ip link set lo1 up
ip addr add 10.255.1.2/32 dev lo1

# Uplinks + QoS TC
for iface in eth1 eth2; do
    ip link set $iface mtu 9216 up
    tc qdisc replace dev $iface root handle 1: prio bands 3
    tc filter add dev $iface protocol ip parent 1:0 prio 1 u32 match ip tos 0xb8 0xfc flowid 1:1
done
ip addr add 10.0.0.3/31 dev eth1
ip addr add 10.0.0.13/31 dev eth2

# Tenant VRFs
ip link add VRF_TEN_A type vrf table 101 && ip link set VRF_TEN_A up
ip link add VRF_TEN_B type vrf table 102 && ip link set VRF_TEN_B up

# VLAN-aware Bridge
ip link add br0 type bridge vlan_filtering 1 vlan_default_pvid 0 mcast_snooping 0
ip link set br0 mtu 9216 up

create_vxlan() {
    ip link add vxlan$1 type vxlan id $1 dstport 4789 local 10.255.0.2 nolearning tos inherit
    ip link set vxlan$1 mtu 9150 master br0 up
    bridge vlan add vid $2 dev vxlan$1 pvid untagged
    bridge link set dev vxlan$1 neigh_suppress on learning off
}

# L3 VNI 100100 (VRF_TEN_A) & L3 VNI 100200 (VRF_TEN_B)
create_vxlan 100100 4001
ip link add link br0 name vlan4001 type vlan id 4001
ip link set vlan4001 master VRF_TEN_A mtu 9100 up

create_vxlan 100200 4002
ip link add link br0 name vlan4002 type vlan id 4002
ip link set vlan4002 master VRF_TEN_B mtu 9100 up

# L2 VNI 10020 (VLAN 20 - Tenant A, вторая нога host-2) + Anycast GW
create_vxlan 10020 20
ip link add link br0 name vlan20 type vlan id 20
ip link set vlan20 master VRF_TEN_A mtu 9000 address 00:00:5e:00:01:20 up
ip addr add 10.10.20.254/24 dev vlan20

# L2 VNI 10030 (VLAN 30 - Tenant B, host-3 с пересекающейся сетью 10.10.10.0/24!)
create_vxlan 10030 30
ip link add link br0 name vlan30 type vlan id 30
ip link set vlan30 master VRF_TEN_B mtu 9000 address 00:00:5e:00:02:30 up
ip addr add 10.10.10.254/24 dev vlan30

# Port eth3 -> host-3 (VLAN 30, Tenant B)
ip link set eth3 mtu 9000 master br0 up
bridge vlan add vid 30 dev eth3 pvid untagged

# Port eth4 -> bond-h2 -> host-2 (EVPN Multihoming, VLAN 20, Tenant A)
ip link add bond-h2 type bond mode 802.3ad lacp_rate fast miimon 100 xmit_hash_policy layer3+4
ip link set bond-h2 mtu 9000
ip link set eth4 down && ip link set eth4 master bond-h2
ip link set bond-h2 master br0 up
bridge vlan add vid 20 dev bond-h2 pvid untagged

bridge vlan add vid 20 dev br0 self
bridge vlan add vid 30 dev br0 self
bridge vlan add vid 4001 dev br0 self
bridge vlan add vid 4002 dev br0 self

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.arp_accept=1

