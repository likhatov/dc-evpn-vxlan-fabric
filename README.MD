# Сетевая фабрика ЦОД на базе EVPN/VXLAN и FRR

Репозиторий содержит проект, конфигурации и воспроизводимый лабораторный стенд (Containerlab) сетевой инфраструктуры ЦОД для SaaS-платформы на стеке **FRRouting (FRR)** и **Linux Networking (`iproute2`)**.

## Архитектурный обзор

* **Топология:** 2-уровневая CLOS-фабрика (Full-Mesh Leaf-Spine). В лабораторном стенде развёрнут базовый отказоустойчивый кластер (**2 Spine × 2 Leaf × 3 Host**), на котором реализованы и протестированы все ключевые механизмы целевой архитектуры.
* **Underlay:** Маршрутизируемая фабрика на базе **eBGP** (уникальные приватные ASN на каждом Leaf и общий ASN `65000` на Spine) с BFD, ECMP и P2P-линками `/31`.
* **Overlay:** **iBGP L2VPN EVPN** (в единой `AS 65000` с Route Reflector на Spine через `local-as 65000 no-prepend replace-as`) с VXLAN data-plane и **Symmetric IRB** (Type-1, Type-2, Type-3, Type-4, Type-5).
* **Multi-tenancy:** Полная L3-изоляция арендаторов на уровне ядра Linux (`VRF_TEN_A` — таблица `101`, `VRF_TEN_B` — таблица `102`) с поддержкой пересекающихся IP-подсетей (`10.10.10.0/24`).
* **Отказоустойчивость доступа:**
  * **EVPN Multihoming (All-Active)** с LACP (802.3ad) и общим Ethernet Segment (`ESI`) между `leaf-1` и `leaf-2` для `host-2`.
  * **Anycast Gateway** на всех SVI-интерфейсах (`vlan10`, `vlan20`, `vlan30`).
* **Высокопроизводительный East-West сегмент:** Jumbo Frames (**MTU 9216** на фабрике, **MTU 9000** на серверах), прозрачная передача DSCP через VXLAN (`tos inherit`) и приоритизация очередей через Linux TC (`prio`).
* **Out-of-Band (OOB):** Изолированный `VRF_MGMT` (таблица `1000`) для интерфейсов управления `eth0`.

## Схема развёрнутого стенда (`evpn-mvp`)

```text
                       +-----------------------+               +-----------------------+

                       |        spine-1        |               |        spine-2        |
                       |   Underlay AS 65000   |               |   Underlay AS 65000   |
                       |  Overlay RR AS 65000  |               |  Overlay RR AS 65000  |
                       |  lo:  10.255.0.101/32 |               |  lo:  10.255.0.102/32 |
                       |  lo1: 10.255.1.101/32 |               |  lo1: 10.255.1.102/32 |
                       +-----+-----------+-----+               +-----+-----------+-----+
                        eth1 |           | eth2                 eth1 |           | eth2
                 10.0.0.0/31 |           | 10.0.0.2/31   10.0.0.10/31|           | 10.0.0.12/31

                             |           +-------------+-------------+           |
                             |                         |                         |
                             |           +-------------+-------------+           |
                 10.0.0.1/31 |           | 10.0.0.11/31  10.0.0.3/31 |           | 10.0.0.13/31
                        eth1 |           | eth2                 eth1 |           | eth2
                       +-----+-----------+-----+               +-----+-----------+-----+

                       |        leaf-1         |               |        leaf-2         |
                       |   Underlay AS 65001   |               |   Underlay AS 65002   |
                       |   Overlay  AS 65000   |               |   Overlay  AS 65000   |
                       |  lo (VTEP): .0.1/32   |               |  lo (VTEP): .0.2/32   |
                       |  lo1 (BGP): .1.1/32   |               |  lo1 (BGP): .1.2/32   |
                       +-----+-----------+-----+               +-----+-----------+-----+
                        eth3 |           | eth4                 eth4 |           | eth3
                     VLAN 10 |           | VLAN 20           VLAN 20 |           | VLAN 30
                   (VRF_TEN_A)           | (VRF_TEN_A)   (VRF_TEN_A) |           | (VRF_TEN_B)

                             |           +-------+     +-------+     |           |
                             |                   |     |             |           |
                       +-----+-----+         +---+-----+---+         |     +-----+-----+

                       |  host-1   |         |   host-2    |         |     |  host-3   |
                       | Tenant A  |         |  Tenant A   |         |     | Tenant B  |
                       |10.10.10.1 |         |  10.10.20.2 |         |     |10.10.10.1 |
                       |GW: .10.254|         | GW: .20.254 |         |     |GW: .10.254|
                       +-----------+         |  LACP bond0 |         |     +-----------+

                                             | (EVPN-MH)   |         |  (IP пересекается
                                             +-------------+         |   с host-1 в др. VRF)
```

## Структура репозитория

```text
.
├── README.md                 # Описание проекта, схема стенда, быстрый старт
├── topology.clab.yml         # Топология Containerlab
├── docs/
│   ├── architecture.md       # Целевая диаграмма, план IP-адресации, таблица VNI/VRF
│   ├── design-decisions.md   # Обоснование ASN, RD/RT, ESI, MLAG vs EVPN-MH, QoS
│   └── runbook.md            # Развёртывание, проверки, Graceful Shutdown и траблшутинг
├── configs/
│   ├── daemons               # Включённые демоны FRR (bgpd, zebra, staticd, bfdd)
│   ├── spine-1/              # frr.conf и setup.sh
│   ├── spine-2/              # frr.conf и setup.sh
│   ├── leaf-1/               # frr.conf и setup.sh
│   ├── leaf-2/               # frr.conf и setup.sh
│   ├── host-1/               # setup.sh (Tenant A, single-homed)
│   ├── host-2/               # setup.sh (Tenant A, EVPN Multihoming LACP)
│   └── host-3/               # setup.sh (Tenant B, пересекающийся IP)
└── tests/
    └── verify.sh             # Скрипт автоматической проверки стенда
```

## Быстрый старт

```bash
# 1. Загрузка модулей ядра на Linux-хосте
sudo modprobe bonding vrf vxlan 8021q

# 2. Развёртывание топологии
containerlab deploy -t topology.clab.yml

# 3. Запуск проверок работоспособности
./tests/verify.sh
```

Подробная документация приведена в каталоге [`docs/`](./docs/).
