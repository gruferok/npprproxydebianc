#!/bin/bash

# Настройки
USERS_PER_PORT=2
TOTAL_PORTS=2
IPV6_SUBNET="2a10:9680:1::"
IPV6_PREFIX="/48"
IPV6_GATEWAY="2a10:9680::1"
ROTATION_INTERVAL=300 # 5 минут в секундах

# Пути к файлам
SQUID_CONF="/etc/squid/squid.conf"
SQUID_PASSWD="/etc/squid/squid_passwd"
GENERATE_IPV6_SCRIPT="/usr/local/bin/generate_ipv6.sh"

# Функция для генерации случайного пароля
generate_password() {
    < /dev/urandom tr -dc 'A-Za-z0-9' | head -c16
}

# Функция для генерации уникального IPv6 адреса
generate_ipv6() {
    printf "${IPV6_SUBNET}%x:%x:%x:%x\n" $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536))
}

# Установка необходимых пакетов
install_packages() {
    apt-get update
    apt-get install -y squid apache2-utils
}

# Создание скрипта для генерации IPv6 адресов
create_ipv6_script() {
    cat > "$GENERATE_IPV6_SCRIPT" <<EOL
#!/bin/bash
generate_ipv6() {
    printf "${IPV6_SUBNET}%x:%x:%x:%x\n" $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536))
}
generate_ipv6
EOL
    chmod +x "$GENERATE_IPV6_SCRIPT"
}

# Настройка Squid
configure_squid() {
    # Создание базовой конфигурации Squid
    cat > "$SQUID_CONF" <<EOL
http_port 3128
auth_param basic program /usr/lib/squid/basic_ncsa_auth $SQUID_PASSWD
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# Использование внешнего скрипта для генерации IPv6 адресов
external_acl_type ipv6_generator ipv6 %LOGIN $GENERATE_IPV6_SCRIPT
acl dynamic_ipv6 external ipv6_generator
tcp_outgoing_address 2a10:9680:1::/48 dynamic_ipv6

# Настройка ротации кэша для принудительного обновления IPv6 адресов
refresh_pattern . 0 0% 0
EOL

    # Генерация пользователей и паролей
    > "$SQUID_PASSWD"
    for ((port=3128; port<3128+TOTAL_PORTS; port++)); do
        for ((user=1; user<=USERS_PER_PORT; user++)); do
            local username="user$((user+(port-3128)*USERS_PER_PORT))"
            local password=$(generate_password)
            htpasswd -b "$SQUID_PASSWD" "$username" "$password"
            echo "$HOSTNAME:$port:$username:$password" >> proxy_list.txt
        done
    done

    chown proxy:proxy "$SQUID_PASSWD"
    chmod 640 "$SQUID_PASSWD"
}

# Функция для ротации IPv6 адресов
rotate_ipv6_addresses() {
    while true; do
        sleep $ROTATION_INTERVAL
        systemctl reload squid
    done
}

# Основная функция
main() {
    install_packages
    create_ipv6_script
    configure_squid
    systemctl restart squid
    rotate_ipv6_addresses &
}

main
