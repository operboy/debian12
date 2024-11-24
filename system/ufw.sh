#!/bin/bash
# 设置环境变量以抑制交互式提示
export DEBIAN_FRONTEND=noninteractive

# 描述: 修复后的 UFW 防火墙快速配置脚本（仅支持 IPv4）
# 功能:
#   1. 支持单端口(如:80,443)
#   2. 支持端口范围(如:20000-30000)
#   3. 支持IP白名单
#   4. 支持内网IP设置
#   5. 默认只开放TCP端口，UDP需要特别指定
#   6. 支持ICMP（Ping）
#
# 使用方法:
#   ./ufw.sh -p '80,443,20000-30000' -u '53,67-68' -w '1.2.3.0/24,6.7.8.0/24' -l '10.0.0.0/8,172.16.0.0/12'

PORTS=""
UDP_PORTS=""
WHITELIST_IPS=""
LAN_IPS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--ports) PORTS="$2"; shift 2 ;;
        -u|--udp) UDP_PORTS="$2"; shift 2 ;;
        -w|--whitelist) WHITELIST_IPS="$2"; shift 2 ;;
        -l|--lan-ips) LAN_IPS="$2"; shift 2 ;;
        *) echo "未知选项: $1"; exit 1 ;;
    esac
done

# 检查是否为root用户
[ "$(id -u)" -ne 0 ] && echo "需要root权限" && exit 1

# 禁用 IPv6 支持
sed -i 's/^IPV6=yes/IPV6=no/' /etc/default/ufw

# 安装并启用 UFW
apt update && apt install -y ufw
echo 'y' | ufw reset
ufw default deny incoming
ufw default allow outgoing

# 处理TCP端口
if [ -n "$PORTS" ]; then
    IFS=',' read -ra PORT_RANGES <<< "$PORTS"
    for range in "${PORT_RANGES[@]}"; do
        if [[ $range =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start_port="${BASH_REMATCH[1]}"
            end_port="${BASH_REMATCH[2]}"
            ufw allow $start_port:$end_port/tcp comment "开放端口范围 $start_port-$end_port TCP"
        else
            ufw allow $range/tcp comment "开放端口 $range TCP"
        fi
    done
fi

# 处理UDP端口
if [ -n "$UDP_PORTS" ]; then
    IFS=',' read -ra UDP_PORT_RANGES <<< "$UDP_PORTS"
    for range in "${UDP_PORT_RANGES[@]}"; do
        if [[ $range =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start_port="${BASH_REMATCH[1]}"
            end_port="${BASH_REMATCH[2]}"
            ufw allow $start_port:$end_port/udp comment "开放端口范围 $start_port-$end_port UDP"
        else
            ufw allow $range/udp comment "开放端口 $range UDP"
        fi
    done
fi

# 处理白名单IP
if [ -n "$WHITELIST_IPS" ]; then
    IFS=',' read -ra IP_LIST <<< "$WHITELIST_IPS"
    for ip in "${IP_LIST[@]}"; do
        ufw allow from "$ip" comment "白名单IP: $ip"
    done
fi

# 处理内网IP
if [ -n "$LAN_IPS" ]; then
    IFS=',' read -ra LAN_IP_LIST <<< "$LAN_IPS"
    for ip in "${LAN_IP_LIST[@]}"; do
        ufw allow from "$ip" comment "内网IP: $ip"
    done
fi

# 允许ICMP（Ping）
ufw allow proto icmp comment "允许ICMP（Ping）"

# 启用日志记录
ufw logging on

# 启用并启动 UFW
ufw --force enable
systemctl enable ufw
systemctl start ufw

# 显示状态
ufw status verbose