#!/bin/bash

# Настройки
USERS_PER_PORT=2
TOTAL_PORTS=2

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

# Создание базового конфигурационного файла для Squid
echo "Создание конфигурационного файла для Squid..."
cat <<EOL > /etc/squid/squid.conf
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 50 startup=5 idle=1
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off

acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access allow CONNECT
http_access allow localhost

positive_dns_ttl 5 minutes
negative_dns_ttl 30 seconds
connect_timeout 30 seconds

cache_log /var/log/squid/cache.log

# Настройка уникальных IPv6 для каждого соединения
acl conn_id connection_id
EOL

# Генерация случайных логинов и паролей, и добавление их в файл паролей
echo "Генерация случайных логинов и паролей..."
touch /etc/squid/passwd
touch /etc/squid/proxies.txt

total_users=$((USERS_PER_PORT * TOTAL_PORTS))
user_count=1

for port in $(seq 3128 $((3127 + TOTAL_PORTS))); do
    echo "http_port $port" >> /etc/squid/squid.conf
    
    for i in $(seq 1 $USERS_PER_PORT); do
        username="user$user_count"
        password=$(openssl rand -base64 12)
        
        if [ $user_count -eq 1 ]; then
            htpasswd -c -b /etc/squid/passwd $username $password
        else
            htpasswd -b /etc/squid/passwd $username $password
        fi
        
        if [ $? -ne 0 ]; then
            echo "Ошибка при создании пользователя $username!"
            exit 1
        fi
        
        echo "45.87.246.238:$port:$username:$password" >> /etc/squid/proxies.txt
        echo "acl user_$user_count proxy_auth $username" >> /etc/squid/squid.conf
        echo "tcp_outgoing_address 2a10:9680:1::$(printf '%x' $user_count) user_$user_count" >> /etc/squid/squid.conf
        
        user_count=$((user_count + 1))
    done
done

# Добавление правила для уникальных IPv6
echo "tcp_outgoing_address 2a10:9680:1::\${conn_id} authenticated" >> /etc/squid/squid.conf

# Перезапуск Squid для применения изменений
echo "Перезапуск Squid..."
systemctl restart squid
if [ $? -ne 0 ]; then
    echo "Ошибка при перезапуске Squid!"
    exit 1
fi

# Скрипт для ротации IPv6 адресов каждые 5 минут
echo "Создание крон-задачи для ротации IPv6 адресов..."
cat <<EOL > /etc/cron.d/rotate_squid_ipv6
*/5 * * * * root /usr/bin/rotate_squid_ipv6.sh
EOL

# Скрипт для ротации IPv6 адресов
cat <<'EOL' > /usr/bin/rotate_squid_ipv6.sh
#!/bin/bash
total_users=$((USERS_PER_PORT * TOTAL_PORTS))
for i in $(seq 1 $total_users); do
    ipv6="2a10:9680:1::$(printf '%x' $((RANDOM % 65536)))"
    sed -i "s/tcp_outgoing_address .* user_$i/tcp_outgoing_address $ipv6 user_$i/" /etc/squid/squid.conf
done
sed -i "s/tcp_outgoing_address 2a10:9680:1::.*/tcp_outgoing_address 2a10:9680:1::\${conn_id} authenticated/" /etc/squid/squid.conf
systemctl reload squid
if [ $? -ne 0 ]; then
    echo "Ошибка при перезагрузке Squid!"
    exit 1
fi
EOL

# Настройка прав на выполнение скрипта
chmod +x /usr/bin/rotate_squid_ipv6.sh

echo "Установка и настройка завершены! Прокси сохранены в /etc/squid/proxies.txt"
