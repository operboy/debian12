#!/bin/bash
# 设置环境变量以抑制交互式提示
export DEBIAN_FRONTEND=noninteractive

# 默认值设置
DEFAULT_SSH_KEY=""
DOCKER_SUBNET="10.77.1.0/24"
DOCKER_IP="10.77.1.1"
SWAP_SIZE="4G"
SSH_PORT="22" # 默认 SSH 端口
REBOOT_AFTER_INSTALL=true
CN_MODE=false # 默认不启用国内模式

# 默认防火墙配置
DEFAULT_TCP_PORTS="80,443,20000-30000" # TCP 默认端口
DEFAULT_UDP_PORTS="" # UDP 默认端口（默认不开放）
DEFAULT_WHITELIST_IPS="" # 默认白名单 IP
DEFAULT_LOCAL_IPS="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" # 默认内网 IP

# 检查依赖工具
REQUIRED_TOOLS=("ipcalc" "curl" "gawk")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &>/dev/null; then
        apt update && apt install -y ipcalc gawk curl
    fi
done

get_current_network_info() {
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$DEFAULT_IFACE" ]; then
        echo "警告: 无法获取默认网卡"
        return 1
    fi
    CURRENT_IP=$(ip addr show $DEFAULT_IFACE | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    CURRENT_CIDR=$(ip addr show $DEFAULT_IFACE | grep 'inet ' | awk '{print $2}' | cut -d/ -f2)
    CURRENT_NETMASK=$(ipcalc "$CURRENT_IP/$CURRENT_CIDR" | grep -w "Netmask" | awk '{print $2}')
    CURRENT_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
    echo "当前网络配置:"
    echo "  网卡: $DEFAULT_IFACE"
    echo "  IP地址: $CURRENT_IP"
    echo "  子网掩码: $CURRENT_NETMASK"
    echo "  网关: $CURRENT_GATEWAY"
}


ask_use_current_network() {
    if [ -z "$IP" ] || [ -z "$NETMASK" ] || [ -z "$GATEWAY" ]; then
        echo
        echo "未指定完整的网络配置，检测到当前系统网络信息："
        get_current_network_info
        echo
        read -p "是否使用当前网络配置？(y/n) " USE_CURRENT
        if [[ $USE_CURRENT =~ ^[Yy]$ ]]; then
            IP=$CURRENT_IP
            NETMASK=$CURRENT_NETMASK
            GATEWAY=$CURRENT_GATEWAY
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
    echo "  -swap <size>           设置Swap大小 (默认: ${SWAP_SIZE}, 例如: 2G, 4G)"
    echo "  -cn                    启用国内模式，1.sh 后加参数 -s 1"
    echo "  -no-reboot             安装后不重启"
    echo "  -h, --help             显示帮助信息"
    exit 1
}

# 参数解析
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -password) PASSWORD="$2"; shift 2 ;;
        -ip) IP="$2"; shift 2 ;;
        -netmask) NETMASK="$2"; shift 2 ;;
        -gateway) GATEWAY="$2"; shift 2 ;;
        -ssh-key) SSH_KEY="$2"; shift 2 ;;
        -ssh-port) SSH_PORT="$2"; shift 2 ;;
        -tcp) TCP_PORTS="$2"; shift 2 ;;
        -udp) UDP_PORTS="$2"; shift 2 ;;
        -whitelist) WHITELIST_IPS="$2"; shift 2 ;;
        -local) LOCAL_IPS="$2"; shift 2 ;;
        -docker-gateway) DOCKER_IP="$2"; shift 2 ;;
        -docker-subnet) DOCKER_SUBNET="$2"; shift 2 ;;
        -swap) SWAP_SIZE="$2"; shift 2 ;;
        -cn) CN_MODE=true; shift ;;
        -no-reboot) REBOOT_AFTER_INSTALL=false; shift ;;
        -h|--help) usage ;;
        *) echo "未知参数: $1"; usage ;;
    esac
done

if [ -z "$PASSWORD" ]; then
    echo "错误: 必须指定密码 (-password)"
    usage
fi

# 设置默认值（如果未提供参数）
TCP_PORTS=${TCP_PORTS:-$DEFAULT_TCP_PORTS}
UDP_PORTS=${UDP_PORTS:-$DEFAULT_UDP_PORTS}
WHITELIST_IPS=${WHITELIST_IPS:-$DEFAULT_WHITELIST_IPS}
LOCAL_IPS=${LOCAL_IPS:-$DEFAULT_LOCAL_IPS}

ask_use_current_network
SSH_KEY=${SSH_KEY:-$DEFAULT_SSH_KEY}

# 动态生成 SSH 公钥（如果未提供）
if [ -z "$SSH_KEY" ]; then
    echo "未指定 SSH 公钥，正在生成临时密钥..."
    ssh-keygen -t rsa -b 2048 -f /tmp/temp_ssh_key -N "" -q
    SSH_KEY=$(cat /tmp/temp_ssh_key.pub)
    echo "生成的临时 SSH 公钥: $SSH_KEY"
fi

# 设置下载链接和参数
BASE_URL="https://raw.githubusercontent.com"
if $CN_MODE; then
    BASE_URL="https://raw.githubusercontent.com"
fi

SYSTEM_Init_SCRIPT="${BASE_URL}/operboy/debian12/refs/heads/main/system/2.sh?$(date +%s)"
SYSTEM_SSH_SCRIPT="${BASE_URL}/operboy/debian12/refs/heads/main/system/ssh.sh?$(date +%s)"
SYSTEM_SYSCTL_SCRIPT="${BASE_URL}/operboy/debian12/refs/heads/main/system/sysctl.sh?$(date +%s)"
SYSTEM_DOCKER_SCRIPT="${BASE_URL}/operboy/debian12/refs/heads/main/system/docker.sh?$(date +%s)"
SYSTEM_UFW_SCRIPT="${BASE_URL}/operboy/debian12/refs/heads/main/system/ufw.sh?$(date +%s)"
DEBI_SCRIPT_URL="${BASE_URL}/bohanyang/debi/master/debi.sh"

# 根据 CN_MODE 动态设置 1.sh 的执行参数
if $CN_MODE; then
    SYSTEM_1_COMMAND="curl \"$SYSTEM_Init_SCRIPT\" | bash -s '-cn' "
else
    SYSTEM_1_COMMAND="curl \"$SYSTEM_Init_SCRIPT\" | bash"
fi

# 生成随机主机名
generate_random_hostname() {
    PREFIX="host"
    RANDOM_SUFFIX=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)
    echo "${PREFIX}-${RANDOM_SUFFIX}"
}

# 使用生成的随机主机名
RANDOM_HOSTNAME=$(generate_random_hostname)
echo "生成的随机主机名: ${RANDOM_HOSTNAME}"

# 创建必要的 Cloud-Init 文件
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
    permissions: '0644'

  # 创建一个空的日志目录
  - path: /var/log/cloud-init-scripts/
    content: ""
    permissions: '0755'
    owner: root:root
    type: directory

runcmd:
  # Swap 配置
  - [ sh, -c, 'echo "[$(date)] 开始配置 Swap..." >> /var/log/cloud-init-scripts/swap.log && { [ ! -e /swapfile ] && { fallocate -l ${SWAP_SIZE} /swapfile && chmod 0600 /swapfile && mkswap /swapfile; } || { echo "创建 Swap 文件失败"; exit 1; }; systemctl daemon-reload && systemctl enable --now swapfile.swap; } >> /var/log/cloud-init-scripts/swap.log 2>&1 && echo "[$(date)] Swap 配置完成" >> /var/log/cloud-init-scripts/swap.log' ]

  # 系统初始化脚本
  - [ sh, -c, 'echo "[$(date)] 开始执行系统初始化脚本..." >> /var/log/cloud-init-scripts/system-init.log && { which curl unzip >/dev/null 2>&1 || (apt update && apt install curl unzip -y) && ${SYSTEM_1_COMMAND}; } >> /var/log/cloud-init-scripts/system-init.log 2>&1 && echo "[$(date)] 系统初始化脚本执行完成" >> /var/log/cloud-init-scripts/system-init.log' ]

  # SSH 配置
  - [ sh, -c, 'echo "[$(date)] 开始配置 SSH..." >> /var/log/cloud-init-scripts/ssh.log && { curl "${SYSTEM_SSH_SCRIPT}" | bash -s "${SSH_PORT}"; } >> /var/log/cloud-init-scripts/ssh.log 2>&1 && echo "[$(date)] SSH 配置完成" >> /var/log/cloud-init-scripts/ssh.log' ]

  # Sysctl 配置
  - [ sh, -c, 'echo "[$(date)] 开始配置 Sysctl..." >> /var/log/cloud-init-scripts/sysctl.log && { curl "${SYSTEM_SYSCTL_SCRIPT}" | bash; } >> /var/log/cloud-init-scripts/sysctl.log 2>&1 && echo "[$(date)] Sysctl 配置完成" >> /var/log/cloud-init-scripts/sysctl.log' ]

  # Docker 配置
  - [ sh, -c, 'echo "[$(date)] 开始配置 Docker..." >> /var/log/cloud-init-scripts/docker.log && { curl "${SYSTEM_DOCKER_SCRIPT}" | bash -s "${DOCKER_IP}" "${DOCKER_SUBNET}"; } >> /var/log/cloud-init-scripts/docker.log 2>&1 && echo "[$(date)] Docker 配置完成" >> /var/log/cloud-init-scripts/docker.log' ]

  # UFW 配置
  - [ sh, -c, 'echo "[$(date)] 开始配置 UFW..." >> /var/log/cloud-init-scripts/ufw.log && { curl "${SYSTEM_UFW_SCRIPT}" | bash -s -- -p "${SSH_PORT},${TCP_PORTS}" -u "${UDP_PORTS}" -w "${WHITELIST_IPS}" -l "${LOCAL_IPS}"; } >> /var/log/cloud-init-scripts/ufw.log 2>&1 && echo "[$(date)] UFW 配置完成" >> /var/log/cloud-init-scripts/ufw.log' ]

  # 添加汇总日志检查命令
  - [ sh, -c, 'echo "[$(date)] Cloud-init 脚本执行完成，日志汇总：" > /var/log/cloud-init-scripts/summary.log && for f in /var/log/cloud-init-scripts/*.log; do echo "=== \${f} ===" >> /var/log/cloud-init-scripts/summary.log && cat "\${f}" >> /var/log/cloud-init-scripts/summary.log && echo >> /var/log/cloud-init-scripts/summary.log; done' ]
EOF


# 下载并执行 debi.sh
echo "开始下载 debi.sh..."
if ! curl -fLO ${DEBI_SCRIPT_URL}; then
    echo "错误: 无法下载 debi.sh，请检查网络连接"
    exit 1
fi
chmod a+rx debi.sh

# 构建 debi.sh 命令
DEBI_CMD="./debi.sh --grub-timeout 1 --cdn --network-console --ethx --bbr --dns '1.1.1.1 8.8.8.8' --cidata /root/cidata --user root --password '${PASSWORD}'"
if [ ! -z "$IP" ]; then
    DEBI_CMD="$DEBI_CMD --ip '${IP}'"
fi
if [ ! -z "$NETMASK" ]; then
    DEBI_CMD="$DEBI_CMD --netmask '${NETMASK}'"
fi
if [ ! -z "$GATEWAY" ]; then
    DEBI_CMD="$DEBI_CMD --gateway '${GATEWAY}'"
fi
if $CN_MODE; then
    DEBI_CMD="$DEBI_CMD --ustc"
fi

echo "执行命令："
echo "$DEBI_CMD"
if ! eval $DEBI_CMD; then
    echo "错误: debi.sh 执行失败"
    exit 1
fi

get_all_network_info() {
    echo "当前系统网络配置信息："
    echo "----------------------------------------"

    # 遍历所有有效网卡
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -Ev '^(lo|docker|veth|br-|tun|virbr)'); do
        IP_INFO=$(ip addr show $iface | grep 'inet ' | head -n1)
        IP_ADDR=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f1)
        CIDR=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f2)
        GATEWAY=$(ip route show dev $iface | grep default | awk '{print $3}')
        NETMASK=$(ipcalc "$IP_ADDR/$CIDR" | grep -w "Netmask" | awk '{print $2}')

        echo "网卡: $iface"
        echo "  IP地址: ${IP_ADDR:-未分配}"
        echo "  子网掩码: ${NETMASK:-未分配}"
        echo "  网关: ${GATEWAY:-未配置}"
        echo "----------------------------------------"
    done

    echo
    echo "当前 /etc/network/interfaces 文件内容："
    echo "----------------------------------------"
    cat /etc/network/interfaces
    echo "----------------------------------------"
    echo

    echo "# Debian 网络配置命令（复制以下全部内容）："
    echo "cat > /etc/network/interfaces << 'EOF'"
    echo "source /etc/network/interfaces.d/*"
    echo "auto lo"
    echo "iface lo inet loopback"
    echo

    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -Ev '^(lo|docker|veth|br-|tun|virbr)'); do
        IP_INFO=$(ip addr show $iface | grep 'inet ' | head -n1)
        IP_ADDR=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f1)
        GATEWAY=$(ip route show dev $iface | grep default | awk '{print $3}')
        NETMASK=$(ipcalc "$IP_ADDR/$CIDR" | grep -w "Netmask" | awk '{print $2}')

        if [[ -n "$IP_ADDR" ]]; then
            echo "auto $iface"
            echo "iface $iface inet static"
            echo "    address $IP_ADDR"
            echo "    netmask $NETMASK"
            [[ -n "$GATEWAY" ]] && echo "    gateway $GATEWAY"
            echo
        fi
    done

    echo "EOF"
    echo
    echo "# 重启网络服务命令："
    echo "systemctl restart networking"
}


get_all_network_info


# 重启逻辑
if $REBOOT_AFTER_INSTALL; then
    echo "安装完成，系统将在 5 秒后重启..."
    sleep 5
    reboot
else
    echo "安装完成，请手动重启系统"
fi
