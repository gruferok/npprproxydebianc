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
http_port 3128
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 5
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off

acl authenticated proxy_auth REQUIRED
http_access allow authenticated
EOL

# Генерация случайных логинов и паролей, и добавление их в файл паролей
echo "Генерация случайных логинов и паролей..."
touch /etc/squid/passwd
touch /etc/squid/proxies.txt

for i in {1..10}  # Изменено на 10
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

    ipv6="2a10:9680:1::$(printf '%x' $i)"
    echo "http_port 45.87.246.238:$((30296 + $i)) name=proxy$i" >> /etc/squid/squid.conf
    echo "45.87.246.238:$((30296 + $i)):$username:$password" >> /etc/squid/proxies.txt
    echo "acl ipv6_$i myportname proxy$i" >> /etc/squid/squid.conf
    echo "tcp_outgoing_address $ipv6 ipv6_$i" >> /etc/squid/squid.conf
done

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
cat <<EOL > /usr/bin/rotate_squid_ipv6.sh
#!/bin/bash
for i in {1..10}  # Изменено на 10
do
    ipv6="2a10:9680:1::\$(printf '%x' \$((i + RANDOM % 1000)))"
    sed -i "s/tcp_outgoing_address .*/tcp_outgoing_address \$ipv6 ipv6_$i/" /etc/squid/squid.conf
done
systemctl reload squid
if [ \$? -ne 0 ]; then
    echo "Ошибка при перезагрузке Squid!"
    exit 1
fi
EOL

# Настройка прав на выполнение скрипта
chmod +x /usr/bin/rotate_squid_ipv6.sh

echo "Установка и настройка завершены! Прокси сохранены в /etc/squid/proxies.txt"