#!/bin/bash

# Настройки
users=2  # Количество пользователей на порт
ports=2  # Количество портов
subnet="2a10:9680:1::"  # Подсеть для IPv6
gateway="2a10:9680::1"  # Шлюз для IPv6
squid_conf="/etc/squid/squid.conf"
ip_list="/etc/squid/ipv6_users.txt"
proxy_list="proxy_list.txt"

# Проверка наличия Squid
if ! command -v squid >/dev/null 2>&1; then
    echo "Squid не установлен. Установите его с помощью: apt install squid"
    exit 1
fi

# Генерация уникальных IPv6 адресов
function generate_unique_ipv6 {
    local ip
    while :; do
        # Генерация случайной части IPv6
        ip="${subnet}$(printf '%x:%x:%x:%x:%x:%x:%x:%x' $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)))"
        if ! grep -q "$ip" "$ip_list"; then
            echo "$ip" >> "$ip_list"
            echo "$ip"
            break
        fi
    done
}

# Настройка пользователей и портов
function setup_users_and_ports {
    for ((p=0; p<ports; p++)); do
        port=$((3128 + p))  # Порты с 3128
        echo "http_port $port" >> "$squid_conf"

        for ((u=0; u<users; u++)); do
            user="user$((p * users + u + 1))"
            password=$(openssl rand -base64 12)
            echo "$user:$(openssl passwd -6 "$password")" >> /etc/squid/squid_passwd

            # Генерация IPv6 для пользователя
            ipv6=$(generate_unique_ipv6)

            echo "acl user_$user proxy_auth $user" >> "$squid_conf"
            echo "http_access allow user_$user" >> "$squid_conf"

            # Запись в файл прокси
            echo "$(curl -4s ifconfig.me):$port:$user:$password" >> "$proxy_list"
        done
    done
}

# Основная функция
function main {
    echo "" > "$squid_conf"  # Очистка конфигурации
    echo "http_access allow all" >> "$squid_conf"  # Разрешение доступа всем (можно настроить)

    setup_users_and_ports

    # Запуск Squid
    squid -N -f "$squid_conf" &

    # Настройка ротации адресов
    while :; do
        sleep 300  # Ожидание 5 минут
        echo "" > "$ip_list"  # Очистка списка IP
        echo "" > "$proxy_list"  # Очистка списка прокси
        setup_users_and_ports  # Повторная настройка пользователей и портов
    done
}

# Запуск основного процесса
main
