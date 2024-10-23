#!/bin/bash

# Установка Squid
echo "Установка Squid..."
apt-get update && apt-get install -y squid apache2-utils
if [ $? -ne 0 ]; then
    echo "Ошибка при установке Squid!"
    exit 1
fi

# Создание конфигурационного файла для Squid
echo "Создание конфигурационного файла для Squid..."
cat <<EOL > /etc/squid/squid.conf
# Настройка порта для входящих подключений по IPv4
http_port 3128

# Аутентификация пользователей
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 5
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off

# Разрешаем доступ только аутентифицированным пользователям
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

EOL

# Генерация 10 прокси с уникальными логинами и паролями
echo "Генерация 10 логинов и паролей..."
touch /etc/squid/passwd
touch /etc/squid/proxies.txt

for i in {1..10}
do
    username="user$i"
    password=$(openssl rand -base64 12)

    # Добавляем логины и пароли в файл аутентификации
    if [ $i -eq 1 ]; then
        htpasswd -c -b /etc/squid/passwd $username $password
    else
        htpasswd -b /etc/squid/passwd $username $password
    fi
    
    if [ $? -ne 0 ]; then
        echo "Ошибка при создании пользователя $username!"
        exit 1
    fi

    # Генерируем уникальный IPv6 адрес
    ipv6="2a10:9680:1::$(printf '%x' $i)"

    # Настраиваем уникальный порт для каждого прокси
    echo "http_port 45.87.246.238:$((3129 + $i)) name=proxy$i" >> /etc/squid/squid.conf
    
    # Добавляем пользователя и его прокси в файл proxies.txt
    echo "45.87.246.238:$((3129 + $i)):$username:$password" >> /etc/squid/proxies.txt

    # Создаем ACL для каждого прокси
    echo "acl ipv6_$i myportname proxy$i" >> /etc/squid/squid.conf
    
    # Назначаем исходящий IPv6 для каждого прокси
    echo "tcp_outgoing_address $ipv6 ipv6_$i" >> /etc/squid/squid.conf
done

# Перезапуск Squid для применения изменений
echo "Перезапуск Squid..."
systemctl restart squid
if [ $? -ne 0 ]; then
    echo "Ошибка при перезапуске Squid!"
    exit 1
fi

echo "Установка завершена! Прокси сохранены в /etc/squid/proxies.txt"
