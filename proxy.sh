#!/bin/bash

# Function to delete file if it exists
delete_file_if_exists() {
  if [ -f "$1" ]; then
    rm "$1"
  fi
}

# Function to install 3proxy
install_3proxy() {
  cd "$proxy_dir"

  echo -e "\nDownloading proxy server source..."
  wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz
  tar -xf 0.9.4.tar.gz
  rm 0.9.4.tar.gz

  # Remove old installation if exists
  rm -rf 3proxy
  mv 3proxy-0.9.4 3proxy
  echo "Proxy server source code downloaded successfully"

  echo -e "\nStart building proxy server execution file from source..."
  cd 3proxy
  make -f Makefile.Linux
  if [ -f "bin/3proxy" ] || [ -f "src/3proxy" ]; then
    echo "Proxy server built successfully"
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

# Function to generate random IPv6 addresses
generate_random_ipv6() {
  array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
  echo -n "$subnet_base:$(printf "%x\n" $((RANDOM % 65536))):$(printf "%x\n" $((RANDOM % 65536))):$(printf "%x\n" $((RANDOM % 65536))):"
  for i in {1..4}; do
      echo -n ${array[$RANDOM % 16]}
  done
}

# Function to populate IPv6 list
populate_ipv6_list() {
  ipv6_list=()
  for i in $(seq 1 "$proxy_count"); do
    ipv6_addr=$(generate_random_ipv6)
    if [ -n "$ipv6_addr" ]; then
      ipv6_list+=("$ipv6_addr")
    else
      echo "Error: Failed to generate IPv6 address for proxy $i"
      exit 1
    fi
  done
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
  ip -6 route add default via "$gateway" dev "$interface_name"
else
  echo "Route already exists"
fi

# Populate IPv6 addresses into an array
populate_ipv6_list

# Ensure IPv6 addresses were generated
if [ ${#ipv6_list[@]} -eq 0 ]; then
  echo "Error: IPv6 address list is empty."
  exit 1
fi

# Create 3proxy config
config_file="$proxy_dir/3proxy.cfg"
delete_file_if_exists "$config_file"
cat > "$config_file" <<EOF
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
  ipv6_address="${ipv6_list[$i]}"
  
  # Ensure IPv6 address exists for the current proxy
  if [ -n "$ipv6_address" ]; then
    echo "users $random_user:CL:$random_pass" >> "$config_file"
    echo "proxy -6 -n -a -p$((start_port + i)) -i127.0.0.1 -e$ipv6_address" >> "$config_file"
    echo "Added proxy with IPv6 address: $ipv6_address"
  else
    echo "Error: Missing IPv6 address for proxy $i"
    exit 1
  fi
done

# Start 3proxy
ulimit -n 600000
ulimit -u 600000
"$proxy_dir/3proxy/bin/3proxy" "$config_file" &

# Write proxies to file
backconnect_ipv4=$(curl -s https://ipinfo.io/ip)
last_port=$((start_port + proxy_count - 1))
proxy_file="$proxy_dir/proxy.txt"
delete_file_if_exists "$proxy_file"
for port in $(eval echo "{$start_port..$last_port}"); do
    echo "$backconnect_ipv4:$port:$random_user:$random_pass" >> "$proxy_file"
done

# Display final message
echo "Файл с прокси создан по адресу - $proxy_file"
