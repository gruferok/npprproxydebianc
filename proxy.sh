#!/bin/bash

# Параметры настройки
users_per_port=2  # Количество пользователей на порт
num_ports=2       # Количество портов

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

# Функция для обновления конфигурации Squid
update_squid_config() {
    echo "Обновление конфигурации Squid..."

    # Создание конфигурационного файла для Squid
    echo "http_port [::]:3128" > /etc/squid/squid.conf

    # Добавление портов для Squid
    for port in $(seq 3128 $((3128 + num_ports - 1))); do
        echo "http_port $port" >> /etc/squid/squid.conf
    done

    cat <<EOL >> /etc/squid/squid.conf
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 5
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off

acl authenticated proxy_auth REQUIRED
http_access allow authenticated

# Правила для обработки CONNECT-запросов (туннелей)
acl CONNECT method CONNECT
EOL

    # Генерация случайных логинов и паролей, добавление в файл паролей
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

            # Добавление логина и пароля в файл proxies.txt
            echo "45.87.246.238:$port:$username:$password" >> /etc/squid/proxies.txt

            # Для каждого пользователя создаем ACL
            echo "acl user_$user_index proxy_auth $username" >> /etc/squid/squid.conf

            # Назначение динамических IPv6 адресов для каждого пользователя
            while true; do
                new_ipv6="$ipv6_base$(printf '%x' $((RANDOM % 65535)))"
                echo "Пробуем назначить IPv6 адрес: $new_ipv6 для пользователя: $username"
                if ! grep -q "$new_ipv6" /etc/squid/squid.conf; then
                    echo "tcp_outgoing_address $new_ipv6 user_$user_index" >> /etc/squid/squid.conf
                    echo "Успешно назначен IPv6 адрес: $new_ipv6 для пользователя: $username"
                    break  # Выход из цикла после назначения адреса
                else
                    echo "IPv6 адрес $new_ipv6 уже существует, генерируем новый..."
                fi
            done
        done
    done

    echo "Текущая конфигурация Squid перед перезапуском:"
    cat /etc/squid/squid.conf

    # Перезапуск Squid для применения изменений
    echo "Перезапуск Squid..."
    systemctl restart squid
    if [ $? -ne 0 ]; then
        echo "Ошибка при перезапуске Squid!"
        exit 1
    fi
}

# Вызов функции обновления конфигурации
update_squid_config

# Скрипт для ротации IPv6 адресов каждые 5 минут
echo "Создание крон-задачи для ротации IPv6 адресов..."
cat <<EOL > /etc/cron.d/rotate_squid_ipv6
*/5 * * * * root /usr/bin/rotate_squid_ipv6.sh
EOL

# Скрипт для ротации IPv6 адресов
cat <<'EOL' > /usr/bin/rotate_squid_ipv6.sh
#!/bin/bash
ipv6_base="2a10:9680:1::"

# Для каждого пользователя генерируем новый уникальный IPv6 адрес
while true; do
    users=$(grep 'tcp_outgoing_address' /etc/squid/squid.conf | awk '{print $4}')
    for user in $users; do
        new_ipv6="$ipv6_base$(printf '%x' $((RANDOM % 65535)))"
        echo "Ротация IPv6 адреса для пользователя: $user. Новый адрес: $new_ipv6"
        if ! grep -q "$new_ipv6" /etc/squid/squid.conf; then
            sed -i "s/tcp_outgoing_address .* $user/tcp_outgoing_address $new_ipv6 $user/" /etc/squid/squid.conf
            echo "Успешно обновлен IPv6 адрес для пользователя: $user на $new_ipv6"
        else
            echo "IPv6 адрес $new_ipv6 уже существует, генерируем новый..."
        fi
    done
    systemctl reload squid
    sleep 300  # Ждем 5 минут перед следующей ротацией
done
EOL

# Настройка прав на выполнение скрипта
chmod +x /usr/bin/rotate_squid_ipv6.sh

echo "Установка и настройка завершены! Прокси сохранены в /etc/squid/proxies.txt"
