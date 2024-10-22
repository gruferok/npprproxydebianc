#!/bin/bash

# Function to delete file if it exists
delete_file_if_exists() {
  if [ -f "$1" ]; then
    rm "$1"
  fi
}

# Function to write proxies to file
write_backconnect_proxies_to_file() {
  delete_file_if_exists $proxy_dir/proxy.txt

  for port in $(eval echo "{$start_port..$last_port}"); do
    echo "$backconnect_ipv4:$port" >> $proxy_dir/proxy.txt
  done
}

# Function to install 3proxy
install_3proxy() {
  cd $proxy_dir

  echo -e "\nDownloading proxy server source..."
  wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz
  tar -xf 0.9.4.tar.gz
  rm 0.9.4.tar.gz
  
  # Remove existing 3proxy directory if it exists
  rm -rf 3proxy
  mv 3proxy-0.9.4 3proxy
  echo "Proxy server source code downloaded successfully"

  echo -e "\nStart building proxy server execution file from source..."
  cd 3proxy
  make -f Makefile.Linux
  if [ -f "bin/3proxy" ] || [ -f "src/3proxy" ]; then
    echo "Proxy server built successfully"
    # Ensure the binary is in the right place
    mkdir -p bin
    [ -f "src/3proxy" ] && mv src/3proxy bin/
  else
    echo "Error: proxy server build from source code failed."
    exit 1
  fi
  cd ..
}

# Main script
proxy_dir="$HOME/proxyserver"
mkdir -p $proxy_dir

# Set default values
subnet=64
proxies_type="http"
start_port=30000
proxy_count=100
mode_flag="-6"

# Install required packages
apt update
apt install -y make gcc g++ wget curl

# Install 3proxy
install_3proxy

# Configure IPv6
interface_name=$(ip -br l | awk '$1 !~ "lo|vir|wl|@NONE" { print $1 }' | awk 'NR==1')
echo "net.ipv6.conf.$interface_name.proxy_ndp=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.proxy_ndp=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
echo "net.ipv6.ip_nonlocal_bind=1" >> /etc/sysctl.conf
sysctl -p

# Generate random IPv6 addresses
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
rnd_subnet_ip() {
    echo -n 2001:0:ae1e:$(printf "%x\n" $((RANDOM % 65536))):$(printf "%x\n" $((RANDOM % 65536))):$(printf "%x\n" $((RANDOM % 65536))):
    for i in {1..4}; do
        echo -n ${array[$RANDOM % 16]}
    done
}

for i in $(seq 1 $proxy_count); do
    rnd_subnet_ip >> $proxy_dir/ipv6.list
done

# Create 3proxy config
cat > $proxy_dir/3proxy.cfg <<EOF
daemon
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth none

$(awk -v port="$start_port" '{print "proxy -6 -n -a -p"port" -i127.0.0.1 -e"$0; port++}' $proxy_dir/ipv6.list)
EOF

# Start 3proxy
ulimit -n 600000
ulimit -u 600000
$proxy_dir/3proxy/bin/3proxy $proxy_dir/3proxy.cfg &

# Write proxies to file
backconnect_ipv4=$(curl -s https://ipinfo.io/ip)
last_port=$((start_port + proxy_count - 1))
write_backconnect_proxies_to_file

# Display final message
echo "Файл с прокси создан по адресу - $proxy_dir/proxy.txt"
