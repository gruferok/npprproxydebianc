su -c '

# Удаление директорий и файлов
rm -rf /root/proxyserver /var/tmp/ipv6-proxy-server-install.log /var/tmp/ipv6-proxy-server-logs.log


# Удаление IPv6 адресов
for ipv6 in $(ip -6 addr show scope global | grep inet6 | awk "{print \$2}"); do
    ip -6 addr del $ipv6 dev $(ip -6 route | grep default | awk "{print \$5}")
done

# Очистка изменений в /etc/security/limits.conf
sed -i "/\* hard nofile 999999/d" /etc/security/limits.conf
sed -i "/\* soft nofile 999999/d" /etc/security/limits.conf

# Очистка изменений в /etc/sysctl.conf
sed -i "/net.ipv4.route.min_adv_mss = 1460/d" /etc/sysctl.conf
sed -i "/net.ipv4.tcp_timestamps=0/d" /etc/sysctl.conf
sed -i "/net.ipv4.tcp_window_scaling=0/d" /etc/sysctl.conf
sed -i "/net.ipv4.icmp_echo_ignore_all = 1/d" /etc/sysctl.conf
sed -i "/net.ipv4.tcp_max_syn_backlog = 4096/d" /etc/sysctl.conf
sed -i "/net.ipv4.conf.all.forwarding=1/d" /etc/sysctl.conf
sed -i "/net.ipv4.ip_nonlocal_bind = 1/d" /etc/sysctl.conf
sed -i "/net.ipv6.conf.all.proxy_ndp=1/d" /etc/sysctl.conf
sed -i "/net.ipv6.conf.default.forwarding=1/d" /etc/sysctl.conf
sed -i "/net.ipv6.conf.all.forwarding=1/d" /etc/sysctl.conf
sed -i "/net.ipv6.ip_nonlocal_bind = 1/d" /etc/sysctl.conf
sed -i "/net.ipv4.ip_default_ttl=128/d" /etc/sysctl.conf
sed -i "/net.ipv4.tcp_syn_retries=2/d" /etc/sysctl.conf
sed -i "/net.ipv4.tcp_fin_timeout=30/d" /etc/sysctl.conf
sed -i "/net.ipv4.tcp_keepalive_time=7200/d" /etc/sysctl.conf
sed -i "/net.ipv4.tcp_rmem=4096 87380 6291456/d" /etc/sysctl.conf
sed -i "/net.ipv4.tcp_wmem=4096 16384 6291456/d" /etc/sysctl.conf

# Применение изменений sysctl
sysctl -p

# Удаление архива и информационных файлов
rm -f /root/proxy.zip /root/upload_info.txt

echo "Очистка завершена."
'
