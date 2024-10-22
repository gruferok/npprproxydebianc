#!/bin/bash

proxy_dir="/opt/3proxy"
script_log_file="/var/log/3proxy_install.log"

function log_err_and_exit() {
    echo "$1" >&2
    exit 1
}

function install_3proxy() {
    # Установка необходимых зависимостей
    apt update
    apt install -y wget tar make gcc

    mkdir -p $proxy_dir && cd $proxy_dir

    echo -e "\nЗагрузка исходного кода прокси-сервера..."
    (
        wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz &> /dev/null
        tar -xf 0.9.4.tar.gz
        rm 0.9.4.tar.gz
        mv 3proxy-0.9.4 3proxy
    ) &>> $script_log_file
    echo "Исходный код прокси-сервера успешно загружен"

    echo -e "\nНачало сборки исполняемого файла прокси-сервера из исходного кода..."
    cd 3proxy
    make -f Makefile.Linux &>> $script_log_file

    if test -f "$proxy_dir/3proxy/bin/3proxy"; then
        echo "Прокси-сервер успешно собран"
    else
        log_err_and_exit "Ошибка: сборка прокси-сервера из исходного кода не удалась."
    fi

    cd ..

    # Копирование бинарного файла в /usr/local/bin для удобства использования
    cp $proxy_dir/3proxy/bin/3proxy /usr/local/bin/

    echo "3proxy успешно установлен и доступен в системе"
}

# Запуск функции установки
install_3proxy
