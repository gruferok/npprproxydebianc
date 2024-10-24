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

# Проверка конфигурации
echo "Проверка конфигурации Squid..."
squid -k parse

if [ $? -ne 0 ]; then
    echo "Ошибка в конфигурации Squid!"
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
