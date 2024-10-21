#!/bin/bash

# Настройки
users_per_port=2
total_ports=2
ipv6_subnet="2a10:9680:1::"
ipv6_prefix="48"
ipv6_gateway="2a10:9680::1"

# Установка необходимых пакетов
apt-get update
apt-get install -y squid apache2-utils

# Генерация случайного пароля
generate_password() {
    < /dev/urandom tr -dc 'A-Za-z0-9' | head -c16
}

# Создание конфигурации Squid
cat > /etc/squid/squid.conf <<EOL
http_port 3128
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# IPv6 настройки
dns_v4_first on

# Внешний ACL для динамического назначения IPv6
external_acl_type ipv6_assign ttl=300 negative_ttl=0 children-startup=1 children-max=50 %LOGIN /usr/local/bin/assign_ipv6.py

acl dynamic_ipv6 external ipv6_assign
tcp_outgoing_address ${ipv6_subnet}%256 dynamic_ipv6
EOL

# Создание файла паролей
touch /etc/squid/passwd

# Генерация пользователей и портов
for ((p=1; p<=total_ports; p++)); do
    port=$((3128 + p - 1))
    echo "http_port $port" >> /etc/squid/squid.conf
    
    for ((u=1; u<=users_per_port; u++)); do
        username="user${p}_${u}"
        password=$(generate_password)
        echo "$username:$password" | tee -a /etc/squid/proxy_list.txt
        htpasswd -b /etc/squid/passwd $username $password
    done
done

# Скрипт для назначения IPv6 адресов
cat > /usr/local/bin/assign_ipv6.py <<EOL
#!/usr/bin/env python3
import sys
import random
import ipaddress

def generate_ipv6():
    subnet = ipaddress.IPv6Network('${ipv6_subnet}/${ipv6_prefix}')
    while True:
        address = subnet[random.randint(0, subnet.num_addresses - 1)]
        if address != subnet.network_address and address != subnet.broadcast_address:
            return str(address)

while True:
    line = sys.stdin.readline().strip()
    if not line:
        break
    
    username = line.split()[0]
    ipv6 = generate_ipv6()
    print(f"{username} OK ipv6={ipv6}")
    sys.stdout.flush()
EOL

chmod +x /usr/local/bin/assign_ipv6.py

# Скрипт для ротации IPv6 адресов
cat > /root/rotate_ipv6.sh <<EOL
#!/bin/bash
if systemctl is-active --quiet squid; then
    systemctl reload squid || systemctl restart squid
else
    systemctl start squid
fi
EOL

chmod +x /root/rotate_ipv6.sh

# Добавление задачи в crontab для ротации каждые 5 минут
(crontab -l 2>/dev/null; echo "*/5 * * * * /root/rotate_ipv6.sh") | crontab -

# Запуск Squid
systemctl enable squid
systemctl start squid

# Вывод списка прокси
while IFS=: read -r username password; do
    for ((p=1; p<=total_ports; p++)); do
        port=$((3128 + p - 1))
        echo "45.87.246.238:$port:$username:$password"
    done
done < /etc/squid/proxy_list.txt
