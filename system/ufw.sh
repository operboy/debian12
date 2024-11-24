#!/bin/bash
# 描述: UFW防火墙快速配置脚本
# 功能:
#   1. 支持单端口(如:80,443)
#   2. 支持端口范围(如:20000-30000)
#   3. 支持IP白名单
#   4. 支持内网IP设置
# 
# 使用方法:
#   curl -s https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/system/ufw.sh | bash -s -- [选项]
#
# 参数说明:
#   -p,--ports '端口列表'    示例: '80,443,20000-30000,55000-55599'
#   -w,--whitelist 'IP列表'  示例: '1.2.3.0/24,2.3.4.0/24'
#   -l,--lan-ips '内网IP'    示例: '10.0.0.0/8,172.16.0.0/12'
#
# 使用示例:
#   curl -s https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/system/ufw.sh | bash -s -- \
#   -p '80,443,20000-30000' \
#   -w '1.2.3.0/24,6.7.8.0/24' \
#   -l '10.0.0.0/8,172.16.0.0/12,192.168.0.0/16'

PORTS=""
WHITELIST_IPS=""
LAN_IPS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--ports) PORTS="$2"; shift 2 ;;
        -w|--whitelist) WHITELIST_IPS="$2"; shift 2 ;;
        -l|--lan-ips) LAN_IPS="$2"; shift 2 ;;
        *) echo "未知选项: $1"; exit 1 ;;
    esac
done

[ "$(id -u)" -ne 0 ] && echo "需要root权限" && exit 1

apt update && apt install -y ufw
echo 'y' | ufw reset
ufw default deny incoming
ufw default allow outgoing

if [ ! -z "$PORTS" ]; then
    IFS=',' read -ra PORT_RANGES <<< "$PORTS"
    for range in "${PORT_RANGES[@]}"; do
        if [[ $range =~ ^([0-9]+)-([0-9]+)$ ]]; then
            ufw allow ${BASH_REMATCH[1]}:${BASH_REMATCH[2]}/tcp
            ufw allow ${BASH_REMATCH[1]}:${BASH_REMATCH[2]}/udp
        else
            ufw allow $range/tcp
            ufw allow $range/udp
        fi
    done
fi

if [ ! -z "$WHITELIST_IPS" ]; then
    IFS=',' read -ra IP_LIST <<< "$WHITELIST_IPS"
    for ip in "${IP_LIST[@]}"; do
        ufw allow from "$ip"
    done
fi

if [ ! -z "$LAN_IPS" ]; then
    IFS=',' read -ra LAN_IP_LIST <<< "$LAN_IPS"
    for ip in "${LAN_IP_LIST[@]}"; do
        ufw allow from "$ip"
    done
fi

ufw --force enable
systemctl enable ufw
systemctl start ufw
ufw status verbose
