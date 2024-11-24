#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

echo "======================="
echo "  开始安装 Docker"
echo "  ./docker.sh 172.18.0.1 172.18.0.0/16"
echo "======================="

# 尝试从参数或标准输入读取 gateway
if [ -n "$1" ]; then
    gateway="$1"
elif [ ! -t 0 ]; then
    read gateway
fi

# 如果没有获取到 gateway，则提示用户输入
if [ -z "$gateway" ]; then
    read -p "请输入 Docker net 网络的网关地址（例如 172.18.0.1）: " gateway < /dev/tty
fi

# 检查 gateway 是否为空
if [ -z "$gateway" ]; then
    echo "错误：未提供网关地址。退出安装。"
    exit 1
fi

# 尝试从第二个参数读取 subnet
if [ -n "$2" ]; then
    subnet="$2"
elif [ ! -t 0 ]; then
    read subnet
fi

# 如果没有获取到 subnet，则提示用户输入
if [ -z "$subnet" ]; then
    read -p "请输入 Docker net 网络的子网地址（例如 172.18.0.0/16）: " subnet < /dev/tty
fi

# 检查 subnet 是否为空
if [ -z "$subnet" ]; then
    echo "错误：未提供子网地址。退出安装。"
    exit 1
fi

echo "使用的网关地址: $gateway"
echo "使用的子网地址: $subnet"

# 安装 Docker
apt install -y docker.io
apt install -y docker-compose

# 启动 Docker 并设置开机自启
systemctl enable docker
systemctl start docker

echo ""
echo ""
echo ""
# 创建 Docker 网络
docker network create -d bridge --gateway "172.18.0.1" --subnet "172.18.0.0/16" "local"
docker network rm net
docker network create -d bridge --gateway "$gateway" --subnet "$subnet" "net"
docker network ls
echo ""
echo ""
echo ""

echo "======================="
echo "  安装 Docker 完成"
echo "  Docker 网络 [ net => $subnet ]"
echo "  使用的网关地址: $gateway"
echo "  使用的子网地址: $subnet"
echo "======================="
