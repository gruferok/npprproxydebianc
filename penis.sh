#!/bin/bash

# Функция логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция проверки команды
check_command() {
    if [ $? -ne 0 ]; then
        log_message "ОШИБКА: $1"
        exit 1
    else
        log_message "УСПЕХ: $1"
    fi
}

# Проверка root прав
if [ "$EUID" -ne 0 ]; then
    log_message "Скрипт должен быть запущен с правами root"
    exit 1
fi

# Установка необходимых пакетов
log_message "Установка необходимых пакетов..."
apt-get update
apt-get install -y squid apache2-utils iputils-ping net-tools
check_command "Установка пакетов"

# Создание базового конфигурационного файла
log_message "Создание конфигурационного файла для Squid..."
cat <<EOL > /etc/squid/squid.conf
# Базовые настройки производительности
max_filedesc 500000
pid_filename /var/run/squid.pid

# Отключение логов для производительности
access_log none
cache_store_log none
cache deny all

# Настройки IPv6
dns_v4_first off
dns_nameservers 2001:4860:4860::8888 2001:4860:4860::8844

# Принудительное использование IPv6
acl to_ipv6 dst ipv6
http_access deny all !to_ipv6

# Базовый порт
http_port 3128

# Защита и оптимизация заголовков
via off
forwarded_for delete
follow_x_forwarded_for deny all
request_header_access X-Forwarded-For deny all
request_header_access Authorization allow all
request_header_access Proxy-Authorization allow all
request_header_access Cache-Control allow all
request_header_access Content-Length allow all
request_header_access Content-Type allow all
request_header_access Date allow all
request_header_access Host allow all
request_header_access If-Modified-Since allow all
request_header_access Pragma allow all
request_header_access Accept allow all
request_header_access Accept-Charset allow all
request_header_access Accept-Encoding allow all
request_header_access Accept-Language allow all
request_header_access Connection allow all
request_header_access All deny all

# Базовые ACL
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# Аутентификация
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 100
auth_param basic realm Proxy
auth_param basic credentialsttl 1 minute
auth_param basic casesensitive off

# Контроль доступа
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# Оптимизация
visible_hostname V6proxies-Net
unique_hostname V6proxies-Net

# Debug
debug_options ALL,1
cache_log /var/log/squid/cache.log
EOL

check_command "Создание базовой конфигурации Squid"

# Генерация прокси
log_message "Генерация прокси..."
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
    check_command "Создание пользователя $username"

    # Настройка порта и ACL
    port=$((3129 + $i))
    cat <<EOL >> /etc/squid/squid.conf
http_port 45.87.246.238:$port
acl p${port} localport $port
tcp_outgoing_address 2a10:9680:1::$i p${port}
EOL
    check_command "Настройка прокси $i"
    
    # Сохранение данных прокси
    echo "45.87.246.238:$port:$username:$password" >> /etc/squid/proxies.txt
done

# Настройка IPv6
log_message "Настройка IPv6..."
ip -6 addr flush dev ens3
ip -6 route flush dev ens3
check_command "Очистка IPv6 настроек"

# Настройка интерфейса
ip link set dev ens3 up
ip -6 addr add 2a10:9680:1::1/48 dev ens3
ip -6 addr add fe80::1/64 dev ens3 scope link

for i in {2..10}; do
    ip -6 addr add 2a10:9680:1::$i/48 dev ens3
done
check_command "Настройка адресов интерфейса"

# Маршрутизация
ip -6 route add 2a10:9680::/48 dev ens3
ip -6 route add default via 2a10:9680::1 dev ens3 metric 1
ip -6 route add 2001:4860:4860::8888 via 2a10:9680::1
ip -6 route add 2001:4860:4860::8844 via 2a10:9680::1
check_command "Настройка маршрутизации"

# Настройки sysctl
cat > /etc/sysctl.d/99-ipv6.conf <<EOL
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.proxy_ndp=1
net.ipv6.conf.default.proxy_ndp=1
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.all.autoconf=0
net.ipv6.conf.default.autoconf=0
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.default.disable_ipv6=0
net.ipv6.conf.ens3.disable_ipv6=0
net.ipv6.conf.all.use_tempaddr=0
net.ipv6.conf.default.use_tempaddr=0
EOL

sysctl -p /etc/sysctl.d/99-ipv6.conf
check_command "Настройка параметров ядра"

# Перезапуск и проверка
systemctl restart squid
sleep 5
systemctl is-active --quiet squid
check_command "Запуск Squid"

# Проверка прокси
log_message "Проверка прокси..."
while IFS=: read -r host port user pass; do
    curl -6 --proxy "$host:$port" --proxy-user "$user:$pass" -s "https://api6.ipify.org"
done < /etc/squid/proxies.txt

log_message "Настройка завершена"
