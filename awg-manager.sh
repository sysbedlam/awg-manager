#!/bin/sh
# awg-manager - AmneziaWG server manager for OpenWrt
# https://github.com/sysbedlam/awg-manager

VERSION="1.0.0"
CLIENTS_DIR="/etc/awg-manager/clients"
CONFIG_FILE="/etc/awg-manager/server.conf"
AWG_IFACE="awg_srv"

# Colors
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
BLUE=$(printf '\033[0;34m')
CYAN=$(printf '\033[0;36m')
NC=$(printf '\033[0m')

# ─────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────

print_banner() {
    printf "\n"
    printf "${CYAN}╔═══════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║        awg-manager v${VERSION}            ║${NC}\n"
    printf "${CYAN}║   AmneziaWG Manager for OpenWrt       ║${NC}\n"
    printf "${CYAN}║  github.com/sysbedlam/awg-manager     ║${NC}\n"
    printf "${CYAN}╚═══════════════════════════════════════╝${NC}\n"
    printf "\n"
}

print_ok()   { printf "${GREEN}[✓]${NC} $1\n"; }
print_err()  { printf "${RED}[✗]${NC} $1\n"; }
print_info() { printf "${BLUE}[i]${NC} $1\n"; }
print_warn() { printf "${YELLOW}[!]${NC} $1\n"; }

check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_err "Запусти от root"
        exit 1
    fi
}

is_awg_installed() {
    command -v awg > /dev/null 2>&1
}

get_server_ip() {
    ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1
}

random_int() {
    local min=$1
    local max=$2
    awk -v min=$min -v max=$max 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'
}

random_token() {
    cat /dev/urandom | tr -dc 'a-z0-9' | head -c 16
}

# ─────────────────────────────────────────
# INSTALL
# ─────────────────────────────────────────

install_awg() {
    echo ""
    print_info "Установка AmneziaWG через скрипт Slava-Shchipunov..."
    echo ""

    if is_awg_installed; then
        print_ok "AmneziaWG уже установлен"
        return 0
    fi

    if ! sh <(wget -O - https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh) << 'ANSWERS'
y
n
ANSWERS
    then
        print_err "Ошибка установки"
        return 1
    fi

    print_ok "AmneziaWG установлен"
}

# ─────────────────────────────────────────
# CREATE SERVER
# ─────────────────────────────────────────

create_server() {
    echo ""

    if ! is_awg_installed; then
        print_err "AmneziaWG не установлен. Сначала выбери пункт 1."
        return 1
    fi

    # Check if server already exists
    if uci get network.$AWG_IFACE > /dev/null 2>&1; then
        print_warn "Сервер уже создан."
        printf "Пересоздать? (y/n): "
        read answer
        [ "$answer" != "y" ] && return 0
        # Remove existing
        uci delete network.$AWG_IFACE 2>/dev/null
        uci commit network
    fi

    print_info "Генерация ключей и параметров..."

    # Generate keys
    PRIV_KEY=$(awg genkey)
    PUB_KEY=$(echo "$PRIV_KEY" | awg pubkey)

    # Random AmneziaWG params (like official app)
    JC=$(random_int 3 10)
    JMIN=$(random_int 40 80)
    JMAX=$(random_int $((JMIN + 20)) 150)
    S1=$(random_int 15 50)
    S2=$(random_int 15 50)
    H1=$(random_int 5 2147483647)
    H2=$(random_int 5 2147483647)
    H3=$(random_int 5 2147483647)
    H4=$(random_int 5 2147483647)

    # Random port
    PORT=$(random_int 10000 65000)

    # Random subnet 172.16.x.x
    RAND_A=$(random_int 16 31)
    RAND_B=$(random_int 1 254)
    DEFAULT_SUBNET="172.$RAND_A.$RAND_B"
    SERVER_IP="${DEFAULT_SUBNET}.1"

    echo ""
    print_info "Предлагаемая подсеть: ${GREEN}${DEFAULT_SUBNET}.0/24${NC} (сервер ${DEFAULT_SUBNET}.1)"
    printf "Использовать её? (Enter = да, или введи своё начало, например 192.168.55): "
    read CUSTOM_SUBNET

    if [ -n "$CUSTOM_SUBNET" ]; then
        SERVER_IP="${CUSTOM_SUBNET}.1"
        DEFAULT_SUBNET="$CUSTOM_SUBNET"
    fi

    print_info "Создание интерфейса $AWG_IFACE..."

    # Create interface via UCI
    uci set network.$AWG_IFACE=interface
    uci set network.$AWG_IFACE.proto='amneziawg'
    uci set network.$AWG_IFACE.private_key="$PRIV_KEY"
    uci set network.$AWG_IFACE.listen_port="$PORT"
    uci set network.$AWG_IFACE.addresses="$SERVER_IP/24"
    uci set network.$AWG_IFACE.awg_jc="$JC"
    uci set network.$AWG_IFACE.awg_jmin="$JMIN"
    uci set network.$AWG_IFACE.awg_jmax="$JMAX"
    uci set network.$AWG_IFACE.awg_s1="$S1"
    uci set network.$AWG_IFACE.awg_s2="$S2"
    uci set network.$AWG_IFACE.awg_h1="$H1"
    uci set network.$AWG_IFACE.awg_h2="$H2"
    uci set network.$AWG_IFACE.awg_h3="$H3"
    uci set network.$AWG_IFACE.awg_h4="$H4"
    uci commit network

    # Firewall zone
    print_info "Настройка firewall..."

    # Add zone
    uci add firewall zone > /dev/null
    uci set firewall.@zone[-1].name='awg'
    uci set firewall.@zone[-1].network="$AWG_IFACE"
    uci set firewall.@zone[-1].input='ACCEPT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].forward='ACCEPT'
    uci set firewall.@zone[-1].masq='1'

    # Forwarding awg -> wan
    uci add firewall forwarding > /dev/null
    uci set firewall.@forwarding[-1].src='awg'
    uci set firewall.@forwarding[-1].dest='wan'

    # Open UDP port
    uci add firewall rule > /dev/null
    uci set firewall.@rule[-1].name="Allow-AmneziaWG"
    uci set firewall.@rule[-1].src='wan'
    uci set firewall.@rule[-1].dest_port="$PORT"
    uci set firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].target='ACCEPT'
    uci commit firewall

    # Save server config
    mkdir -p /etc/awg-manager
    mkdir -p $CLIENTS_DIR

    cat > $CONFIG_FILE << EOF
SERVER_PUB_KEY=$PUB_KEY
SERVER_PRIV_KEY=$PRIV_KEY
SERVER_PORT=$PORT
SERVER_IP=$SERVER_IP
SUBNET_BASE=$DEFAULT_SUBNET
JC=$JC
JMIN=$JMIN
JMAX=$JMAX
S1=$S1
S2=$S2
H1=$H1
H2=$H2
H3=$H3
H4=$H4
EOF

    # Apply
    service network restart > /dev/null 2>&1
    service firewall restart > /dev/null 2>&1
    sleep 2
    ifdown $AWG_IFACE > /dev/null 2>&1
    ifup $AWG_IFACE > /dev/null 2>&1

    echo ""
    print_ok "Сервер создан!"
    echo ""
    echo "  Публичный ключ : ${GREEN}$PUB_KEY${NC}"
    echo "  Порт           : ${GREEN}$PORT${NC}"
    echo "  Туннель        : ${GREEN}$SERVER_IP/24${NC}"
    echo "  Jc/Jmin/Jmax   : ${GREEN}$JC / $JMIN / $JMAX${NC}"
    echo "  S1/S2          : ${GREEN}$S1 / $S2${NC}"
    echo ""
}

# ─────────────────────────────────────────
# ADD CLIENT
# ─────────────────────────────────────────

get_next_ip() {
    . $CONFIG_FILE
    local i=2
    while [ $i -le 254 ]; do
        local ip="${SUBNET_BASE}.$i"
        if ! grep -r "Address = $ip" $CLIENTS_DIR/ > /dev/null 2>&1; then
            echo $ip
            return
        fi
        i=$((i + 1))
    done
    echo ""
}

add_client() {
    echo ""

    if [ ! -f "$CONFIG_FILE" ]; then
        print_err "Сервер не создан. Сначала выбери пункт 2."
        return 1
    fi

    . $CONFIG_FILE

    printf "Имя клиента (например phone, laptop): "
    read CLIENT_NAME

    if [ -z "$CLIENT_NAME" ]; then
        print_err "Имя не может быть пустым"
        return 1
    fi

    # Check if exists
    if [ -f "$CLIENTS_DIR/$CLIENT_NAME.conf" ]; then
        print_err "Клиент '$CLIENT_NAME' уже существует"
        return 1
    fi

    # Get next IP
    CLIENT_IP=$(get_next_ip)
    if [ -z "$CLIENT_IP" ]; then
        print_err "Нет свободных IP адресов"
        return 1
    fi

    print_info "Генерация ключей для $CLIENT_NAME..."

    # Generate keys
    CLIENT_PRIV=$(awg genkey)
    CLIENT_PUB=$(echo "$CLIENT_PRIV" | awg pubkey)
    CLIENT_PSK=$(awg genpsk)

    # Get server external IP
    EXT_IP=$(get_server_ip)

    # Create client config
    cat > $CLIENTS_DIR/$CLIENT_NAME.conf << EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP/32
DNS = 1.1.1.1, 8.8.8.8
Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

[Peer]
PublicKey = $SERVER_PUB_KEY
PresharedKey = $CLIENT_PSK
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $EXT_IP:$SERVER_PORT
PersistentKeepAlive = 25
EOF

    # Add peer to server via UCI
    local PEER_ID="awg_peer_$(echo $CLIENT_NAME | tr -cd 'a-zA-Z0-9_')"
    uci set network.$PEER_ID=amneziawg_$AWG_IFACE
    uci set network.$PEER_ID.public_key="$CLIENT_PUB"
    uci set network.$PEER_ID.preshared_key="$CLIENT_PSK"
    uci set network.$PEER_ID.allowed_ips="$CLIENT_IP/32"
    uci set network.$PEER_ID.description="$CLIENT_NAME"
    uci commit network

    # Restart interface
    ifdown $AWG_IFACE > /dev/null 2>&1
    ifup $AWG_IFACE > /dev/null 2>&1

    echo ""
    print_ok "Клиент '${GREEN}$CLIENT_NAME${NC}' создан!"
    echo "  IP в туннеле : ${GREEN}$CLIENT_IP${NC}"
    echo ""

    # Show QR
    show_qr_by_name $CLIENT_NAME

    # Offer download
    echo ""
    printf "Открыть ссылку для скачивания конфига? (y/n): "
    read ans
    [ "$ans" = "y" ] && serve_client_config $CLIENT_NAME
}

# ─────────────────────────────────────────
# DELETE CLIENT
# ─────────────────────────────────────────

delete_client() {
    echo ""
    list_clients
    echo ""
    printf "Имя клиента для удаления: "
    read CLIENT_NAME

    if [ ! -f "$CLIENTS_DIR/$CLIENT_NAME.conf" ]; then
        print_err "Клиент '$CLIENT_NAME' не найден"
        return 1
    fi

    printf "${RED}Удалить клиента '$CLIENT_NAME'? (y/n):${NC} "
    read confirm
    [ "$confirm" != "y" ] && return 0

    # Remove UCI peer
    local PEER_ID="awg_peer_$(echo $CLIENT_NAME | tr -cd 'a-zA-Z0-9_')"
    uci delete network.$PEER_ID 2>/dev/null
    uci commit network

    # Remove config file
    rm -f "$CLIENTS_DIR/$CLIENT_NAME.conf"

    # Restart interface
    ifdown $AWG_IFACE > /dev/null 2>&1
    ifup $AWG_IFACE > /dev/null 2>&1

    print_ok "Клиент '$CLIENT_NAME' удалён"
}

# ─────────────────────────────────────────
# LIST CLIENTS
# ─────────────────────────────────────────

list_clients() {
    echo ""
    print_info "Список клиентов:"
    echo ""

    if [ -z "$(ls -A $CLIENTS_DIR 2>/dev/null)" ]; then
        print_warn "Клиентов нет"
        return
    fi

    i=1
    for f in $CLIENTS_DIR/*.conf; do
        name=$(basename $f .conf)
        ip=$(grep "^Address" $f | awk '{print $3}' | cut -d/ -f1)
        printf "  ${GREEN}$i.${NC} $name  ${BLUE}($ip)${NC}\n"
        i=$((i+1))
    done
    echo ""
}

# ─────────────────────────────────────────
# SHOW QR
# ─────────────────────────────────────────

show_qr_by_name() {
    local name=$1
    local conf="$CLIENTS_DIR/$name.conf"

    if [ ! -f "$conf" ]; then
        print_err "Клиент '$name' не найден"
        return 1
    fi

    if ! command -v qrencode > /dev/null 2>&1; then
        print_info "Устанавливаю qrencode..."
        opkg install qrencode > /dev/null 2>&1
    fi

    echo ""
    print_info "QR-код для $name:"
    echo ""
    qrencode -t ansiutf8 < "$conf"
    echo ""
}

show_qr() {
    echo ""
    list_clients
    printf "Имя клиента: "
    read name
    show_qr_by_name "$name"
}

# ─────────────────────────────────────────
# SHOW CONFIG
# ─────────────────────────────────────────

show_config() {
    echo ""
    list_clients
    printf "Имя клиента: "
    read name

    local conf="$CLIENTS_DIR/$name.conf"
    if [ ! -f "$conf" ]; then
        print_err "Клиент '$name' не найден"
        return 1
    fi

    echo ""
    print_info "Конфиг $name:"
    printf "${CYAN}────────────────────────────────────────${NC}\n"
    cat "$conf"
    printf "${CYAN}────────────────────────────────────────${NC}\n"
}

# ─────────────────────────────────────────
# SERVE CONFIG VIA HTTP (120 sec)
# ─────────────────────────────────────────

serve_client_config() {
    local CLIENT_NAME=$1

    if [ -z "$CLIENT_NAME" ]; then
        list_clients
        printf "Имя клиента: "
        read CLIENT_NAME
    fi

    local conf="$CLIENTS_DIR/$CLIENT_NAME.conf"
    if [ ! -f "$conf" ]; then
        print_err "Клиент '$CLIENT_NAME' не найден"
        return 1
    fi

    local EXT_IP=$(get_server_ip)
    local PORT=$(random_int 20000 60000)
    local TOKEN=$(random_token)
    local SERVE_DIR="/tmp/awg_serve_$$"
    local TIMEOUT=120

    # Prepare directory with token subdir
    mkdir -p "$SERVE_DIR/$TOKEN"
    cp "$conf" "$SERVE_DIR/$TOKEN/$CLIENT_NAME.conf"

    # Open firewall port temporarily
    uci add firewall rule > /dev/null
    local RULE_NAME="tmp_awg_serve_$$"
    uci set firewall.@rule[-1].name="$RULE_NAME"
    uci set firewall.@rule[-1].src='wan'
    uci set firewall.@rule[-1].dest_port="$PORT"
    uci set firewall.@rule[-1].proto='tcp'
    uci set firewall.@rule[-1].target='ACCEPT'
    uci commit firewall
    service firewall restart > /dev/null 2>&1

    # Start busybox httpd
    busybox httpd -f -p $PORT -h "$SERVE_DIR" &
    HTTPD_PID=$!

    echo ""
    print_ok "Ссылка для скачивания (действует ${TIMEOUT} сек):"
    echo ""
    echo "  ${GREEN}http://$EXT_IP:$PORT/$TOKEN/$CLIENT_NAME.conf${NC}"
    echo ""

    # Countdown
    i=$TIMEOUT
    while [ $i -gt 0 ]; do
        printf "\r  ${YELLOW}Осталось: %3d сек...${NC}" $i
        sleep 1
        i=$((i-1))
    done
    echo ""

    # Cleanup
    kill $HTTPD_PID 2>/dev/null
    rm -rf "$SERVE_DIR"

    # Remove firewall rule
    local idx=0
    while uci get firewall.@rule[$idx] > /dev/null 2>&1; do
        local rname=$(uci get firewall.@rule[$idx].name 2>/dev/null)
        if [ "$rname" = "$RULE_NAME" ]; then
            uci delete firewall.@rule[$idx]
            break
        fi
        idx=$((idx+1))
    done
    uci commit firewall
    service firewall restart > /dev/null 2>&1

    print_ok "Ссылка закрыта, порт закрыт"
}

# ─────────────────────────────────────────
# SERVER STATUS
# ─────────────────────────────────────────

server_status() {
    echo ""
    print_info "Статус сервера:"
    echo ""
    awg show 2>/dev/null || print_err "AmneziaWG не запущен"
    echo ""
}

# ─────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────

main_menu() {
    while true; do
        print_banner
        printf "  ${GREEN}1.${NC} Установить AmneziaWG\n"
        printf "  ${GREEN}2.${NC} Создать сервер\n"
        printf "  ${GREEN}3.${NC} Добавить клиента\n"
        printf "  ${GREEN}4.${NC} Удалить клиента\n"
        printf "  ${GREEN}5.${NC} Список клиентов\n"
        printf "  ${GREEN}6.${NC} Показать QR-код клиента\n"
        printf "  ${GREEN}7.${NC} Показать конфиг клиента\n"
        printf "  ${GREEN}8.${NC} Скачать конфиг (HTTP 120 сек)\n"
        printf "  ${GREEN}9.${NC} Статус сервера\n"
        printf "  ${RED}0.${NC} Выход\n"
        printf "\n"
        printf "Выбор: "
        read choice

        case $choice in
            1) install_awg ;;
            2) create_server ;;
            3) add_client ;;
            4) delete_client ;;
            5) list_clients ;;
            6) show_qr ;;
            7) show_config ;;
            8) serve_client_config ;;
            9) server_status ;;
            0) echo ""; print_ok "Пока!"; echo ""; exit 0 ;;
            *) print_err "Неверный выбор" ;;
        esac

        echo ""
        printf "Нажми Enter для продолжения..."
        read dummy
    done
}

# ─────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────

check_root
main_menu
