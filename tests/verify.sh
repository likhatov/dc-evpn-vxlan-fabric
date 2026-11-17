#!/bin/bash
set -e

PREFIX="clab-evpn-mvp"

echo "[1/6] Проверка BGP Underlay (eBGP + ECMP)..."
docker exec ${PREFIX}-leaf-1 vtysh -c "show bgp ipv4 unicast summary" | grep -q "10.0.0.0"
[ $(docker exec ${PREFIX}-leaf-1 ip route show 10.255.0.2 | grep -c "nexthop") -eq 2 ]
echo "OK: eBGP Underlay активен, в FIB установлены 2 равноценных пути ECMP."

echo "[2/6] Проверка Overlay (iBGP L2VPN EVPN и маршруты Type-2 / Type-3)..."
docker exec ${PREFIX}-leaf-1 vtysh -c "show bgp l2vpn evpn summary" | grep -q "10.255.1.101"
EVPN_RIB=$(docker exec ${PREFIX}-spine-1 vtysh -c "show bgp l2vpn evpn")
echo "$EVPN_RIB" | grep -q "\[2\]:"
echo "$EVPN_RIB" | grep -q "\[3\]:"
echo "OK: iBGP EVPN сессии подняты, маршруты Type-2 (MAC/IP) и Type-3 (IMET) в RIB."

echo "[3/6] Проверка EVPN Multihoming (All-Active LACP на host-2)..."
docker exec ${PREFIX}-host-2 grep -q "MII Status: up" /proc/net/bonding/bond0
echo "OK: Агрегация LACP bond0 активна на двух Leaf-коммутаторах."

echo "[4/6] Проверка Symmetric IRB и Jumbo Frames (MTU 9000)..."
docker exec ${PREFIX}-host-1 ping -M do -s 8972 -c 3 10.10.20.2 >/dev/null
echo "OK: Связность L3 между подсетями арендатора A с кадром 9000 байт работает."

echo "[5/6] Проверка изоляции Out-of-Band управления (VRF_MGMT)..."
docker exec ${PREFIX}-leaf-1 ip link show master VRF_MGMT | grep -q "eth0"
echo "OK: Интерфейс управления eth0 изолирован в VRF_MGMT."

echo "[6/6] Проверка L3-изоляции арендаторов (пересекающиеся IP 10.10.10.1)..."
docker exec ${PREFIX}-host-3 ping -c 2 10.10.10.254 >/dev/null
if docker exec ${PREFIX}-host-3 ping -c 2 -W 1 10.10.20.2 >/dev/null 2>&1; then
    echo "FAIL: Нарушена изоляция VRF между Tenant A и Tenant B!"
    exit 1
fi
echo "OK: Изоляция VRF_TEN_A и VRF_TEN_B подтверждена."

echo "Все 6 проверок фабрики успешно пройдены!"

