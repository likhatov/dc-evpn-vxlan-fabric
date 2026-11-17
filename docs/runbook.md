# Эксплуатационный регламент (Runbook)

## 1. Развёртывание стенда

### Предварительные требования
* Linux-хост (Debian/Ubuntu) с установленными Docker и Containerlab.
* Загруженные модули ядра:
  ```bash
  sudo modprobe bonding vrf vxlan 8021q
  ```

### Запуск и остановка
```bash
# Развёртывание топологии
containerlab deploy -t topology.clab.yml

# Автоматическая проверка работоспособности
./tests/verify.sh

# Полная остановка и очистка ресурсов
containerlab destroy -t topology.clab.yml --cleanup
```

## 2. Процедуры проверки и диагностики

### Проверка Control Plane (Underlay eBGP и Overlay iBGP EVPN)
```bash
# 1. Underlay eBGP (IPv4 Unicast) — ожидается статус Established с цифрой префиксов
docker exec -it clab-evpn-mvp-leaf-1 vtysh -c "show bgp ipv4 unicast summary"

# 2. Overlay iBGP EVPN (L2VPN EVPN) — сессии с RR 10.255.1.101 и 10.255.1.102
docker exec -it clab-evpn-mvp-leaf-1 vtysh -c "show bgp l2vpn evpn summary"

# 3. Просмотр маршрутов EVPN на Spine (Type-1, Type-2, Type-3, Type-4)
docker exec -it clab-evpn-mvp-spine-1 vtysh -c "show bgp l2vpn evpn"
```

### Проверка EVPN Multihoming (All-Active LACP и DF Election)
```bash
# Проверка агрегации LACP на сервере host-2 (оба линка eth1 и eth2 должны быть UP)
docker exec -it clab-evpn-mvp-host-2 cat /proc/net/bonding/bond0

# Проверка статуса Ethernet Segment и выбора Designated Forwarder на Leaf
docker exec -it clab-evpn-mvp-leaf-1 vtysh -c "show evpn es"
docker exec -it clab-evpn-mvp-leaf-2 vtysh -c "show evpn es"
```

### Проверка Data Plane, Jumbo Frames (MTU 9000) и изоляции VRF
```bash
# 1. L3-маршрутизация Symmetric IRB внутри Tenant A (VLAN 10 -> VLAN 20) с кадром 9000 байт
docker exec -it clab-evpn-mvp-host-1 ping -M do -s 8972 -c 3 10.10.20.2

# 2. Проверка таблиц VRF в ядре Linux на leaf-2 (пересекающиеся сети 10.10.10.0/24)
docker exec -it clab-evpn-mvp-leaf-2 ip vrf show
docker exec -it clab-evpn-mvp-leaf-2 ip route show vrf VRF_TEN_A
docker exec -it clab-evpn-mvp-leaf-2 ip route show vrf VRF_TEN_B

# 3. Проверка изоляции Tenant B от Tenant A (ожидается 100% потерь)
docker exec -it clab-evpn-mvp-host-3 ping -c 2 -W 1 10.10.20.2
```

## 3. Процедура Graceful Shutdown одного Leaf (вывод в обслуживание)

Для плавного вывода `leaf-1` (обслуживающего dual-homed сервер `host-2`) без потери трафика:

1. **Активация BGP Graceful Shutdown (RFC 8326):**
   Отправляет соседям community `65535:0`, снижая `LOCAL_PREF` маршрутов через `leaf-1` до `0` и переводя транзитный трафик на `leaf-2`:
   ```bash
   docker exec -it clab-evpn-mvp-leaf-1 vtysh \
     -c "conf t" \
     -c "router bgp 65001" \
     -c "bgp graceful-shutdown"
   ```
2. **Проверка переключения Designated Forwarder на `leaf-2`:**
   ```bash
   docker exec -it clab-evpn-mvp-leaf-2 vtysh -c "show evpn es"
   ```
3. **Выключение клиентского бонда на `leaf-1` (для перестроения LACP на `host-2`):**
   ```bash
   docker exec -it clab-evpn-mvp-leaf-1 ip link set dev bond-h2 down
   ```
4. **Возврат в работу после обслуживания:**
   Поднять `bond-h2`, дождаться установления BGP-сессий и выполнить `no bgp graceful-shutdown`.

## 4. Особенности эксплуатации FRR 10.2 в контейнерной среде (Root Cause Notes)

При сборке и отладке стенда в среде Linux/Containerlab учтены следующие архитектурные нюансы:
1. **Маршрутизация SVI в Linux VLAN-aware bridge:** Помимо добавления VLAN на физические и VXLAN-порты, каждый VLAN должен быть явно зарегистрирован на самом интерфейсе моста (`bridge vlan add vid <VID> dev br0 self`), иначе ядро отбрасывает кадры, адресованные L3-интерфейсам `vlan<VID>`.
2. **Пиринг iBGP EVPN поверх eBGP Underlay:** Так как Leaf-коммутаторы работают в собственных автономных системах (`65001`, `65002`), для установления iBGP-сессии со Spine (`AS 65000`) используется `neighbor OVERLAY local-as 65000 no-prepend replace-as` с явным указанием IP-адреса источника (`update-source 10.255.1.x`).


