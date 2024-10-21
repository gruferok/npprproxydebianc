#!/bin/bash

# Снятие системных лимитов
echo "Снятие системных лимитов..."
ulimit -n 1048576
ulimit -u 1048576

# Запрос количества пользователей
echo "Сколько пользователей вы хотите сгенерировать?"
read user_count

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
http_port 3128

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

# Внешний ACL для генерации уникальных IPv6 адресов
external_acl_type ipv6_generator %LOGIN /usr/local/bin/generate_ipv6.sh
acl dynamic_ipv6 external ipv6_generator
tcp_outgoing_address 2a10:9680:1::%>a dynamic_ipv6
EOL

# Создание скрипта для генерации уникальных IPv6 адресов
cat <<'EOL' > /usr/local/bin/generate_ipv6.sh
#!/bin/bash
while read login; do
    printf "%x\n" $((RANDOM << 15 | RANDOM))
done
EOL

chmod +x /usr/local/bin/generate_ipv6.sh

# Генерация случайных логинов и паролей, и добавление их в файл паролей
echo "Генерация случайных логинов и паролей..."
touch /etc/squid/passwd
touch /etc/squid/proxies.txt

for i in $(seq 1 $user_count)
do
    username="user$i"
    password=$(openssl rand -base64 12)
    
    if [ $i -eq 1 ]; then
        htpasswd -c -b /etc/squid/passwd $username $password
    else
        htpasswd -b /etc/squid/passwd $username $password
    fi
    
    if [ $? -ne 0 ]; then
        echo "Ошибка при создании пользователя $username!"
        exit 1
    fi
    
    echo "45.87.246.238:3128:$username:$password" >> /etc/squid/proxies.txt
done

# Перезапуск Squid для применения изменений
echo "Перезапуск Squid..."
systemctl restart squid
if [ $? -ne 0 ]; then
    echo "Ошибка при перезапуске Squid!"
    exit 1
fi

echo "Установка и настройка завершены! Прокси сохранены в /etc/squid/proxies.txt"
