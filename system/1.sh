#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y ipcalc curl awk

# 定义全局变量
DEFAULT_SSH_KEY=""
DOCKER_SUBNET="10.77.1.0/24"
DOCKER_IP="10.77.1.1"
SWAP_SIZE="4G"
SSH_PORT="22"
REBOOT_AFTER_INSTALL=true
CN_MODE=false
DEFAULT_TCP_PORTS="80,443,20000-30000,55000-55599"
DEFAULT_UDP_PORTS=""
DEFAULT_WHITELIST_IPS="118.99.2.0/24,138.199.62.0/24,156.146.45.0/24,89.187.163.0/24,149.88.106.0/24,103.216.223.0/24,86.107.104.0/24,138.199.24.0/24,156.146.57.0/24"
DEFAULT_LOCAL_IPS="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m'

# 根据CIDR获取子网掩码
get_netmask() {
    local CIDR=$1
    case "$CIDR" in
        "32") echo "255.255.255.255" ;;
        "31") echo "255.255.255.254" ;;
        "30") echo "255.255.255.252" ;;
        "29") echo "255.255.255.248" ;;
        "28") echo "255.255.255.240" ;;
        "27") echo "255.255.255.224" ;;
        "26") echo "255.255.255.192" ;;
        "25") echo "255.255.255.128" ;;
        "24") echo "255.255.255.0" ;;
        "23") echo "255.255.254.0" ;;
        "22") echo "255.255.252.0" ;;
        "21") echo "255.255.248.0" ;;
        "20") echo "255.255.240.0" ;;
        "19") echo "255.255.224.0" ;;
        "18") echo "255.255.192.0" ;;
        "17") echo "255.255.128.0" ;;
        "16") echo "255.255.0.0" ;;
        "15") echo "255.254.0.0" ;;
        "14") echo "255.252.0.0" ;;
        "13") echo "255.248.0.0" ;;
        "12") echo "255.240.0.0" ;;
        "11") echo "255.224.0.0" ;;
        "10") echo "255.192.0.0" ;;
        "9") echo "255.128.0.0" ;;
        "8") echo "255.0.0.0" ;;
        *) echo "255.255.255.0" ;;
    esac
}

# 获取网络信息的统一函数
get_network_info() {
    local iface=$1
    local IP_INFO=$(ip addr show $iface | grep 'inet ' | head -n1)
    local IP_ADDR=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f1)
    local CIDR=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f2)
    local GATEWAY=$(ip route show dev $iface | grep default | awk '{print $3}')
    local NETMASK=$(get_netmask "$CIDR")
    
    echo -e "  ${CYAN}网卡:${NC} ${YELLOW}$iface${NC}"
    echo -e "    ${CYAN}IP地址:${NC} ${GREEN}${IP_ADDR:-未分配}${NC}"
    echo -e "    ${CYAN}子网掩码:${NC} ${GREEN}${NETMASK:-未分配}${NC}"
    echo -e "    ${CYAN}网关:${NC} ${GREEN}${GATEWAY:-未配置}${NC}"
    echo -e "${GRAY}----------------------------------------${NC}"

    # 返回获取到的值供其他函数使用
    echo "$IP_ADDR:$NETMASK:$GATEWAY"
}

# 获取所有网络信息
get_all_network_info() {
    echo -e "${GREEN}当前系统网络配置信息：${NC}"
    echo -e "${GRAY}----------------------------------------${NC}"

    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -Ev '^(lo|docker|veth|br-|tun|virbr)'); do
        get_network_info "$iface"
    done

    echo
    echo -e "${GREEN}当前 /etc/network/interfaces 文件内容：${NC}"
    echo -e "${GRAY}----------------------------------------${NC}"
    echo -e "${YELLOW}$(cat /etc/network/interfaces)${NC}"
    echo -e "${GRAY}----------------------------------------${NC}"
    echo

    # 生成网络配置命令
    echo -e "${BLUE}# Debian 网络配置命令：${NC}"
    echo -e "${PURPLE}cat > /etc/network/interfaces << 'EOF'${NC}"
    echo -e "${GREEN}source /etc/network/interfaces.d/*"
    echo "auto lo"
    echo -e "iface lo inet loopback${NC}"
    echo

    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -Ev '^(lo|docker|veth|br-|tun|virbr)'); do
        local NET_INFO=$(get_network_info "$iface")
        local IP_ADDR=$(echo "$NET_INFO" | cut -d: -f1)
        local NETMASK=$(echo "$NET_INFO" | cut -d: -f2)
        local GATEWAY=$(echo "$NET_INFO" | cut -d: -f3)

        if [[ -n "$IP_ADDR" ]]; then
            echo -e "${GREEN}auto $iface"
            echo "iface $iface inet static"
            echo "    address $IP_ADDR"
            echo "    netmask $NETMASK"
            [[ -n "$GATEWAY" ]] && echo "    gateway $GATEWAY"
            echo -e "${NC}"
        fi
    done

    echo -e "${PURPLE}EOF${NC}"
    echo
    echo -e "${BLUE}# 重启网络服务命令：${NC}"
    echo -e "${PURPLE}systemctl restart networking${NC}"
}

# 获取当前网络信息
get_current_network_info() {
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    [ -z "$DEFAULT_IFACE" ] && { echo -e "${RED}警告: 无法获取默认网卡${NC}"; return 1; }
    
    local NET_INFO=$(get_network_info "$DEFAULT_IFACE")
    CURRENT_IP=$(echo "$NET_INFO" | cut -d: -f1)
    CURRENT_NETMASK=$(echo "$NET_INFO" | cut -d: -f2)
    CURRENT_GATEWAY=$(echo "$NET_INFO" | cut -d: -f3)
}

# 询问是否使用当前网络配置
ask_use_current_network() {
    if [ -z "$IP" ] || [ -z "$NETMASK" ] || [ -z "$GATEWAY" ]; then
        echo; echo "未指定完整的网络配置，检测到当前系统网络信息："
        get_current_network_info
        echo
        read -p "是否使用当前网络配置？(y/n) " USE_CURRENT
        if [[ $USE_CURRENT =~ ^[Yy]$ ]]; then
            IP=$CURRENT_IP; NETMASK=$CURRENT_NETMASK; GATEWAY=$CURRENT_GATEWAY
            echo "将使用当前网络配置继续安装"
        else
            echo "请使用以下参数指定网络配置："
            echo "  -ip <ip地址>"
            echo "  -netmask <子网掩码>"
            echo "  -gateway <网关>"
            exit 1
        fi
    fi
}

# 显示使用帮助
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -password <password>    设置系统密码"
    echo "  -ip <ip>               设置系统IP地址"
    echo "  -netmask <netmask>     设置子网掩码"
    echo "  -gateway <gateway>      设置网关"
    echo "  -ssh-key <public_key>   设置SSH公钥"
    echo "  -ssh-port <port>       设置SSH端口 (默认: ${SSH_PORT})"
    echo "  -tcp <ports>           设置TCP端口 (默认: ${DEFAULT_TCP_PORTS})"
    echo "  -udp <ports>           设置UDP端口 (默认: ${DEFAULT_UDP_PORTS})"
    echo "  -whitelist <ips>       设置白名单 IP (默认: ${DEFAULT_WHITELIST_IPS})"
    echo "  -local <ips>           设置内网 IP (默认: ${DEFAULT_LOCAL_IPS})"
    echo "  -docker-gateway <ip>   设置Docker IP (默认: ${DOCKER_IP})"
    echo "  -docker-subnet <subnet> 设置Docker子网 (默认: ${DOCKER_SUBNET})"
    echo "  -swap <size>           设置Swap大小 (默认: ${SWAP_SIZE})"
    echo "  -cn                    启用国内模式"
    echo "  -no-reboot             安装后不重启"
    echo "  -h, --help             显示帮助信息"
    exit 1
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -password) PASSWORD="$2"; shift 2;;
        -ip) IP="$2"; shift 2;;
        -netmask) NETMASK="$2"; shift 2;;
        -gateway) GATEWAY="$2"; shift 2;;
        -ssh-key) SSH_KEY="$2"; shift 2;;
        -ssh-port) SSH_PORT="$2"; shift 2;;
        -tcp) TCP_PORTS="$2"; shift 2;;
        -udp) UDP_PORTS="$2"; shift 2;;
        -whitelist) WHITELIST_IPS="$2"; shift 2;;
        -local) LOCAL_IPS="$2"; shift 2;;
        -docker-gateway) DOCKER_IP="$2"; shift 2;;
        -docker-subnet) DOCKER_SUBNET="$2"; shift 2;;
        -swap) SWAP_SIZE="$2"; shift 2;;
        -cn) CN_MODE=true; shift;;
        -no-reboot) REBOOT_AFTER_INSTALL=false; shift;;
        -h|--help) usage;;
        *) echo "未知参数: $1"; usage;;
    esac
done

# 检查必要参数
[ -z "$PASSWORD" ] && { echo "错误: 必须指定密码 (-password)"; usage; }

# 设置默认值
TCP_PORTS=${TCP_PORTS:-$DEFAULT_TCP_PORTS}
UDP_PORTS=${UDP_PORTS:-$DEFAULT_UDP_PORTS}
WHITELIST_IPS=${WHITELIST_IPS:-$DEFAULT_WHITELIST_IPS}
LOCAL_IPS=${LOCAL_IPS:-$DEFAULT_LOCAL_IPS}

# 检查网络配置
ask_use_current_network
SSH_KEY=${SSH_KEY:-$DEFAULT_SSH_KEY}

# 生成SSH密钥（如果未提供）
if [ -z "$SSH_KEY" ]; then
    echo "未指定 SSH 公钥，正在生成临时密钥..."
    ssh-keygen -t rsa -b 2048 -f /tmp/temp_ssh_key -N "" -q
    SSH_KEY=$(cat /tmp/temp_ssh_key.pub)
    echo "生成的临时 SSH 公钥: $SSH_KEY"
fi

# 定义脚本URL
BASE_URL="https://raw.githubusercontent.com"
SYSTEM_Init_SCRIPT="${BASE_URL}/operboy/debian12/refs/heads/main/system/2.sh?$(date +%s)"
SYSTEM_SSH_SCRIPT="${BASE_URL}/operboy/debian12/refs/heads/main/system/ssh.sh?$(date +%s)"
SYSTEM_SYSCTL_SCRIPT="${BASE_URL}/operboy/debian12/refs/heads/main/system/sysctl.sh?$(date +%s)"
SYSTEM_DOCKER_SCRIPT="${BASE_URL}/operboy/debian12/refs/heads/main/system/docker.sh?$(date +%s)"
SYSTEM_UFW_SCRIPT="${BASE_URL}/operboy/debian12/refs/heads/main/system/ufw.sh?$(date +%s)"
DEBI_SCRIPT_URL="${BASE_URL}/bohanyang/debi/master/debi.sh"

# 构建系统初始化命令
SYSTEM_1_COMMAND="curl \"$SYSTEM_Init_SCRIPT\" | bash${CN_MODE:+ -s '-cn'}"

# 生成随机主机名
RANDOM_HOSTNAME="host-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
echo "生成的随机主机名: ${RANDOM_HOSTNAME}"

# 创建cloud-init配置
mkdir -p /root/cidata
touch /root/cidata/meta-data
cat > /root/cidata/user-data <<EOF
#cloud-config
hostname: ${RANDOM_HOSTNAME}
user: debian
disable_root: false
ssh_pwauth: true
password: '${PASSWORD}'
ssh_authorized_keys:
  - ${SSH_KEY}
chpasswd: { expire: false }

write_files:
  - content: |
      [Swap]
      What=/swapfile
      [Install]
      WantedBy=swap.target
    path: /etc/systemd/system/swapfile.swap

runcmd:
  - [ sh, -c, "[ ! -e /swapfile ] && { fallocate -l ${SWAP_SIZE} /swapfile && chmod 0600 /swapfile && mkswap /swapfile; } || { echo '创建 Swap 文件失败'; exit 1; }; systemctl daemon-reload && systemctl enable --now swapfile.swap" ]
  - [ sh, -c, 'which curl unzip >/dev/null 2>&1 || (apt update && apt install curl unzip -y) && ${SYSTEM_1_COMMAND}' ]
  - [ sh, -c, 'curl "${SYSTEM_SSH_SCRIPT}" | bash -s "${SSH_PORT}"' ]
  - [ sh, -c, 'curl "${SYSTEM_SYSCTL_SCRIPT}" | bash' ]
  - [ sh, -c, 'curl "${SYSTEM_DOCKER_SCRIPT}" | bash -s "${DOCKER_IP}" "${DOCKER_SUBNET}"' ]
  - [ sh, -c, 'curl "${SYSTEM_UFW_SCRIPT}" | bash -s -- -p "${SSH_PORT},${TCP_PORTS}" -u "${UDP_PORTS}" -w "${WHITELIST_IPS}" -l "${LOCAL_IPS}"' ]
EOF

# 下载并执行debi.sh
curl -fLO ${DEBI_SCRIPT_URL} || { echo "错误: 无法下载 debi.sh"; exit 1; }
chmod a+rx debi.sh

# 构建debi.sh命令
DEBI_CMD="./debi.sh --cdn --network-console --ethx --bbr --dns '1.1.1.1 8.8.8.8' --cidata /root/cidata --user root --password '${PASSWORD}'"
[ ! -z "$IP" ] && DEBI_CMD="$DEBI_CMD --ip '${IP}'"
[ ! -z "$NETMASK" ] && DEBI_CMD="$DEBI_CMD --netmask '${NETMASK}'"
[ ! -z "$GATEWAY" ] && DEBI_CMD="$DEBI_CMD --gateway '${GATEWAY}'"
$CN_MODE && DEBI_CMD="$DEBI_CMD --ustc"

echo "执行命令：${DEBI_CMD}"
eval $DEBI_CMD || { echo "错误: debi.sh 执行失败"; exit 1; }

# 完成安装
if $REBOOT_AFTER_INSTALL; then
    echo "安装完成，系统将在 5 秒后重启..."
    sleep 5
    reboot
else
    echo "安装完成，请手动重启系统"
fi
