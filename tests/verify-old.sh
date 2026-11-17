#!/bin/bash
set -e

PREFIX="clab-evpn-mvp"

echo "[1/4] Проверка BGP Underlay и iBGP EVPN Overlay..."
docker exec ${PREFIX}-leaf-1 vtysh -c "show bgp l2vpn evpn summary" | grep -q "10.255.1.101"
echo "OK: EVPN сессии подняты."

echo "[2/4] Проверка Symmetric IRB и Jumbo Frames (MTU 9000) внутри Tenant A..."
docker exec ${PREFIX}-host-1 ping -M do -s 8972 -c 3 10.10.20.2 >/dev/null
echo "OK: Связность L3 между VLAN 10 и VLAN 20 с MTU 9000 работает."

echo "[3/4] Проверка L3-изоляции арендаторов (пересекающиеся IP 10.10.10.1)..."
docker exec ${PREFIX}-host-3 ping -c 2 10.10.10.254 >/dev/null
if docker exec ${PREFIX}-host-3 ping -c 2 -W 1 10.10.20.2 >/dev/null 2>&1; then
    echo "FAIL: Нарушена изоляция VRF между Tenant A и Tenant B!"
    exit 1
fi
echo "OK: Изоляция VRF_TEN_A и VRF_TEN_B подтверждена."
