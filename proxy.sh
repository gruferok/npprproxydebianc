#!/bin/bash

# Function to delete file if it exists
delete_file_if_exists() {
  if [ -f "$1" ]; then
    rm "$1"
  fi
}

# Function to write proxies to file
write_backconnect_proxies_to_file() {
  delete_file_if_exists "$proxy_dir/proxy.txt"

  for port in $(eval echo "{$start_port..$last_port}"); do
    echo "$backconnect_ipv4:$port:$random_user:$random_pass" >> "$proxy_dir/proxy.txt"
  done
}

# Function to install 3proxy
install_3proxy() {
  cd "$proxy_dir"

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

# Generate random user credentials
generate_random_credentials() {
  random_user=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)
  random_pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)
}

# Main script
proxy_dir="$HOME/proxyserver"
mkdir -p "$proxy_dir"

# Set default values
start_port=30000
proxy_count=10

# Subnet and gateway for your network
subnet_base="2a10:9680:1"
prefix="/48"
gateway="2a10:9680::1"

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

# Add route for IPv6 with your gateway, check if route exists before adding
if ! ip -6 route show default | grep -q "$gateway"; then
  ip -6 route add default via $gateway dev $interface_name
else
  echo "Route already exists"
fi

# Generate random IPv6 addresses based on your subnet
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
rnd_subnet_ip() {
    echo -n "$subnet_base:$(printf "%x\n" $((RANDOM % 65536))):$(printf "%x\n" $((RANDOM % 65536))):$(printf "%x\n" $((RANDOM % 65536))):"
    for i in {1..4}; do
        echo -n ${array[$RANDOM % 16]}
    done
}

# Check if IPv6 address list exists and generate addresses
if [ ! -s "$proxy_dir/ipv6.list" ]; then
  for i in $(seq 1 "$proxy_count"); do
      rnd_subnet_ip >> "$proxy_dir/ipv6.list"
  done
fi

# Create 3proxy config with random login and password
cat > "$proxy_dir/3proxy.cfg" <<EOF
daemon
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth strong
EOF

# Add random user credentials and proxy configuration to 3proxy config
for i in $(seq 0 $((proxy_count-1))); do
  generate_random_credentials
  ipv6_address=$(sed "${i}q;d" "$proxy_dir/ipv6.list")
  if [ -n "$ipv6_address" ]; then
    echo "users $random_user:CL:$random_pass" >> "$proxy_dir/3proxy.cfg"
    echo "proxy -6 -n -a -p$((start_port + i)) -i127.0.0.1 -e$ipv6_address" >> "$proxy_dir/3proxy.cfg"
  else
    echo "Error: Missing IPv6 address for proxy $i"
    exit 1
  fi
done

# Start 3proxy
ulimit -n 600000
ulimit -u 600000
"$proxy_dir/3proxy/bin/3proxy" "$proxy_dir/3proxy.cfg" &

# Write proxies to file
backconnect_ipv4=$(curl -s https://ipinfo.io/ip)
last_port=$((start_port + proxy_count - 1))
write_backconnect_proxies_to_file

# Display final message
echo "Файл с прокси создан по адресу - $proxy_dir/proxy.txt"
