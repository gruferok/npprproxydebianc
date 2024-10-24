#!/bin/bash

# Установка Squid
echo "Установка Squid..."
apt-get update && apt-get install -y squid apache2-utils

if [ $? -ne 0 ]; then
    echo "Ошибка при установке Squid!"
    exit 1
fi

# Создание базового конфигурационного файла
echo "Создание конфигурационного файла для Squid..."
cat <<EOL > /etc/squid/squid.conf
# Базовые настройки
http_port 3128

# Принудительное использование IPv6
dns_v4_first off
dns_nameservers 2001:4860:4860::8888 2001:4860:4860::8844
tcp_outgoing_address 2a10:9680:1::1

# Форсирование IPv6
client_dst_passthru on
dns_defnames on
dns_retransmit_interval 5
dns_timeout 5

# IPv6 ACL
acl ipv6_traffic proto ipv6
prefer_direct on

# Аутентификация
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 100
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off

# Базовый контроль доступа
acl authenticated proxy_auth REQUIRED
acl ipv6_net src all
http_access allow authenticated
http_access deny all

# Включение расширенных логов
debug_options ALL,1 33,2 28,9
EOL

# Генерация прокси
echo "Генерация прокси..."
touch /etc/squid/passwd
touch /etc/squid/proxies.txt

for i in {1..10}
do
    username="user$i"
    password=$(openssl rand -base64 12)
    
    # Создание пользователей
    if [ $i -eq 1 ]; then
        htpasswd -c -b /etc/squid/passwd $username $password
    else
        htpasswd -b /etc/squid/passwd $username $password
    fi
    
    if [ $? -ne 0 ]; then
        echo "Ошибка при создании пользователя $username!"
        exit 1
    fi

    # Настройка порта и ACL
    port=$((3129 + $i))
    echo "http_port 45.87.246.238:$port name=proxy$i" >> /etc/squid/squid.conf
    echo "acl proxy${i}_users myportname proxy$i" >> /etc/squid/squid.conf
    echo "tcp_outgoing_address 2a10:9680:1::$i proxy${i}_users" >> /etc/squid/squid.conf
    
    # Сохранение данных прокси
    echo "45.87.246.238:$port:$username:$password" >> /etc/squid/proxies.txt
done

# Настройка маршрутизации IPv6
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

# Проверка конфигурации
echo "Проверка конфигурации Squid..."
squid -k parse

if [ $? -ne 0 ]; then
    echo "Ошибка в конфигурации Squid!"
    exit 1
fi

# Проверка IPv6 маршрутизации
ip -6 route show
if [ $? -ne 0 ]; then
    echo "IPv6 маршрутизация не настроена!"
    exit 1
fi

# Перезапуск сервиса
echo "Перезапуск Squid..."
systemctl restart squid

if [ $? -ne 0 ]; then
    echo "Ошибка при перезапуске Squid!"
    exit 1
fi

echo "Установка успешно завершена! Прокси сохранены в /etc/squid/proxies.txt"

# Функция проверки прокси
check_proxy() {
    local host=$1
    local port=$2
    local user=$3
    local pass=$4
    
    echo "Проверка $host:$port..."
    
    # Проверка с принудительным IPv6
    local external_ip=$(curl -6 --proxy "$host:$port" --proxy-user "$user:$pass" -s -m 10 --retry 3 --retry-delay 2 -H "Accept: application/json" https://api64.ipify.org?format=json)
    
    if [[ $external_ip == *"2a10"* ]]; then
        ip=$(echo $external_ip | grep -o '"ip":"[^"]*' | cut -d'"' -f4)
        echo "Прокси $host:$port РАБОТАЕТ"
        echo "Внешний IPv6: $ip"
        echo "$ip" >> /tmp/proxy_ips.txt
        return 0
    else
        echo "Прокси $host:$port использует IPv4 или неверный IPv6"
        return 1
    fi
}

echo "Начинаем проверку прокси с определением внешних IPv6..."
rm -f /tmp/proxy_ips.txt

while IFS=: read -r host port user pass; do
    check_proxy "$host" "$port" "$user" "$pass"
done < /etc/squid/proxies.txt

# Проверка уникальности IPv6
echo "Проверка уникальности IPv6 адресов..."
if [ -f /tmp/proxy_ips.txt ]; then
    DUPLICATE_IPS=$(sort /tmp/proxy_ips.txt | uniq -d)
    if [ -n "$DUPLICATE_IPS" ]; then
        echo "Найдены повторяющиеся IPv6 адреса:"
        echo "$DUPLICATE_IPS"
        exit 1
    else
        echo "Все прокси используют уникальные IPv6 адреса"
    fi
else
    echo "Не удалось получить IPv6 адреса от прокси"
    exit 1
fi
