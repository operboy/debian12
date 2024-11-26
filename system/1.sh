#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[信息]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
log_error() { echo -e "${RED}[错误]${NC} $*"; }

# 默认值设置
PASSWORD="Hi8899"
SSH_KEY=""
DOCKER_SUBNET="10.77.1.0/24"
DOCKER_IP="10.77.1.1"
SWAP_SIZE="2G"
SSH_PORT="22"
REBOOT_AFTER_INSTALL=true
CN_MODE=false
DRY_RUN=false
PROXY=""
# 默认防火墙配置
TCP_PORTS="80,443,20000-30000"
UDP_PORTS=""
WHITELIST_IPS=""
LOCAL_IPS="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

# 设置下载链接和参数
BASE_URL="http://repo123.ddnsfree.com"
SYSTEM_INIT_SCRIPT="${BASE_URL}/operboy/debian12/system/2.sh?$(date +%s)"
SYSTEM_SSH_SCRIPT="${BASE_URL}/operboy/debian12/system/ssh.sh?$(date +%s)"
SYSTEM_SYSCTL_SCRIPT="${BASE_URL}/operboy/debian12/system/sysctl.sh?$(date +%s)"
SYSTEM_DOCKER_SCRIPT="${BASE_URL}/operboy/debian12/system/docker.sh?$(date +%s)"
SYSTEM_UFW_SCRIPT="${BASE_URL}/operboy/debian12/system/ufw.sh?$(date +%s)"
DEBI_SCRIPT_URL="${BASE_URL}/operboy/debian12/system/debi.sh"


# 获取网络信息
get_network_info() {
    DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}')
    if [ -z "$DEFAULT_IFACE" ]; then
        log_error "无法获取默认网络接口"
        exit 1
    fi

    local IP_INFO=$(ip addr show $DEFAULT_IFACE | grep 'inet ' | head -n1)
    if [ -z "$IP_INFO" ]; then
        log_error "无法获取网络信息"
        exit 1
    fi

    IP=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f1)
    CIDR=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f2)
    GATEWAY=$(ip route show dev $DEFAULT_IFACE | grep default | awk '{print $3}')

    # 计算子网掩码
    NETMASK=$(printf "%d.%d.%d.%d\n" \
        $(( (0xFFFFFFFF << (32 - CIDR)) >> 24 & 0xFF )) \
        $(( (0xFFFFFFFF << (32 - CIDR)) >> 16 & 0xFF )) \
        $(( (0xFFFFFFFF << (32 - CIDR)) >> 8 & 0xFF )) \
        $(( (0xFFFFFFFF << (32 - CIDR)) & 0xFF )))

    log_info "网络信息获取成功:"
    log_info "接口: $DEFAULT_IFACE"
    log_info "IP: $IP"
    log_info "掩码: $NETMASK"
    log_info "网关: $GATEWAY"
}

# 生成随机主机名
generate_random_hostname() {
    PREFIX="host"
    RANDOM_SUFFIX=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)
    echo "${PREFIX}-${RANDOM_SUFFIX}"
}

# 参数解析
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -password) PASSWORD="$2"; shift 2 ;;
            -cmd) CMD="$2"; shift 2 ;;
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
            -proxy) PROXY="$2"; shift 2 ;;
            -cn) CN_MODE=true; shift ;;
            -dry-run) DRY_RUN=true; shift ;;
            -no-reboot) REBOOT_AFTER_INSTALL=false; shift ;;
            -h|--help) show_usage; exit 0 ;;
            *) log_error "未知参数: $1"; show_usage; exit 1 ;;
        esac
    done
}

# 显示使用帮助
show_usage() {
    echo "使用方法: $0 [选项]"
    echo "选项:"
    echo "  -password <密码>        设置系统密码"
    echo "  -cmd <命令>        扩展执行命令"
    echo "  -ip <IP地址>           设置系统IP"
    echo "  -netmask <掩码>        设置子网掩码"
    echo "  -gateway <网关>        设置默认网关"
    echo "  -ssh-key <密钥>        设置SSH公钥"
    echo "  -ssh-port <端口>       设置SSH端口"
    echo "  -tcp <端口列表>        设置TCP端口"
    echo "  -udp <端口列表>        设置UDP端口"
    echo "  -whitelist <IP列表>    设置IP白名单"
    echo "  -local <IP列表>        设置本地IP范围"
    echo "  -docker-gateway <IP>   设置Docker网关"
    echo "  -docker-subnet <子网>  设置Docker子网"
    echo "  -swap <大小>           设置交换分区大小"
    echo "  -cn                    使用国内源"
    echo "  -dry-run              测试模式，只生成配置"
    echo "  -no-reboot            安装后不重启"
}

# 创建cloud-init配置
create_cloud_init_config() {
    local config_dir

    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN"
        config_dir="/var/lib/cloud/seed/nocloud"
        mkdir -p "$config_dir"
    else
        config_dir="/root/cidata"
        mkdir -p "$config_dir"
    fi

    local RANDOM_HOSTNAME=$(generate_random_hostname)

    # 动态生成 SSH 公钥（如果未提供）
    if [ -z "$SSH_KEY" ]; then
        echo "未指定 SSH 公钥，正在生成临时密钥..."
        rm -f /tmp/temp_ssh_key /tmp/temp_ssh_key.pub
        ssh-keygen -t rsa -b 2048 -f /tmp/temp_ssh_key -N "" -q
        SSH_KEY=$(cat /tmp/temp_ssh_key.pub)
        echo "生成的临时 SSH 公钥: $SSH_KEY"
    fi

    # 创建 meta-data 文件
    touch "${config_dir}/meta-data"

    # 如果 CMD 不为空
    if [[ -n "$CMD" ]]; then
      EXTEND_CMD="- [ sh, -c, \"$CMD\" ]"
    else
      EXTEND_CMD="- [ sh, -c, \"date && echo 'done'\" ]"
    fi

    # 创建 user-data 文件
    cat > "${config_dir}/user-data" <<EOF
#cloud-config
hostname: $RANDOM_HOSTNAME
user: hello
manage_etc_hosts: true
disable_root: false
ssh_pwauth: true
password: '$PASSWORD'
ssh_authorized_keys:
  - $SSH_KEY
chpasswd: { expire: false }

write_files:
  - content: |
      [Swap]
      What=/swapfile

      [Install]
      WantedBy=swap.target
    path: /etc/systemd/system/swapfile.swap

runcmd:
  - [ hostnamectl, set-hostname, $RANDOM_HOSTNAME ]
  - [ systemctl, restart, systemd-hostnamed ]
  - [ sh, -c, "[ ! -e /swapfile ] && { fallocate -l $SWAP_SIZE /swapfile && chmod 0600 /swapfile && mkswap /swapfile; }; systemctl daemon-reload && systemctl enable --now swapfile.swap" ]
  - [ sh, -c, "which curl unzip >/dev/null 2>&1 || (apt update && apt install curl unzip -y) && curl '$SYSTEM_INIT_SCRIPT' | bash" ]
  - [ sh, -c, "curl '$SYSTEM_SYSCTL_SCRIPT' | bash" ]
  - [ sh, -c, "curl '$SYSTEM_DOCKER_SCRIPT' | bash -s '${DOCKER_IP}' '${DOCKER_SUBNET}'" ]
  - [ sh, -c, "curl '$SYSTEM_SSH_SCRIPT' | bash -s '${SSH_PORT}'" ]
  - [ sh, -c, "curl '$SYSTEM_UFW_SCRIPT' | bash -s -- -p '${SSH_PORT},${TCP_PORTS}' -u '${UDP_PORTS}' -w '${WHITELIST_IPS}' -l '${LOCAL_IPS}'" ]
  $EXTEND_CMD
EOF

    log_info "Cloud-init 配置文件已创建在 ${config_dir}"

    cat "${config_dir}/user-data"
}

# 执行 dry-run 测试
run_cloud_init_test() {
    log_info "开始执行 cloud-init 测试..."
    # 清理现有的 cloud-init 数据
	sudo cloud-init clean --logs
	# 执行所有阶段
	sudo cloud-init init --local && sudo cloud-init init && sudo cloud-init modules --mode=config && sudo cloud-init modules --mode=final
    log_info "cloud-init 测试完成"
}

# 获取所有网络信息
get_all_network_info() {
    echo "当前系统网络配置信息："
    echo "----------------------------------------"

    # 遍历所有有效网卡
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -Ev '^(lo|docker|veth|br-|tun|virbr)'); do
        IP_INFO=$(ip addr show $iface | grep 'inet ' | head -n1)
        IP_ADDR=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f1)
        CIDR=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f2)
        GATEWAY=$(ip route show dev $iface | grep default | awk '{print $3}')

        # 计算子网掩码
        if [[ -n "$CIDR" ]]; then
            NETMASK=$(printf "%d.%d.%d.%d\n" \
                $(( (0xFFFFFFFF << (32 - CIDR)) >> 24 & 0xFF )) \
                $(( (0xFFFFFFFF << (32 - CIDR)) >> 16 & 0xFF )) \
                $(( (0xFFFFFFFF << (32 - CIDR)) >> 8 & 0xFF )) \
                $(( (0xFFFFFFFF << (32 - CIDR)) & 0xFF )))
        else
            NETMASK="未分配"
        fi

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
    echo
    echo "# 重启网络服务命令："
    echo "systemctl restart networking"
    echo
    echo
}

# 主函数
main() {
    log_info "开始执行..."

    # 解析命令行参数
    parse_arguments "$@"


    echo ""
    echo ""

    # 创建配置文件
    create_cloud_init_config

    echo ""
    echo ""

    if [ "$DRY_RUN" = true ]; then
        log_info "运行在测试模式"
        run_cloud_init_test
        exit 0
    fi
    echo ""
    echo ""

    # 正常安装流程
    log_info "下载 debi.sh..."
    if ! curl -fLO "${DEBI_SCRIPT_URL}"; then
        log_error "下载 debi.sh 失败"
        exit 1
    fi
    chmod a+rx debi.sh

    # 获取网络配置
    get_network_info

    # 构建安装命令
    DEBI_CMD="./debi.sh --grub-timeout 1 --cdn --network-console --ethx --bbr"
    DNS="1.1.1.1 8.8.8.8 114.114.114.114 223.5.5.5"
    $CN_MODE && DNS="114.114.114.114 223.5.5.5 1.1.1.1 8.8.8.8"
    DEBI_CMD+=" --dns '$DNS' --cidata /root/cidata --user root"
    DEBI_CMD+=" --password '${PASSWORD}'"

    [ -n "$IP" ] && DEBI_CMD+=" --ip '${IP}'"
    [ -n "$NETMASK" ] && DEBI_CMD+=" --netmask '${NETMASK}'"
    [ -n "$GATEWAY" ] && DEBI_CMD+=" --gateway '${GATEWAY}'"
    $CN_MODE && DEBI_CMD+=" --ustc"

    echo ""
    echo ""
    log_info "安装命令：$DEBI_CMD"
    echo ""
    echo ""

    read -p "是否使用当前配置，并执行安装命令？(y/n) " USE_CURRENT
    if [[ $USE_CURRENT =~ ^[Yy]$ ]]; then
        echo "将使用当前网络配置继续安装"
    else
        echo "请使用以下参数指定网络配置："
        echo "  -ip <ip地址>"
        echo "  -netmask <子网掩码>"
        echo "  -gateway <网关>"
        exit 1
    fi

    if ! eval "$DEBI_CMD"; then
        log_error "安装失败"
        exit 1
    fi

    get_all_network_info

    echo "SSH端口: $SSH_PORT"
    echo "用户：root 密码: $PASSWORD"
    echo "用户：hello 密码: $PASSWORD"
    echo "SSH 公钥: $SSH_KEY"

    # 重启逻辑
    echo "执行安装命令：$DEBI_CMD"
    if $REBOOT_AFTER_INSTALL; then
        echo "安装完成，系统将在 5 秒后重启..."
        date
        sleep 5
        reboot
    else
        echo "安装完成，请手动重启系统"
        date
    fi
}

# 执行主程序
main "$@"
