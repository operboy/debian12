#!/bin/bash
# 设置环境变量以抑制交互式提示
export DEBIAN_FRONTEND=noninteractive

# 描述: UFW防火墙快速配置脚本
# 功能:
#   1. 支持单端口(如:80,443)
#   2. 支持端口范围(如:20000-30000)
#   3. 支持IP白名单
#   4. 支持内网IP设置
#
# 使用方法:
#   curl -s "https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/system/ufw.sh?$(date +%s)" | bash -s -- [选项]
#
# 参数说明:
#   -p,--ports '端口列表'    示例: '80,443,20000-30000,55000-55599'
#   -w,--whitelist 'IP列表'  示例: '1.2.3.0/24,2.3.4.0/24'
#   -l,--lan-ips '内网IP'    示例: '10.0.0.0/8,172.16.0.0/12'
#
# 使用示例:
#   curl -s "https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/system/ufw.sh?$(date +%s)" | bash -s -- \
#   -p '80,443,20000-30000' \
#   -w '1.2.3.0/24,6.7.8.0/24' \
#   -l '10.0.0.0/8,172.16.0.0/12,192.168.0.0/16'

# 错误处理函数
error_exit() {
    echo "错误: $1" >&2
    exit 1
}

# 参数解析
PORTS=""
WHITELIST_IPS=""
LAN_IPS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--ports) PORTS="$2"; shift 2 ;;
        -w|--whitelist) WHITELIST_IPS="$2"; shift 2 ;;
        -l|--lan-ips) LAN_IPS="$2"; shift 2 ;;
        *) error_exit "未知选项: $1" ;;
    esac
done

# 检查root权限
[ "$(id -u)" -ne 0 ] && error_exit "需要root权限"

# 安装必要的包
echo "正在安装必要的包..."
apt update || error_exit "apt update 失败"
apt install -y ufw iptables-persistent netfilter-persistent linux-modules-extra-$(uname -r) || error_exit "安装包失败"

# 配置iptables为legacy模式
echo "配置iptables模式..."
update-alternatives --set iptables /usr/sbin/iptables-legacy || error_exit "设置iptables-legacy失败"
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || error_exit "设置ip6tables-legacy失败"

# 加载必要的内核模块
echo "加载内核模块..."
modprobe xt_multiport || error_exit "加载xt_multiport模块失败"
modprobe xt_limit || error_exit "加载xt_limit模块失败"
modprobe xt_conntrack || error_exit "加载xt_conntrack模块失败"
modprobe xt_state || error_exit "加载xt_state模块失败"

# 重置UFW
echo "重置UFW配置..."
echo 'y' | ufw reset
ufw default deny incoming
ufw default allow outgoing

# 配置端口规则
if [ ! -z "$PORTS" ]; then
    echo "配置端口规则..."
    IFS=',' read -ra PORT_RANGES <<< "$PORTS"
    for range in "${PORT_RANGES[@]}"; do
        if [[ $range =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start_port="${BASH_REMATCH[1]}"
            end_port="${BASH_REMATCH[2]}"
            ufw allow "$start_port:$end_port/tcp" comment "开放端口范围 $start_port-$end_port TCP" || error_exit "配置端口范围 $range TCP 失败"
            ufw allow "$start_port:$end_port/udp" comment "开放端口范围 $start_port-$end_port UDP" || error_exit "配置端口范围 $range UDP 失败"
        else
            ufw allow "$range/tcp" comment "开放端口 $range TCP" || error_exit "配置端口 $range TCP 失败"
            ufw allow "$range/udp" comment "开放端口 $range UDP" || error_exit "配置端口 $range UDP 失败"
        fi
    done
fi

# 配置白名单IP
if [ ! -z "$WHITELIST_IPS" ]; then
    echo "配置白名单IP..."
    IFS=',' read -ra IP_LIST <<< "$WHITELIST_IPS"
    for ip in "${IP_LIST[@]}"; do
        ufw allow from "$ip" comment "白名单IP: $ip" || error_exit "配置白名单IP $ip 失败"
    done
fi

# 配置内网IP
if [ ! -z "$LAN_IPS" ]; then
    echo "配置内网IP..."
    IFS=',' read -ra LAN_IP_LIST <<< "$LAN_IPS"
    for ip in "${LAN_IP_LIST[@]}"; do
        ufw allow from "$ip" comment "内网IP: $ip" || error_exit "配置内网IP $ip 失败"
    done
fi

# 启用UFW
echo "启用UFW..."
ufw --force enable || error_exit "启用UFW失败"
systemctl enable ufw || error_exit "设置UFW开机启动失败"
systemctl start ufw || error_exit "启动UFW服务失败"

# 显示配置结果
echo "配置完成，当前UFW状态："
ufw status verbose

echo "UFW配置成功完成！"
