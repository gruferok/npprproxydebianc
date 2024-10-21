#!/bin/bash

# Настройки
users_per_port=2
total_ports=2

# Снятие системных лимитов
echo "Снятие системных лимитов..."
ulimit -n 1048576
ulimit -u 1048576

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
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 5
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off
acl authenticated proxy_auth REQUIRED
http_access allow authenticated

# Уникальный IPv6 для каждого соединения
acl connect method CONNECT
external_acl_type ipv6_per_connection ipv6 %CONNECTION_ID
acl unique_ipv6 external ipv6_per_connection
tcp_outgoing_address 2a10:9680:1::%o unique_ipv6
EOL

# Генерация случайных логинов и паролей, и добавление их в файл паролей
echo "Генерация случайных логинов и паролей..."
touch /etc/squid/passwd
touch /etc/squid/proxies.txt

total_users=$((users_per_port * total_ports))
for port in $(seq 3128 $((3127 + total_ports))); do
    echo "http_port $port" >> /etc/squid/squid.conf
    
    for i in $(seq 1 $users_per_port); do
        user_id=$((($port - 3128) * users_per_port + i))
        username="user$user_id"
        password=$(openssl rand -base64 12)
        
        if [ $user_id -eq 1 ]; then
            htpasswd -c -b /etc/squid/passwd $username $password
        else
            htpasswd -b /etc/squid/passwd $username $password
        fi
        
        if [ $? -ne 0 ]; then
            echo "Ошибка при создании пользователя $username!"
            exit 1
        fi
        
        echo "45.87.246.238:$port:$username:$password" >> /etc/squid/proxies.txt
    done
done

# Создание скрипта для генерации уникальных IPv6
cat <<'EOL' > /usr/lib/squid/ipv6_per_connection
#!/bin/bash
while read line; do
    echo $(printf '2a10:9680:1::%x' $((RANDOM % 65536)))
done
EOL

chmod +x /usr/lib/squid/ipv6_per_connection

# Скрипт для ротации IPv6 адресов каждые 5 минут
echo "Создание крон-задачи для ротации IPv6 адресов..."
cat <<EOL > /etc/cron.d/rotate_squid_ipv6
*/5 * * * * root /usr/bin/rotate_squid_ipv6.sh
EOL

# Скрипт для ротации IPv6 адресов
cat <<'EOL' > /usr/bin/rotate_squid_ipv6.sh
#!/bin/bash
systemctl reload squid
if [ $? -ne 0 ]; then
    echo "Ошибка при перезагрузке Squid!"
    exit 1
fi
EOL

# Настройка прав на выполнение скрипта
chmod +x /usr/bin/rotate_squid_ipv6.sh

# Перезапуск Squid для применения изменений
echo "Перезапуск Squid..."
systemctl restart squid
if [ $? -ne 0 ]; then
    echo "Ошибка при перезапуске Squid!"
    exit 1
fi

echo "Установка и настройка завершены! Прокси сохранены в /etc/squid/proxies.txt"
