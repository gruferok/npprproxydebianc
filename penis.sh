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

# После генерации прокси добавить настройку маршрутизации IPv6:
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

# Проверка конфигурации
echo "Проверка конфигурации Squid..."
squid -k parse

if [ $? -ne 0 ]; then
    echo "Ошибка в конфигурации Squid!"
    exit 1
fi

# Перед перезапуском squid добавить проверку IPv6:
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

# Функция проверки прокси через IPv6
check_proxy() {
    local proxy_line=$1
    local host=$2
    local port=$3
    local user=$4
    local pass=$5
    
    # Проверяем соединение через curl с IPv6
    result=$(curl -6 --proxy "$host:$port" --proxy-user "$user:$pass" -s https://api64.ipify.org?format=json)
    
    if [[ $result == *"ip"* ]]; then
        ip=$(echo $result | grep -o '"ip":"[^"]*' | cut -d'"' -f4)
        if [[ $ip == 2a10* ]]; then
            echo "Прокси $host:$port работает через IPv6: $ip"
            return 0
        else
            echo "Прокси $host:$port использует IPv4: $ip"
            return 1
        fi
    else
        echo "Прокси $host:$port не отвечает"
        return 1
    fi
}

echo "Проверка работоспособности прокси..."
while IFS=: read -r host port user pass; do
    check_proxy "$line" "$host" "$port" "$user" "$pass"
done < /etc/squid/proxies.txt

# Проверяем общий результат
if [ $? -eq 0 ]; then
    echo "Все прокси успешно настроены и работают через IPv6!"
else
    echo "Обнаружены проблемы с некоторыми прокси!"
    exit 1
fi

