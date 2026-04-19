# awg-manager

Простой менеджер AmneziaWG сервера для OpenWrt. Устанавливает и настраивает AmneziaWG одной командой, управляет клиентами, показывает QR-коды и позволяет скачать конфиг по временной ссылке.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/sysbedlam/awg-manager/main/install.sh | sh
```

Или через wget:

```bash
sh <(wget -O - https://raw.githubusercontent.com/sysbedlam/awg-manager/main/install.sh)
```

После установки запускай командой:

```bash
awg-manager
```

## Возможности

- Установка AmneziaWG (через скрипт Slava-Shchipunov)
- Создание сервера со случайными параметрами обфускации (Jc, Jmin, Jmax, S1, S2, H1-H4) и случайным портом — как в официальном приложении AmneziaVPN
- Автоматическая настройка firewall и зоны
- Добавление клиентов с автоматической выдачей IP
- Удаление клиентов
- Показ QR-кода в терминале
- Скачивание конфига по временной HTTP-ссылке (120 секунд, случайный токен)

## Меню

```
1. Установить AmneziaWG
2. Создать сервер
3. Добавить клиента
4. Удалить клиента
5. Список клиентов
6. Показать QR-код клиента
7. Показать конфиг клиента
8. Скачать конфиг (HTTP 120 сек)
9. Статус сервера
0. Выход
```

## Требования

- OpenWrt 24.10+
- KVM VPS (не OpenVZ/LXC)
- x86_64

## Конфиги клиентов

Хранятся в `/etc/awg-manager/clients/`. Можно скачать через SCP:

```bash
scp root@YOUR_IP:/etc/awg-manager/clients/phone.conf .
```

Или через встроенную команду скачивания (пункт 8 в меню) — поднимает временный HTTP-сервер на 120 секунд с уникальным токеном в URL.

## Примечания

- Сервер использует подсеть `10.0.0.1/24`, клиенты получают адреса с `10.0.0.2`
- DNS для клиентов: `1.1.1.1` и `8.8.8.8`
- Для подключения используй приложение [AmneziaVPN](https://amnezia.org)

## Благодарности

- [Slava-Shchipunov](https://github.com/Slava-Shchipunov/awg-openwrt) — скрипт установки AmneziaWG для OpenWrt
- [AmneziaVPN](https://amnezia.org) — проект AmneziaWG
