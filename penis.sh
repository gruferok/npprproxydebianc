check_proxy() {
    local host=$1
    local port=$2
    local user=$3
    local pass=$4
    
    echo "Проверка $host:$port..."
    
    # Проверка доступности
    nc -zv -w5 $host $port >/dev/null 2>&1
    local nc_status=$?
    
    if [ $nc_status -eq 0 ]; then
        # Получаем внешний IPv6
        local external_ip=$(curl -6 --proxy "$host:$port" --proxy-user "$user:$pass" -s https://api64.ipify.org?format=json | grep -o '"ip":"[^"]*' | cut -d'"' -f4)
        
        if [[ $external_ip == 2a10* ]]; then
            echo "Прокси $host:$port РАБОТАЕТ"
            echo "Внешний IPv6: $external_ip"
            
            # Сохраняем IP для проверки уникальности
            echo "$external_ip" >> /tmp/proxy_ips.txt
            return 0
        else
            echo "Прокси $host:$port использует IPv4 или неверный IPv6"
            return 1
        fi
    else
        echo "Прокси $host:$port НЕ РАБОТАЕТ"
        return 1
    fi
}

echo "Начинаем проверку прокси с определением внешних IPv6..."
rm -f /tmp/proxy_ips.txt

while IFS=: read -r host port user pass; do
    check_proxy "$host" "$port" "$user" "$pass"
done < /etc/squid/proxies.txt

# Проверка уникальности IPv6
echo "Проверка уникальности IPv6 адресов..."
DUPLICATE_IPS=$(sort /tmp/proxy_ips.txt | uniq -d)
if [ -n "$DUPLICATE_IPS" ]; then
    echo "Найдены повторяющиеся IPv6 адреса:"
    echo "$DUPLICATE_IPS"
    exit 1
else
    echo "Все прокси используют уникальные IPv6 адреса"
fi
