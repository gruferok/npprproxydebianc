#!/bin/bash

# Функция для отображения финального сообщения
show_final_message() {
    local local_path=$1
    echo "Файл с прокси сохранен по адресу: ${local_path}"
}

# Функция для интерактивного ввода параметров
get_user_input() {
    echo "Пожалуйста, введите следующие параметры для установки прокси:"
    
    # Подсеть
    echo "Подсеть (например, 48):"
    read subnet
    if [[ -z "$subnet" ]]; then subnet=64; fi
    
    # Логин и пароль
    echo "Логин и пароль:"
    echo "1) Указать"
    echo "2) Без логина и пароля"
    echo "3) Рандомные"
    read auth_choice
    case $auth_choice in
        1)
            echo "Введите логин:"
            read user
            echo "Введите пароль:"
            read password
            use_random_auth=false
            ;;
        2)
            user=""
            password=""
            use_random_auth=false
            ;;
        3)
            user=""
            password=""
            use_random_auth=true
            ;;
        *)
            echo "Неверный выбор, будут использованы рандомные логин и пароль."
            use_random_auth=true
            ;;
    esac
    
    # Количество прокси
    echo "Количество прокси:"
    read proxy_count
    if [[ -z "$proxy_count" ]]; then proxy_count=100; fi
}

# Функция для проверки параметров запуска
check_startup_parameters() {
    if ! [[ $proxy_count =~ ^[0-9]+$ ]]; then
        echo "Ошибка: Количество прокси должно быть положительным целым числом" >&2
        exit 1
    fi

    if [ $(expr $subnet % 4) != 0 ]; then
        echo "Ошибка: Значение подсети должно быть кратно 4" >&2
        exit 1
    fi
}

# Функция для проверки IPv6
check_ipv6() {
    if ! test -f /proc/net/if_inet6; then
        echo "Ошибка: IPv6 интерфейс не включен. Включите IPv6 в вашей системе." >&2
        exit 1
    fi

    if ! [[ $(ip -6 addr show scope global) ]]; then
        echo "Ошибка: Глобальный IPv6 адрес не назначен серверу." >&2
        exit 1
    fi
}

# Функция для настройки IPv6
configure_ipv6() {
    echo "net.ipv6.conf.all.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
    sysctl -p
}

# Функция для установки необходимых пакетов
install_required_packages() {
    apt update
    apt install -y make g++ wget curl
}

# Функция для установки 3proxy
install_3proxy() {
    mkdir -p ~/proxyserver && cd ~/proxyserver
    wget https://github.com/3proxy/3proxy/archive/0.9.4.tar.gz
    tar -xvf 0.9.4.tar.gz
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p ~/proxyserver/3proxy
    mv bin/3proxy ~/proxyserver/3proxy/
    cd ~/proxyserver
    rm -rf 3proxy-0.9.4 0.9.4.tar.gz
}

# Функция для получения IPv4 адреса для обратного подключения
get_backconnect_ipv4() {
    ip addr show | awk '$1 == "inet" && $3 == "brd" {gsub(/\/.*$/, "", $2); print $2; exit}'
}

# Функция для генерации случайных пользователей, если необходимо
generate_random_users_if_needed() {
    if [ "$use_random_auth" = true ]; then
        for i in $(seq 1 $proxy_count); do
            echo "user$i:$(openssl rand -base64 12)" >> ~/proxyserver/users.txt
        done
    fi
}

# Функция для создания скрипта запуска
create_startup_script() {
    cat > ~/proxyserver/start.sh <<EOL
#!/bin/bash
ulimit -n 600000
ulimit -u 600000
~/proxyserver/3proxy/3proxy ~/proxyserver/3proxy.cfg
EOL
    chmod +x ~/proxyserver/start.sh
}

# Функция для добавления в cron
add_to_cron() {
    (crontab -l 2>/dev/null; echo "@reboot ~/proxyserver/start.sh") | crontab -
}

# Функция для запуска прокси-сервера
run_proxy_server() {
    ~/proxyserver/start.sh
}

# Функция для записи прокси в файл
write_backconnect_proxies_to_file() {
    local proxy_file="$1"
    local backconnect_ip=$(get_backconnect_ipv4)
    local start_port=30000
    
    for i in $(seq 1 $proxy_count); do
        local port=$((start_port + i - 1))
        if [ "$use_random_auth" = true ]; then
            local credentials=$(sed -n "${i}p" ~/proxyserver/users.txt)
            echo "$backconnect_ip:$port:$credentials" >> "$proxy_file"
        else
            if [ -n "$user" ] && [ -n "$password" ]; then
                echo "$backconnect_ip:$port:$user:$password" >> "$proxy_file"
            else
                echo "$backconnect_ip:$port" >> "$proxy_file"
            fi
        fi
    done
}

# Основной код скрипта
get_user_input
check_startup_parameters
check_ipv6
configure_ipv6
install_required_packages
install_3proxy
generate_random_users_if_needed
create_startup_script
add_to_cron

# Создание конфигурационного файла для 3proxy
cat > ~/proxyserver/3proxy.cfg <<EOL
daemon
maxconn 2000
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth $([[ "$use_random_auth" = true ]] && echo "strong" || echo "none")
users $([ -f ~/proxyserver/users.txt ] && cat ~/proxyserver/users.txt | tr '\n' ' ' || echo "$user:CL:$password")
allow * * * *
$(for i in $(seq 1 $proxy_count); do
    echo "proxy -6 -n -a -p$((30000 + i - 1)) -i$(get_backconnect_ipv4) -e"
done)
EOL

# Запуск прокси-сервера
run_proxy_server

# Путь к файлу с прокси
proxy_file="$HOME/proxy_list.txt"

# Сохраняем прокси в текстовый файл
write_backconnect_proxies_to_file "$proxy_file"

# Вызов функции для отображения финального сообщения
show_final_message "$proxy_file"

exit 0
