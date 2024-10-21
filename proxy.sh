#!/bin/bash

# Параметры настройки
users_per_port=2  # Количество пользователей на порт
num_ports=2       # Количество портов

# Общие системные лимиты
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
EOL

# Генерация случайных логинов, паролей и добавление их в файл паролей
echo "Генерация случайных логинов и паролей..."
touch /etc/squid/passwd
touch /etc/squid/proxies.txt

total_users=$((users_per_port * num_ports))
ipv6_base="2a10:9680:1::"  # Базовый префикс IPv6 адресов

for port in $(seq 3128 $((3128 + num_ports - 1))); do
    for i in $(seq 1 $users_per_port); do
        user_index=$(( (port - 3128) * users_per_port + i ))
        username="user$user_index"
        password=$(openssl rand -base64 12)

        if [ $user_index -eq 1 ]; then
            htpasswd -c -b /etc/squid/passwd $username $password
        else
            htpasswd -b /etc/squid/passwd $username $password
        fi

        if [ $? -ne 0 ]; then
            echo "Ошибка при создании пользователя $username!"
            exit 1
        fi

        ipv6="$ipv6_base$(printf '%x' $user_index)"
        echo "45.87.246.238:$port:$username:$password" >> /etc/squid/proxies.txt
        echo "acl user_$user_index proxy_auth $username" >> /etc/squid/squid.conf
        echo "tcp_outgoing_address $ipv6 user_$user_index" >> /etc/squid/squid.conf
    done
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
cat <<'EOL' > /usr/bin/rotate_squid_ipv6.sh
#!/bin/bash
ipv6_base="2a10:9680:1::"

for port in $(seq 3128 $((3128 + num_ports - 1))); do
    for i in $(seq 1 $users_per_port); do
        user_index=$(( (port - 3128) * users_per_port + i ))
        new_ipv6="$ipv6_base$(printf '%x' $((user_index + RANDOM % 1000)))"
        sed -i "s/tcp_outgoing_address .*/tcp_outgoing_address $new_ipv6 user_$user_index/" /etc/squid/squid.conf
    done
done
systemctl reload squid
if [ $? -ne 0 ]; then
    echo "Ошибка при перезагрузке Squid!"
    exit 1
fi
EOL

# Настройка прав на выполнение скрипта
chmod +x /usr/bin/rotate_squid_ipv6.sh

echo "Установка и настройка завершены! Прокси сохранены в /etc/squid/proxies.txt"

# Скрипт для мониторинга сервера и предупреждений при перегрузке
cat <<'EOL' > /usr/bin/monitor_server.sh
#!/bin/bash
CPU_THRESHOLD=80
MEM_THRESHOLD=80

while true; do
    CPU_USAGE=$(top -b -n1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    MEM_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    if (( $(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l) )); then
        echo "Предупреждение: Загрузка CPU превышает $CPU_THRESHOLD%. Текущая загрузка: $CPU_USAGE%."
    fi
    
    if (( $(echo "$MEM_USAGE > $MEM_THRESHOLD" | bc -l) )); then
        echo "Предупреждение: Загрузка памяти превышает $MEM_THRESHOLD%. Текущая загрузка: $MEM_USAGE%."
    fi
    
    sleep 60
done
EOL

# Настройка прав на выполнение скрипта
chmod +x /usr/bin/monitor_server.sh

# Создание крон-задачи для мониторинга сервера
echo "Создание крон-задачи для мониторинга сервера..."
cat <<EOL > /etc/cron.d/monitor_server
* * * * * root /usr/bin/monitor_server.sh
EOL
