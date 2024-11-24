#!/bin/bash

# 脚本名称: ufw.sh
# 描述: 配置UFW防火墙规则，支持端口范围和IP白名单设置
# 使用方法: curl -s https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/system/ufw.sh | bash -s -- [选项]
# 选项:
#   -p,--ports '端口范围'    示例: '20000-30000,50000-60000'
#   -w,--whitelist 'IP列表'  示例: '1.2.3.0/24,2.3.4.0/24'
#   -l,--lan-ips '内网IP'    示例: '10.0.0.0/8,172.16.0.0/12'
#
# 示例:
#   基础用法:
#   curl -s https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/system/ufw.sh | bash -s -- \
#        -p '20000-30000,50000-60000' \
#        -w '1.2.3.0/24,2.3.4.0/24' \
#        -l '10.0.0.0/8,172.16.0.0/12'
#
#   仅配置端口:
#   curl -s https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/system/ufw.sh | bash -s -- -p '20000-30000'
#
#   仅配置IP白名单:
#   curl -s https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/system/ufw.sh | bash -s -- -w '1.2.3.0/24'

# 显示帮助信息函数
show_help() {
    echo "用法: curl -s https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/system/ufw.sh | bash -s -- [选项]"
    echo "选项:"
    echo "  -p, --ports '端口范围列表'    设置允许的端口范围，格式：'20000-30000,50000-60000'"
    echo "  -w, --whitelist 'IP列表'      设置允许访问的IP/IP段，格式：'1.2.3.0/24,2.3.4.0/24'"
    echo "  -l, --lan-ips '内网IP列表'    设置允许的内网IP，格式：'10.0.0.0/8,172.16.0.0/12'"
    echo
    echo "示例:"
    echo "curl -s https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/system/ufw.sh | bash -s -- -p '20000-30000,50000-60000' -w '1.2.3.0/24'"
}

# 默认值初始化
PORTS=""
WHITELIST_IPS=""
LAN_IPS=""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--ports)
            PORTS="$2"
            shift 2
            ;;
        -w|--whitelist)
            WHITELIST_IPS="$2"
            shift 2
            ;;
        -l|--lan-ips)
            LAN_IPS="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# root权限检查
if [ "$(id -u)" -ne 0 ]; then
    echo "请以 root 用户身份运行此脚本。"
    exit 1
fi

# 安装和配置UFW
echo "更新软件包列表并安装 UFW..."
apt update && apt install -y ufw

echo "重置 UFW 配置..."
#echo 'y' | ufw reset && ufw disable && rm -rf /etc/ufw/*.rules.* /var/lib/ufw/*.rules.* /etc/ufw/user.rules.* && echo "UFW已完全重置且无备份"
echo 'y' | ufw reset

echo "设置默认策略：拒绝所有传入，允许所有传出..."
ufw default deny incoming
ufw default allow outgoing

# 配置端口范围
if [ ! -z "$PORTS" ]; then
    echo "配置允许的端口范围..."
    IFS=',' read -ra PORT_RANGES <<< "$PORTS"
    for range in "${PORT_RANGES[@]}"; do
        if [[ $range =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start_port="${BASH_REMATCH[1]}"
            end_port="${BASH_REMATCH[2]}"
            echo "允许端口范围 $start_port-$end_port..."
            ufw allow $start_port:$end_port/tcp
            ufw allow $start_port:$end_port/udp
        else
            echo "警告: 无效的端口范围格式: $range"
        fi
    done
fi

# 配置IP白名单
if [ ! -z "$WHITELIST_IPS" ]; then
    echo "配置IP白名单..."
    IFS=',' read -ra IP_LIST <<< "$WHITELIST_IPS"
    for ip in "${IP_LIST[@]}"; do
        echo "允许IP/IP段: $ip"
        ufw allow from "$ip" comment '白名单IP允许访问'
    done
fi

# 配置内网IP
if [ ! -z "$LAN_IPS" ]; then
    echo "配置内网IP..."
    IFS=',' read -ra LAN_IP_LIST <<< "$LAN_IPS"
    for ip in "${LAN_IP_LIST[@]}"; do
        echo "允许内网IP: $ip"
        ufw allow from "$ip" comment 'LAN 允许访问'
    done
fi

# 启用UFW并设置开机启动
echo "启用 UFW..."
ufw --force enable

echo "设置 UFW 开机启动..."
systemctl enable ufw
systemctl start ufw

# 显示配置结果
echo "UFW 状态和规则："
ufw status verbose

echo "UFW 配置完成。"
