#!/bin/bash

# Переменные
INTERFACE="ens3"
IPV6_GATEWAY="2a10:9680::1"
SUBNET="2a10:9680:1::/48"
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

# Вывод всех IPv6 адресов перед удалением для отладки
log_debug "Текущие IPv6 адреса на интерфейсе $INTERFACE:"
ip -6 addr show dev "$INTERFACE"

# Удаление старых IPv6 адресов по одному
log_info "Удаляем старые IPv6 адреса в подсети $SUBNET на интерфейсе $INTERFACE..."
for IP in "${IPV6_ADDRESSES[@]}"; do
    log_debug "Проверяем наличие $IP на интерфейсе..."
    if ip -6 addr show dev "$INTERFACE" | grep -q "$IP"; then
        log_debug "Удаляем адрес $IP..."
        if ! ip -6 addr del "$IP/128" dev "$INTERFACE"; then
            log_error "Ошибка при удалении адреса $IP."
        else
            log_info "Адрес $IP успешно удалён."
        fi
    else
        log_info "Адрес $IP не найден на интерфейсе."
    fi
done

# Повторный вывод IPv6 адресов для проверки удаления
log_debug "IPv6 адреса на интерфейсе после удаления:"
ip -6 addr show dev "$INTERFACE"

# Настройка новых IPv6 адресов
log_info "Настраиваем IPv6 адреса на интерфейсе $INTERFACE..."
for IP in "${IPV6_ADDRESSES[@]}"; do
    log_debug "Добавляем адрес $IP..."
    if ! ip -6 addr add "$IP/128" dev "$INTERFACE"; then
        log_error "Ошибка при добавлении $IP."
    else
        log_info "Адрес $IP успешно добавлен."
    fi
done

# Удаление существующего маршрута
log_info "Удаляем существующий маршрут..."
ip -6 route del default via "$IPV6_GATEWAY" dev "$INTERFACE" 2>/dev/null
log_info "Удаление маршрута завершено."

# Добавление нового маршрута
log_info "Добавляем новый маршрут по умолчанию через $IPV6_GATEWAY..."
if ! ip -6 route add default via "$IPV6_GATEWAY" dev "$INTERFACE"; then
    log_error "Не удалось добавить маршрут по умолчанию."
fi
log_info "Маршрут по умолчанию успешно добавлен."

# Проверка подключения по IPv6
log_info "Проверяем сетевое подключение по IPv6..."
if ! ping6 -c 3 google.com > /dev/null 2>&1; then
    log_error "Не удалось пинговать google.com по IPv6. Проверьте подключение."
fi
log_info "Подключение по IPv6 успешно проверено."

# Перезапуск Squid
log_info "Перезапускаем Squid..."
if ! systemctl restart squid; then
    log_error "Не удалось перезапустить Squid."
fi
log_info "Squid успешно перезапущен."

log_info "Скрипт завершен успешно."
