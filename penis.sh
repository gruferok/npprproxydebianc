#!/bin/bash

# Функция логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция генерации случайного IPv6
generate_random_ipv6() {
    printf "2a10:9680:1:%04x:%04x:%04x:%04x:%04x" \
        $((RANDOM % 65535)) $((RANDOM % 65535)) \
        $((RANDOM % 65535)) $((RANDOM % 65535)) \
        $((RANDOM % 65535))
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
apt-get install -y squid apache2-utils iputils-ping net-tools curl
check_command "Установка пакетов"

# Создание необходимых директорий
mkdir -p /usr/local/squid/var/run/
mkdir -p /usr/local/squid/libexec/
ln -sf /usr/lib/squid/basic_ncsa_auth /usr/local/squid/libexec/basic_ncsa_auth

# Создание базового конфигурационного файла
log_message "Создание конфигурационного файла для Squid..."
cat <<'EOL' > /etc/squid/squid.conf
max_filedesc 500000

pid_filename /usr/local/squid/var/run/squidv6.pid

access_log          none

cache_store_log     none

# Hide client ip #
forwarded_for delete

# Turn off via header #
via off

# Deny request for original source of a request
follow_x_forwarded_for allow localhost
follow_x_forwarded_for deny all

# See below
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

cache           deny    all

acl to_ipv6 dst ipv6

http_access deny all !to_ipv6

acl allow_net src 1.1.1.1

# Common settings
acl SSL_ports port 443
acl Safe_ports port 80      # http
acl Safe_ports port 21      # ftp
acl Safe_ports port 443     # https
acl Safe_ports port 70      # gopher
acl Safe_ports port 210     # wais
acl Safe_ports port 1025-65535  # unregistered ports
acl Safe_ports port 280     # http-mgmt
acl Safe_ports port 488     # gss-http
acl Safe_ports port 591     # filemaker
acl Safe_ports port 777     # multiling http
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager

auth_param basic program /usr/local/squid/libexec/basic_ncsa_auth /etc/squid/squidv6.auth
auth_param basic children 5
auth_param basic realm Web-Proxy
auth_param basic credentialsttl 1 minute
auth_param basic casesensitive off

acl db-auth proxy_auth REQUIRED
http_access allow db-auth
http_access allow localhost
http_access deny all

coredump_dir /var/spool/squid3

unique_hostname V6proxies-Net
visible_hostname V6proxies-Net

refresh_pattern ^ftp:       1440    20% 10080
refresh_pattern ^gopher:    1440    0%  1440
refresh_pattern -i (/cgi-bin/|\?) 0 0%  0
refresh_pattern .       0   20% 4320

EOL

# Генерация прокси
log_message "Генерация прокси..."
touch /etc/squid/squidv6.auth
touch /etc/squid/proxies.txt

for i in {0..10}
do
    username="user$i"
    password=$(openssl rand -base64 12)
    port=$((10000 + $i))
    ipv6_addr=$(generate_random_ipv6)
    
    # Создание пользователей
    if [ $i -eq 0 ]; then
        htpasswd -c -b /etc/squid/squidv6.auth $username $password
    else
        htpasswd -b /etc/squid/squidv6.auth $username $password
    fi
    check_command "Создание пользователя $username"

    # Добавление конфигурации прокси
    cat <<EOL >> /etc/squid/squid.conf

http_access allow allow_net
http_port       $port
acl     p$port  localport       $port
tcp_outgoing_address    $ipv6_addr p$port
EOL
    check_command "Настройка прокси $i"
    
    # Сохранение данных прокси
    echo "$ipv6_addr:$port:$username:$password" >> /etc/squid/proxies.txt
done

# Настройка IPv6
log_message "Настройка IPv6..."
ip -6 addr flush dev ens3
ip -6 route flush dev ens3
check_command "Очистка IPv6 настроек"

# Настройка интерфейса
ip link set dev ens3 up

# Добавляем IPv6 адреса из proxies.txt
while IFS=: read -r host port user pass; do
    ip -6 addr add $host/48 dev ens3
done < /etc/squid/proxies.txt

ip -6 addr add fe80::1/64 dev ens3 scope link
check_command "Настройка адресов интерфейса"

# Маршрутизация
ip -6 route add local 2a10:9680:1::/48 dev lo
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
log_message "Начинаем проверку прокси..."

while IFS=: read -r host port user pass; do
    log_message "Тестирование прокси $host:$port"
    
    if nc -z -w5 "$host" "$port"; then
        log_message "Порт $port открыт"
        
        response=$(curl -6 --proxy-insecure --proxy "[$host]:$port" --proxy-user "$user:$pass" -s "https://api6.ipify.org" --connect-timeout 10)
        
        if [[ $response == *"2a10"* ]]; then
            log_message "Прокси $host:$port РАБОТАЕТ (IPv6: $response)"
            echo "$host:$port - OK (IPv6: $response)" >> /root/working_proxies.txt
        else
            log_message "Прокси $host:$port не использует IPv6"
            echo "$host:$port - ОШИБКА (Не IPv6)" >> /root/failed_proxies.txt
        fi
    else
        log_message "Порт $port недоступен"
        echo "$host:$port - ОШИБКА (Порт закрыт)" >> /root/failed_proxies.txt
    fi
    
    sleep 1
done < /etc/squid/proxies.txt

log_message "Проверка завершена"
