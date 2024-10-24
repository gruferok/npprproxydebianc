#!/bin/bash

# Переменные
INTERFACE="ens3"
IPV6_SUBNET="2a10:9680:1::/48"
IPV6_GATEWAY="2a10:9680::1"
IPV6_ADDRESSES=(
  "2a10:9680:1::1"
  "2a10:9680:1::2"
  "2a10:9680:1::3"
  "2a10:9680:1::4"
  "2a10:9680:1::5"
  "2a10:9680:1::6"
  "2a10:9680:1::7"
  "2a10:9680:1::8"
  "2a10:9680:1::9"
  "2a10:9680:1::10"
)

# Функция для вывода отладочных сообщений
log_debug() {
    echo "[DEBUG] $1"
}

log_error() {
    echo "[ERROR] $1"
    exit 1
}

log_info() {
    echo "[INFO] $1"
}

# Проверка доступности интерфейса
log_info "Проверяем наличие интерфейса $INTERFACE..."
if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
    log_error "Интерфейс $INTERFACE не найден."
fi
log_info "Интерфейс $INTERFACE найден."

# Настройка IPv6 адресов
log_info "Настраиваем IPv6 адреса на интерфейсе $INTERFACE..."
for IP in "${IPV6_ADDRESSES[@]}"; do
    log_debug "Добавляем адрес $IP..."
    if ! ip -6 addr add "$IP/48" dev "$INTERFACE" 2>/dev/null; then
        log_error "Ошибка при добавлении $IP. Возможно, он уже добавлен."
    fi
done
log_info "IPv6 адреса успешно добавлены."

# Удаление существующего маршрута, если он есть
log_info "Удаляем существующий маршрут, если он есть..."
ip -6 route del default via "$IPV6_GATEWAY" dev "$INTERFACE" 2>/dev/null
log_info "Удаление маршрута завершено (если маршрут существовал)."

# Добавление нового маршрута
log_info "Добавляем новый маршрут по умолчанию через $IPV6_GATEWAY..."
if ! ip -6 route add default via "$IPV6_GATEWAY" dev "$INTERFACE"; then
    log_error "Не удалось добавить маршрут по умолчанию."
fi
log_info "Маршрут по умолчанию успешно добавлен."

# Проверка доступности IPv6 интернета
log_info "Проверяем сетевое подключение по IPv6..."
if ! ping6 -c 3 google.com > /dev/null 2>&1; then
    log_error "Не удалось пинговать google.com по IPv6. Проверьте подключение."
fi
log_info "Подключение по IPv6 успешно проверено."

# Проверка конфигурации Squid
log_info "Проверка конфигурации Squid..."
squid -k parse > /dev/null 2>&1
if [ $? -ne 0 ]; then
    log_error "Конфигурация Squid содержит ошибки."
fi
log_info "Конфигурация Squid успешно проверена."

# Перезапуск Squid
log_info "Перезапускаем Squid..."
if ! systemctl restart squid; then
    log_error "Не удалось перезапустить Squid."
fi
log_info "Squid успешно перезапущен."

# Проверка состояния Squid
log_info "Проверка статуса Squid..."
if ! systemctl is-active --quiet squid; then
    log_error "Squid не запущен."
fi
log_info "Squid успешно работает."

# Проверка прокси
log_info "Начинаем проверку прокси-серверов..."

for ((i=0; i<${#IPV6_ADDRESSES[@]}; i++)); do
    PROXY_PORT=$((3130 + i))
    log_debug "Проверка прокси 45.87.246.238:$PROXY_PORT..."
    
    # Проверка подключения по IPv6 через конкретный прокси
    curl --proxy "http://[${IPV6_ADDRESSES[$i]}]:$PROXY_PORT" -6 http://ifconfig.co > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "Прокси 45.87.246.238:$PROXY_PORT использует IPv4 или неверный IPv6."
    else
        log_info "Прокси 45.87.246.238:$PROXY_PORT успешно проверен и использует IPv6."
    fi
done

log_info "Все прокси успешно проверены."

# Конец скрипта
log_info "Скрипт завершен успешно."
