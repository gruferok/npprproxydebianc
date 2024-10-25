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

# Проверка наличия IPv6
if ! ip -6 addr show > /dev/null 2>&1; then
    log_message "IPv6 не поддерживается на этой системе"
    exit 1
fi

# Установка необходимых пакетов
log_message "Установка необходимых пакетов..."
apt-get update
apt-get install -y squid apache2-utils iputils-ping net-tools
check_command "Установка пакетов"

# Проверка интерфейса
if ! ip link show ens3 > /dev/null 2>&1; then
    log_message "Интерфейс ens3 не найден"
    exit 1
fi

# Создание базового конфигурационного файла
log_message "Создание конфигурационного файла для Squid..."
cat <<EOL > /etc/squid/squid.conf
# Базовые настройки
http_port 3128 ipv6

# IPv6 настройки
dns_nameservers 2001:4860:4860::8888 2001:4860:4860::8844

# Принудительное использование IPv6
tcp_outgoing_address 2a10:9680:1::1
prefer_direct off
dns_v4_first off

# DNS настройки
client_dst_passthru on
dns_defnames on
dns_retransmit_interval 5 second
dns_timeout 5 second
dns_packet_max 4096

# Кэш настройки
ipcache_size 4096
ipcache_low 90
ipcache_high 95
fqdncache_size 4096

# Базовые ACL
acl localnet src all
acl SSL_ports port 443
acl Safe_ports port 80 443
acl CONNECT method CONNECT
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# Аутентификация
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 100
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off

# Контроль доступа
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# Оптимизация
forwarded_for delete
request_header_access Via deny all
request_header_access X-Forwarded-For deny all
request_header_access From deny all
visible_hostname unknown

# Debug
debug_options ALL,1 28,9
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
    echo "http_port 45.87.246.238:$port ipv6 name=proxy$i" >> /etc/squid/squid.conf
    echo "acl proxy${i}_users myportname proxy$i" >> /etc/squid/squid.conf
    echo "tcp_outgoing_address 2a10:9680:1::$i proxy${i}_users" >> /etc/squid/squid.conf
    check_command "Настройка прокси $i"
    
    # Сохранение данных прокси
    echo "45.87.246.238:$port:$username:$password" >> /etc/squid/proxies.txt
done

# Настройка IPv6
log_message "Настройка IPv6..."

# Очистка старых настроек IPv6
log_message "Очистка старых настроек IPv6..."
ip -6 addr flush dev ens3
ip -6 route flush dev ens3
check_command "Очистка IPv6 настроек"

# Базовая настройка интерфейса
log_message "Настройка сетевого интерфейса..."
ip link set dev ens3 up
ip -6 addr add 2a10:9680:1::1/48 dev ens3
ip -6 addr add fe80::1/64 dev ens3 scope link

# Добавление дополнительных IPv6 адресов
for i in {2..10}; do
    ip -6 addr add 2a10:9680:1::$i/48 dev ens3
done

check_command "Настройка адресов интерфейса"

# Настройка маршрутизации
log_message "Настройка маршрутизации IPv6..."
ip -6 route add 2a10:9680::/48 dev ens3
ip -6 route add default via 2a10:9680::1 dev ens3 metric 1
ip -6 route add 2001:4860:4860::8888 via 2a10:9680::1
ip -6 route add 2001:4860:4860::8844 via 2a10:9680::1
check_command "Добавление маршрутов IPv6"

# Расширенные настройки sysctl
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

# Проверка IPv6 конфигурации
log_message "Проверка IPv6 конфигурации..."
ip -6 addr show
ip -6 route show
check_command "Проверка IPv6 конфигурации"

# Добавляем паузу для стабилизации сети
sleep 3

# Проверка IPv6 связности с подробным выводом
log_message "Проверка IPv6 связности..."
ping6 -c 3 -I ens3 2001:4860:4860::8888
check_command "Проверка связности с Google DNS"

# Проверка конфигурации Squid
log_message "Проверка конфигурации Squid..."
squid -k parse
check_command "Проверка конфигурации"

# Перезапуск сервиса
log_message "Перезапуск Squid..."
systemctl restart squid
check_command "Перезапуск службы"

# Ожидание запуска службы
sleep 5

# Проверка статуса службы
systemctl is-active --quiet squid
check_command "Проверка статуса службы"

# Функция проверки прокси
check_proxy() {
    local host=$1
    local port=$2
    local user=$3
    local pass=$4
    
    log_message "Проверка $host:$port..."
    
    # Проверка доступности порта
    nc -zv -w5 $host $port > /dev/null 2>&1
    check_command "Проверка доступности порта $port"
    
    # Проверка с принудительным IPv6
    local external_ip=$(curl -6 --proxy-insecure --proxy "$host:$port" --proxy-user "$user:$pass" -s -m 10 --retry 3 --retry-delay 2 "https://api6.ipify.org")
    
    if [[ $external_ip == *"2a10"* ]]; then
        ip=$external_ip
        log_message "Прокси $host:$port РАБОТАЕТ (IPv6: $ip)"
        echo "$ip" >> /tmp/proxy_ips.txt
        return 0
    else
        log_message "Прокси $host:$port использует IPv4 или неверный IPv6"
        return 1
    fi
}

log_message "Начинаем проверку прокси с определением внешних IPv6..."
rm -f /tmp/proxy_ips.txt

while IFS=: read -r host port user pass; do
    check_proxy "$host" "$port" "$user" "$pass"
done < /etc/squid/proxies.txt

# Проверка уникальности IPv6
log_message "Проверка уникальности IPv6 адресов..."
if [ -f /tmp/proxy_ips.txt ]; then
    DUPLICATE_IPS=$(sort /tmp/proxy_ips.txt | uniq -d)
    if [ -n "$DUPLICATE_IPS" ]; then
        log_message "Найдены повторяющиеся IPv6 адреса:"
        echo "$DUPLICATE_IPS"
        exit 1
    else
        log_message "Все прокси используют уникальные IPv6 адреса"
    fi
else
    log_message "Не удалось получить IPv6 адреса от прокси"
    exit 1
fi
