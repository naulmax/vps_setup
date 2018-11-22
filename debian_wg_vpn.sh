#!/bin/bash



SUBNET=10.0.0
################

umask 077

# 更新软件包源
apt update

# 安装和 linux-image 内核版本相对于的 linux-headers 内核
apt install linux-headers-$(uname -r) -y

# Debian9 安装后内核列表
dpkg -l|grep linux-headers

# 安装WireGuard

# 添加 unstable 软件包源，以确保安装版本是最新的
echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list
echo -e 'Package: *\nPin: release a=unstable\nPin-Priority: 150' > /etc/apt/preferences.d/limit-unstable
 
# 更新一下软件包源
apt update
 
# 开始安装 WireGuard
apt install -y wireguard resolvconf dnsutils

# 验证是否安装成功
modprobe wireguard && lsmod | grep wireguard

# 配置 WireGuard服务端

# 首先进入配置文件目录
wg-quick down wg0 2>/dev/null
mkdir -p /etc/wireguard
rm -rf /etc/wireguard/*
cd /etc/wireguard

# 然后开始生成 密匙对(公匙+私匙)。
wg genkey | tee server_priv | wg pubkey > server_pub
wg genkey | tee client_priv | wg pubkey > client_pub

echo $SUBNET > /etc/wireguard/subnet

PORT=$(rand 10000 60000)
	
	SERVER_PUB=$(cat server_pub)
	SERVER_PRIV=$(cat server_priv)
	CLIENT_PUB=$(cat client_pub)
CLIENT_PRIV=$(cat client_priv)

echo $SERVER_PUB > /etc/wireguard/server_pubkey

# 获得服务器ip
SERVER_PUBLIC_IP=$(curl ipinfo.io/ip)

# 生成服务端配置文件

echo "[Interface]
PrivateKey = $(cat server_priv)
Address = 10.0.0.1/24 
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ListenPort = $PORT
DNS = 1.1.1.1
MTU = 1300

[Peer]
PublicKey = $(cat client_pub)
AllowedIPs = 10.0.0.2/32" > wg0.conf

# 生成客户端配置文件

echo "[Interface]
PrivateKey = $(cat client_priv)
Address = 10.0.0.2/24
DNS = 1.1.1.1
MTU = 1300

[Peer]
PublicKey = $(cat server_pub)
Endpoint = $serverip:50000
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25"|sed '/^#/d;/^\s*$/d' > client.conf

# 再次生成简洁的客户端配置
echo "
[Interface]
PrivateKey = $(cat server_priv)
Address = 10.0.0.2/24
DNS = 1.1.1.1
MTU = 1300

[Peer]
PublicKey = $(cat client_priv)
Endpoint = $serverip:9009
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25

" > client.conf

# 赋予配置文件夹权限
chmod 777 -R /etc/wireguard

sysctl_config() {
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
}

# 开启 BBR
sysctl_config
lsmod | grep bbr
 
# 打开防火墙转发功能
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# 启动WireGuard
wg-quick save wg0
wg-quick ip wg0

# 设置开机启动
systemctl enable wg-quick@wg0

# 查询WireGuard状态
wg

# 显示配置文件，可以修改里面的实际IP
cat /etc/wireguard/client.conf

