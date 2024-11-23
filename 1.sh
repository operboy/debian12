#!/bin/bash

# 用于主机(非容器)初始化的脚本

# 设置环境变量以抑制交互式提示
export DEBIAN_FRONTEND=noninteractive

echo "======================="
echo "  开始基础工具安装"
echo "======================="
CN=${1:-0}
#if CN == 1
if [ "$CN" == "1" ]; then
  echo "开始安装国内软件源"
  cp /etc/apt/sources.list /etc/apt/sources.list.bak
  cat >/etc/apt/sources.list<<EOF
# 中科大镜像站
deb http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware
EOF
  cat /etc/apt/sources.list
fi

# 更新系统并安装基础工具，使用选项来避免交互
apt-get update
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# 安装常用工具和软件，使用选项来避免交互
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  logrotate net-tools isc-dhcp-client iftop wget curl htop vim lsof unzip zip psmisc git ufw rsync cron \
  traceroute dnsutils sudo openssh-server iputils-ping build-essential \
  locales sysstat iotop nethogs mtr ncdu pciutils screen expect tree ethtool \
  apt-transport-https ca-certificates software-properties-common \
  python3-pip python3-venv zsh iproute2 aria2 telnet rinetd rclone

# 安装 cron
sudo systemctl start cron
sudo systemctl enable cron

# 设置 dns
cat <<EOF | sudo tee /etc/resolv.conf >/dev/null
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# 模拟 /etc/rc.local 开机脚本
cat <<EOF >/etc/rc.local
#!/bin/sh -e
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.

iptables -A FORWARD -j ACCEPT

exit 0
EOF

iptables -A FORWARD -j ACCEPT

chmod +x /etc/rc.local

#创建缺失的 rc.local 服务
cat <<EOF >/etc/systemd/system/rc-local.service
[Unit]
Description=/etc/rc.local
ConditionFileIsExecutable=/etc/rc.local
After=network.target

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
RemainAfterExit=yes
GuessMainPID=no

[Install]
WantedBy=multi-user.target
EOF

#启用并立即启动服务
systemctl enable --now rc-local

# 设置时区为香港
rm -rf /etc/localtime && ln -s /usr/share/zoneinfo/Asia/Hong_Kong /etc/localtime

# 设置 locale
echo 'LC_TIME="en_GB.UTF-8"' | sudo tee /etc/default/locale
echo 'LANG="en_US.UTF-8"' | sudo tee -a /etc/default/locale

# 生成 locale
sudo locale-gen en_US.UTF-8 en_GB.UTF-8

# 设置系统 locale
sudo localedef -i en_US -f UTF-8 en_US.UTF-8
sudo localedef -i en_GB -f UTF-8 en_GB.UTF-8

# 检查并添加环境变量到 .profile
{
    if ! grep -q 'export LC_TIME="en_GB.UTF-8"' ~/.profile; then
        echo 'export LC_TIME="en_GB.UTF-8"' >> ~/.profile
    fi

    if ! grep -q 'export LANG="en_US.UTF-8"' ~/.profile; then
        echo 'export LANG="en_US.UTF-8"' >> ~/.profile
    fi

    if ! grep -q 'export LC_ALL="en_US.UTF-8"' ~/.profile; then
        echo 'export LC_ALL="en_US.UTF-8"' >> ~/.profile
    fi
}

# 使 .profile 中的改动立即生效
source ~/.profile

# 输出当前 locale 设置
locale

# 创建Python虚拟环境并安装包
python3 -m venv /opt/py3
/opt/py3/bin/pip install --no-cache-dir requests speedtest-cli
ln -s /opt/py3/bin/speedtest-cli /usr/bin/speedtest-cli

# 创建py3命令快捷方式
echo '#!/bin/bash\n/opt/py3/bin/python "$@"' >/usr/bin/py3 && chmod +x /usr/bin/py3

cat > /usr/bin/cleanlog <<'EOF'
#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 root 权限运行此脚本"
    exit 1
fi

echo "开始系统清理..."

# 清理所有用户的 Bash 和 Zsh 历史记录
echo "清理所有用户的 Shell 历史记录..."
for user_home in /home/*; do
    user=$(basename "$user_home")
    if [ -f "$user_home/.bash_history" ]; then
        truncate -s 0 "$user_home/.bash_history"
    fi
    if [ -f "$user_home/.zsh_history" ]; then
        truncate -s 0 "$user_home/.zsh_history"
    fi
done
# 不要忘记 root 用户的历史记录
truncate -s 0 /root/.bash_history
truncate -s 0 /root/.zsh_history
history -c
echo "Shell 历史记录已清理。"

# 清理用户登录记录
echo "清理用户登录记录..."
truncate -s 0 /var/log/wtmp
truncate -s 0 /var/log/btmp
truncate -s 0 /var/log/lastlog
echo "用户登录记录已清理。"

# 清理系统日志
echo "清理系统日志..."
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.old" -delete
find /var/log -type f -name "*.1" -delete
journalctl --vacuum-time=1d  # 只保留最近一天的日志
echo "系统日志已清理。"

# 清理临时文件和缓存
echo "清理临时文件和缓存..."
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -rf /var/cache/apt/archives/*.deb
rm -rf /root/.cache/*
find /home -type f -name '.thumbnails' -exec rm -rf {} +
find /home -type f -name '.cache' -exec rm -rf {} +
echo "临时文件和缓存已清理。"

# 清理软件包
echo "清理软件包..."
apt-get update
apt-get autoremove -y
apt-get autoclean
apt-get clean
echo "软件包已清理。"

# 清理旧的内核
echo "清理旧内核..."
dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | xargs apt-get -y purge 2>/dev/null || true
echo "旧内核已清理。"

# 清理 systemd 日志
echo "清理 systemd 日志..."
journalctl --vacuum-size=100M  # 限制日志大小为 100MB
echo "systemd 日志已清理。"

# 清理 snap 缓存（如果安装了 snap）
if command -v snap >/dev/null 2>&1; then
    echo "清理 snap 缓存..."
    set +e  # 防止错误中断脚本
    snap list --all | awk '/disabled/{print $1, $3}' |
        while read snapname revision; do
            snap remove "$snapname" --revision="$revision"
        done
    set -e
    echo "snap 缓存已清理。"
fi

# 清理 Docker 缓存（如果安装了 Docker）
if command -v docker >/dev/null 2>&1; then
    echo "清理 Docker 缓存..."
    docker system prune -af --volumes
    echo "Docker 缓存已清理。"
fi

# 清理 Flatpak 缓存（如果安装了 Flatpak）
if command -v flatpak >/dev/null 2>&1; then
    echo "清理 Flatpak 缓存..."
    flatpak uninstall --unused -y
    echo "Flatpak 缓存已清理。"
fi

# 清理 ~/.local/share/Trash 目录
echo "清理用户回收站..."
rm -rf /home/*/.local/share/Trash/*
rm -rf /root/.local/share/Trash/*
echo "用户回收站已清理。"

# 清理 systemd 失败的单元
echo "重置失败的 systemd 单元..."
systemctl reset-failed
echo "systemd 单元已重置。"

# 同步磁盘缓存
echo "同步磁盘缓存..."
sync

echo "所有清理操作已完成！"
echo "建议重启系统以应用所有更改。"

# 显示清理后的磁盘使用情况
df -h /
EOF
chmod +x /usr/bin/cleanlog && /usr/bin/cleanlog

cat > /usr/bin/netcheck <<'EOF'
#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 打印带颜色的标题
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
    echo "----------------------------------------"
}

# 执行命令并打印结果
execute_and_print() {
    local cmd="$1"
    echo -e "${GREEN}执行命令: ${cmd}${NC}"
    echo "----------------------------------------"
    if ! eval "$cmd" 2>&1; then
        echo -e "${RED}命令执行失败${NC}"
    fi
    echo "----------------------------------------"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${RED}警告: $1 命令未找到${NC}"
        return 1
    fi
    return 0
}

# 检查 iptables 规则
check_iptables() {
    local tables=("mangle" "filter" "nat")
    local chains=("OUTPUT" "PREROUTING" "POSTROUTING" "FORWARD" "INPUT")

    for table in "${tables[@]}"; do
        print_header "iptables ${table}表规则"
        for chain in "${chains[@]}"; do
            # 对于 filter 表，不需要指定 -t filter
            if [ "$table" = "filter" ]; then
                execute_and_print "iptables -L ${chain} -v -n --line-numbers"
            else
                execute_and_print "iptables -t ${table} -L ${chain} -v -n --line-numbers"
            fi
        done
    done
}

# 主函数
main() {
    print_header "防火墙规则检查 (iptables)"
    if check_command iptables; then
        check_iptables
    fi

    print_header "UFW 状态检查"
    if check_command ufw; then
        execute_and_print "ufw status verbose"
    fi

    print_header "路由表检查"
    if check_command ip; then
        execute_and_print "ip route show table main"
        # 检查 vpnbypass 表是否存在
        if ip route show table vpnbypass >/dev/null 2>&1; then
            execute_and_print "ip route show table vpnbypass"
        else
            echo -e "${RED}注意: vpnbypass 路由表不存在${NC}"
        fi
    fi

    print_header "网络连通性检查"
    if check_command traceroute; then
        execute_and_print "traceroute -I -q 1 -w 1 -n www.google.com"
    fi

    if check_command curl; then
        execute_and_print "curl -v --max-time 3 ipinfo.io"
    fi

    print_header "网络监听端口"
    if check_command netstat; then
        execute_and_print "netstat -ntlpu"
    fi

    echo -e "\n${GREEN}检查完成！${NC}"
}

# 捕获 Ctrl+C
trap 'echo -e "\n${RED}脚本被用户中断${NC}"; exit 1' INT

# 运行主函数
main
EOF
chmod +x /usr/bin/netcheck && /usr/bin/netcheck

cat > /usr/bin/flushroute <<'EOF'
#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 root 权限运行此脚本"
    exit 1
fi

# 检查 iptables 是否已安装
if ! command -v iptables &> /dev/null; then
    echo "错误：iptables 未安装，正在尝试安装..."
    apt update && apt install -y iptables
    if [ $? -ne 0 ]; then
        echo "安装 iptables 失败，请手动检查系统"
        exit 1
    fi
fi

# 保存当前规则（以防万一需要恢复）
echo "备份当前 iptables 规则..."
iptables-save > /root/iptables_backup_$(date +%Y%m%d_%H%M%S).rules

# 使用 set -e 在发生错误时立即退出
set -e

echo "开始清理 iptables 规则..."

# 1. 清空所有表的所有规则
iptables -F  # 清空 filter 表
iptables -t nat -F  # 清空 nat 表
iptables -t mangle -F  # 清空 mangle 表
iptables -t raw -F  # 清空 raw 表
echo "已清空所有表的规则"

# 2. 删除所有自定义链
iptables -X  # 清空 filter 表的自定义链
iptables -t nat -X  # 清空 nat 表的自定义链
iptables -t mangle -X  # 清空 mangle 表的自定义链
iptables -t raw -X  # 清空 raw 表的自定义链
echo "已删除所有自定义链"

# 3. 重置所有计数器
iptables -Z  # 重置 filter 表计数器
iptables -t nat -Z  # 重置 nat 表计数器
iptables -t mangle -Z  # 重置 mangle 表计数器
iptables -t raw -Z  # 重置 raw 表计数器
echo "已重置所有计数器"

# 4. 设置默认策略为 ACCEPT
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
echo "已将默认策略设置为 ACCEPT"

# 5. 删除所有非默认路由
echo "正在清理非默认路由..."
ip route | grep -v "default" | while read -r route; do
    ip route del $route 2>/dev/null || true
done
echo "已删除所有非默认路由"

# 6. 显示当前状态
echo -e "\n当前 iptables 规则："
iptables -L -n -v

echo -e "\n当前路由表："
ip route show

echo -e "\n清理完成！系统已恢复到默认状态。"
echo "备份文件已保存在 /root 目录下"
echo "如需恢复，请使用：iptables-restore < 备份文件名"

# 重置 set -e
set +e
EOF

# 设置脚本可执行权限
sudo chmod +x /usr/bin/flushroute

# 检查并安装 gost
if ! command -v gost >/dev/null 2>&1; then
    echo "安装 gost..."
    cd /tmp && wget -c https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
    gunzip gost-linux-amd64-2.11.5.gz && chmod +x gost-linux-amd64-2.11.5 && mv gost-linux-amd64-2.11.5 /usr/bin/gost
    gost -V
else
    echo "gost 已安装，版本："
    gost -V
fi

# 检查并安装 tcping
if ! command -v tcping >/dev/null 2>&1; then
    echo "安装 tcping..."
    wget https://github.com/pouriyajamshidi/tcping/releases/latest/download/tcping_amd64.deb -O /tmp/tcping.deb
    sudo apt install -y /tmp/tcping.deb
    rm -f /tmp/tcping.deb
else
    echo "tcping 已安装"
fi

# 检查并安装 oh-my-zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "安装 oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    chsh -s $(which zsh) root
else
    echo "oh-my-zsh 已安装"
fi


KEY_BINDINGS=$(cat <<'EOF'
bindkey "\e[1~" beginning-of-line
bindkey "\e[4~" end-of-line
bindkey "\e[5~" beginning-of-history
bindkey "\e[6~" end-of-history
bindkey "\e[8~" end-of-line
bindkey "\e[7~" beginning-of-line
bindkey "\eOH" beginning-of-line
bindkey "\eOF" end-of-line
bindkey "\e[H" beginning-of-line
bindkey "\e[F" end-of-line
bindkey '^i' expand-or-complete-prefix
bindkey -s "^[Op" "0"
bindkey -s "^[On" "."
bindkey -s "^[OM" "^M"
bindkey -s "^[Oq" "1"
bindkey -s "^[Or" "2"
bindkey -s "^[Os" "3"
bindkey -s "^[Ot" "4"
bindkey -s "^[Ou" "5"
bindkey -s "^[Ov" "6"
bindkey -s "^[Ow" "7"
bindkey -s "^[Ox" "8"
bindkey -s "^[Oy" "9"
bindkey -s "^[Ol" "+"
bindkey -s "^[Om" "-"
bindkey -s "^[Oj" "*"
bindkey -s "^[Oo" "/"
EOF
)

# 将键绑定添加到 .zshrc 中
if ! grep -q 'bindkey "\\e\[1~" beginning-of-line' ~/.zshrc; then
  echo "$KEY_BINDINGS" >> ~/.zshrc
  echo "键绑定已添加到 ~/.zshrc"
else
  echo "键绑定已存在于 ~/.zshrc"
fi

# 修改PATH
if ! grep -q 'export PATH=\$PATH:/usr/sbin:/sbin' ~/.zshrc; then
    echo 'export PATH=$PATH:/usr/sbin:/sbin' >> ~/.zshrc
fi

# 设置Vim在debian 12编辑模式下正常使用鼠标、快捷键复制等功能
sed -i "s/set mouse=a/set mouse-=a/g" /usr/share/vim/vim*/defaults.vim
cat /usr/share/vim/vim*/defaults.vim | grep mouse-=a

# 快捷命令
# Docker 执行命令（以交互模式运行 /bin/bash）
sed -i '/dbash()/d' ~/.zshrc
echo 'dbash() { docker exec -it "$1" /bin/bash; }' >> ~/.zshrc
echo "Function 'dbash' added or replaced in ~/.zshrc"

# 删除并添加 Docker 执行命令（以交互模式运行 /bin/sh）
sed -i '/dsh()/d' ~/.zshrc
echo 'dsh() { docker exec -it "$1" /bin/sh; }' >> ~/.zshrc
echo "Function 'dsh' added or replaced in ~/.zshrc"

# 删除并添加 Docker 实时日志查看
sed -i '/dlogs()/d' ~/.zshrc
echo 'dlogs() { docker logs -f "$1"; }' >> ~/.zshrc
echo "Function 'dlogs' added or replaced in ~/.zshrc"

# 删除并添加 Docker 重启容器
sed -i '/drestart()/d' ~/.zshrc
echo 'drestart() { docker stop "$1" -t 1 && docker start "$1"; }' >> ~/.zshrc
echo "Function 'drestart' added or replaced in ~/.zshrc"

# 删除并添加 Docker 停止并移除容器
sed -i '/drm()/d' ~/.zshrc
echo 'drm() { docker stop "$1" -t 1 && docker rm "$1"; }' >> ~/.zshrc
echo "Function 'drm' added or replaced in ~/.zshrc"

# 删除并添加 Docker 获取容器名称和 IP 地址
sed -i '/dip()/d' ~/.zshrc
echo 'dip() { docker ps -q | xargs -n 1 docker inspect --format "{{.Name}} - {{range \$k,\$v := .NetworkSettings.Networks}}{{printf \"%s:%s \" \$k \$v.IPAddress}}{{end}}- DNS: {{range .HostConfig.Dns}}{{.}} {{end}}" | sed "s|/||g"; }' >> ~/.zshrc
echo "Function 'dip' added or replaced in ~/.zshrc"

source ~/.zshrc

# 创建并写入配置
cat > ~/.vimrc << 'EOF'
"==========================================
" 基础设置
"==========================================
set nocompatible                " 关闭 vi 兼容模式
set number                      " 显示行号
syntax on                       " 语法高亮
set mouse=a                     " 启用鼠标
set encoding=utf-8              " 编码设置
set fileencodings=utf-8,ucs-bom,gb18030,gbk,gb2312,cp936
set termencoding=utf-8

"==========================================
" 界面显示
"==========================================
set ruler                       " 显示光标当前位置
set cursorline                  " 高亮显示当前行
set showmatch                   " 高亮显示匹配的括号
set hlsearch                    " 高亮显示搜索结果
set incsearch                   " 实时搜索
set ignorecase                  " 搜索时忽略大小写
set smartcase                   " 搜索时如果包含大写则对大小写敏感
set laststatus=2               " 永远显示状态栏
set showcmd                     " 显示输入的命令
set scrolloff=5                " 距离顶部和底部5行
set sidescrolloff=15           " 距离左右15列

"==========================================
" 编辑和缩进
"==========================================
set autoindent                  " 自动缩进
set smartindent                 " 智能缩进
set tabstop=4                   " Tab键的宽度
set softtabstop=4              " 统一缩进为4
set shiftwidth=4               " 自动缩进长度
set expandtab                   " 用空格代替制表符
set smarttab                    " 在行和段开始处使用制表符

"==========================================
" 文件类型
"==========================================
filetype on                     " 开启文件类型检测
filetype indent on              " 针对不同的文件类型采用不同的缩进格式
filetype plugin on              " 针对不同的文件类型加载对应的插件
filetype plugin indent on       " 启用自动补全

"==========================================
" 实用功能
"==========================================
set paste                       " 粘贴模式
set backspace=indent,eol,start  " 退格键可用
set nowrap                      " 禁止折行
set history=1000               " 历史记录数
set autoread                    " 文件在Vim之外修改过，自动重新读入
set wildmenu                    " 命令模式下的补全菜单
set nobackup                    " 不创建备份文件
set noswapfile                 " 不创建交换文件

"==========================================
" 编码和格式
"==========================================
set fileformat=unix            " 文件格式
set fileformats=unix,dos,mac   " 文件格式检测

"==========================================
" 颜色主题
"==========================================
set background=dark            " 深色背景
set t_Co=256                   " 启用256色

"==========================================
" 自定义快捷键
"==========================================
" 空格作为leader键
let mapleader=" "
" 快速保存
nmap <leader>w :w<CR>
" 快速退出
nmap <leader>q :q<CR>
" 取消搜索高亮
nmap <leader>h :nohl<CR>

"==========================================
" 状态栏设置
"==========================================
set statusline=%F%m%r%h%w\ [FORMAT=%{&ff}]\ [TYPE=%Y]\ [POS=%l,%v][%p%%]\ %{strftime(\"%d/%m/%y\ -\ %H:%M\")}

"==========================================
" 其他设置
"==========================================
set updatetime=300             " 更新时间
set timeoutlen=500            " 键盘快捷键连击时间
EOF

# 配置日志轮转
cat > /etc/logrotate.conf << 'EOF'
rotate 7
daily
compress
notifempty
delaycompress
EOF

# 对 SSD 使用 NOOP 或 deadline
echo 'noop' > /sys/block/sda/queue/scheduler

echo "======================="
echo "  基础工具安装完成"
echo "======================="
