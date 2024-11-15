#!/bin/bash
# 创建快捷指令
add_alias() {
    config_file=$1
    alias_names=("a" "5")
    [ ! -f "$config_file" ] || touch "$config_file"
    for alias_name in "${alias_names[@]}"; do
        if ! grep -q "alias $alias_name=" "$config_file" 2>/dev/null; then  
        #   echo "Adding alias $alias_name to $config_file"
         #   echo -e "\e[1;3;31m快捷指令已创建 a或5\e[0m"
            echo "alias $alias_name='bash <(curl -fsSL https://github.com/yyfalbl/sing-box-reality-hysteria2/raw/main/reality_hy2_ws.sh)'" >> "$config_file"
 fi
    done
    . "$config_file"
}
config_files=("/root/.bashrc" "/root/.profile" "/root/.bash_profile")
for config_file in "${config_files[@]}"; do
    add_alias "$config_file"
done
# 重新加载 .bashrc
     source /root/.bashrc
# 文本文字从左到右依次延时逐个显示
print_with_delay() {
    local message="$1"
    local delay="$2"
    
    for (( i=0; i<${#message}; i++ )); do
        echo -ne "\e[1;3;32m${message:i:1}\e[0m"  # 打印每个字符，带有颜色和样式
        sleep "$delay"
    done
    echo  # 换行
}
#长方形=...框样式
show_notice() {
    local message="$1"
    local width=50  # 定义长方形的宽度
    local border_char="="  # 边框字符
    local yellow_color="\033[31m"  # 黄色
    local yellow_bold_italic="\033[33;1;3m"  # 黄色斜体加粗
    local reset_color="\033[0m"  # 重置颜色
    # 打印黄色边框
    printf "${yellow_color}%${width}s${reset_color}\n" | tr " " "$border_char"  # 打印顶部边框
    printf "${yellow_color}||%$((width - 4))s||${reset_color}\n"  # 打印空行
    # 处理中文字符长度
    local message_length=$(echo -n "$message" | wc -m)  # 使用 -m 计算字符数
    local total_padding=$((width - message_length - 4))  # 4 是两侧 "||" 占用的字符数
    local left_padding=$((total_padding / 2))
    local right_padding=$((total_padding - left_padding))
    # 确保填充宽度正确（包括中文字符）
    if (( total_padding < 0 )); then
        # 消息太长的情况下，直接输出消息
        printf "${yellow_color}||%s||${reset_color}\n" "$message"
    else
      # 手动调整右侧填充
        right_padding=$((right_padding - 6)) 
        # 打印消息行并居中，应用黄色斜体加粗样式
       printf "${yellow_color}||%${left_padding}s${yellow_bold_italic}%s%${right_padding}s${reset_color}${yellow_color}||\n" "" "$message" ""
    fi
    printf "${yellow_color}||%$((width - 4))s||${reset_color}\n"  # 打印空行
    printf "${yellow_color}%${width}s${reset_color}\n" | tr " " "$border_char"  # 打印底部边框
}
# 安装依赖
install_base(){
  # Check if jq is installed, and install it if not
  if ! command -v jq &> /dev/null; then
      echo -e "\033[1;3;33m正在安装所需依赖，请稍后...${RESET}"
      if [ -n "$(command -v apt)" ]; then
          apt update > /dev/null 2>&1
          apt install -y jq > /dev/null 2>&1
      elif [ -n "$(command -v yum)" ]; then
          yum install -y epel-release
          yum install -y jq
      elif [ -n "$(command -v dnf)" ]; then
          dnf install -y jq
      else
          echo "Cannot install jq. Please install jq manually and rerun the script."
          exit 1
      fi
  fi
}
# 重新配置隧道
regenarte_cloudflared_argo(){
  vmess_port=$(jq -r '.inbounds[] | select(.type == "vmess") | .listen_port' /root/sbox/sbconfig_server.json)
  
  # 提示用户选择使用固定 Argo 隧道或临时隧道
  read -p $'\e[1;3;33mY 使用固定 Argo 隧道或 N 使用临时隧道？(Y/N，Enter 默认 Y): \e[0m' use_fixed
  use_fixed=${use_fixed:-Y}

  if [[ "$use_fixed" =~ ^[Yy]$ || -z "$use_fixed" ]]; then
    # 终止现有的 cloudflared 进程
    pid=$(pgrep -f cloudflared-linux)
    if [ -n "$pid" ]; then
      pkill -f cloudflared-linux 2>/dev/null
    fi

    # 提示用户生成 Argo 固定隧道配置
    echo -e "\033[1;3;33m请访问以下网站生成 Argo 固定隧道所需的Json配置信息。${RESET}"
    echo ""
    echo -e "${red}      https://fscarmen.cloudflare.now.cc/ ${reset}"
    echo ""

    # 获取 Argo 域名
    while true; do
      read -p $'\e[1;3;33m请输入你的 Argo 域名: \e[0m' argo_domain
      if [[ -n "$argo_domain" ]] && [[ "$argo_domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
      else
        echo -e "\e[1;3;31m输入无效，请输入一个有效的域名（不能为空）。\e[0m"
      fi
    done

    # 获取 Argo 密钥
    while true; do
      read -s -p $'\e[1;3;33m请输入你的 Argo 密钥 (token 或 json): \e[0m' argo_auth
      if [[ -z "$argo_auth" ]]; then
        echo -e "\e[1;3;31m密钥不能为空，请重新输入！\e[0m"
        continue
      fi   
      if [[ "$argo_auth" =~ ^[A-Za-z0-9-_=]{120,250}$ ]]; then
        echo -e "\e[32;3;1m你的 Argo 密钥为 Token 格式: $argo_auth\e[0m"
        break
      elif [[ "$argo_auth" =~ ^\{.*\}$ ]]; then
        echo -e "\e[32;3;1m你的 Argo 密钥为 JSON 格式: $argo_auth\e[0m"
        break
      else
        echo -e "\e[1;3;31m输入无效，请重新输入有效的 Token 或 JSON 格式的密钥!\n\e[0m"
      fi
    done

    # 如果 Argo 密钥包含 TunnelSecret，处理 JSON 格式
    if [[ $argo_auth =~ TunnelSecret ]]; then
      # 创建 JSON 凭据文件
      echo "$argo_auth" > /root/sbox/tunnel.json

      # 生成 tunnel.yml 文件
      cat > /root/sbox/tunnel.yml << EOF
tunnel: $(echo "$argo_auth" | jq -r '.TunnelID')
credentials-file: /root/sbox/tunnel.json
protocol: http2

ingress:
  - hostname: $argo_domain
    service: http://localhost:$vmess_port
    originRequest:
      noTLSVerify: true
  - service: "http_status:404"
EOF

      # 启动固定隧道
      if [ -e "/root/sbox/tunnel.yml" ]; then
        /root/sbox/cloudflared-linux tunnel --config /root/sbox/tunnel.yml run > /root/sbox/argo_run.log 2>&1 &
      else
        if [[ -n "$argo_auth" ]]; then
          echo "正在使用令牌启动Argo隧道..."
          /root/sbox/cloudflared-linux tunnel --token "$argo_auth" run > /root/sbox/argo_run.log 2>&1 &
        else
          echo "你的令牌错误,请提供有效的令牌!"
        fi
      fi
      echo ""
      echo -e "\e[1;3;32mcloudflare 固定隧道功能已启动！\e[0m"
    fi
  else
    # 用户选择使用临时隧道
    pid=$(pgrep -f cloudflared-linux)
    if [ -n "$pid" ]; then
      pkill -f cloudflared-linux 2>/dev/null
    fi

    # 启动临时隧道
    /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol http2 > /root/sbox/argo.log 2>&1 &
    sleep 2
    echo -e "\e[1;3;33m等待 Cloudflare Argo 生成地址...\e[0m"
    sleep 5

    # 获取生成的 Argo 域名
    argo=$(cat /root/sbox/argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    echo "$argo" | base64 > /root/sbox/argo.txt.b64
  fi
}

# 下载cloudflared文件
download_cloudflared(){
  arch=$(uname -m)
  case ${arch} in
      x86_64)
          cf_arch="amd64"
          ;;
      aarch64)
          cf_arch="arm64"
          ;;
      armv7l)
          cf_arch="arm"
          ;;
  esac
  cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
  curl -sLo "/root/sbox/cloudflared-linux" "$cf_url"
  chmod +x /root/sbox/cloudflared-linux
  echo -e "\e[1;35m======================\e[0m"
}

# 下载singbox最新测试版内核和正式版
download_singbox() {
    echo -e "\e[1;3;33m正在下载sing-box内核...\e[0m"
    sleep 1
    arch=$(uname -m)
    echo -e "\e[1;3;32m本机系统架构: $arch（ amd64，64-bit 架构）\e[0m"

    # 系统架构名称
    case ${arch} in
        x86_64)
            arch="amd64"
            ;;
        aarch64)
            arch="arm64"
            ;;
        armv7l)
            arch="armv7"
            ;;
    esac

    # 获取最新正式版的版本号
    latest_release_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | \
        jq -r '.[] | select(.prerelease == false) | .tag_name' | sort -V | tail -n 1)
    latest_release_version=${latest_release_tag#v}  # Remove 'v' prefix from version number
    echo -e "\e[1;3;32m当前最新正式版本: $latest_release_version\e[0m"

    # 获取最新测试版的版本号
    latest_prerelease_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | \
        jq -r '.[] | select(.prerelease == true) | .tag_name' | sort -V | tail -n 1)
    latest_prerelease_version=${latest_prerelease_tag#v}  # Remove 'v' prefix from version number
    echo -e "\e[1;3;33m当前最新测试版本: $latest_prerelease_version\e[0m"

    # 定义下载路径
    release_package="sing-box-${latest_release_version}-linux-${arch}"
    prerelease_package="sing-box-${latest_prerelease_version}-linux-${arch}"

    release_path="/root/sbox/release"
    prerelease_path="/root/sbox/prerelease"

    mkdir -p "$release_path" "$prerelease_path"

    # 下载并处理正式版
    if [ -f "${release_path}/sing-box" ]; then
        echo -e "\e[1;3;32m正式版文件已经存在，跳过下载。\e[0m"
    else
        release_url="https://github.com/SagerNet/sing-box/releases/download/${latest_release_tag}/${release_package}.tar.gz"
        curl -sLo "/root/${release_package}.tar.gz" "$release_url"

        tar -xzf "/root/${release_package}.tar.gz" -C /root
        mv "/root/${release_package}/sing-box" "$release_path"
        rm -r "/root/${release_package}.tar.gz" "/root/${release_package}"
        chown root:root "${release_path}/sing-box"
        chmod +x "${release_path}/sing-box"
        echo -e "\e[1;3;32m正式版已成功安装到: ${release_path}/sing-box\e[0m"
    fi

    # 下载并处理测试版
    if [ -f "${prerelease_path}/sing-box" ]; then
        echo -e "\e[1;3;32m测试版文件已经存在，跳过下载。\e[0m"
    else
        prerelease_url="https://github.com/SagerNet/sing-box/releases/download/${latest_prerelease_tag}/${prerelease_package}.tar.gz"
        curl -sLo "/root/${prerelease_package}.tar.gz" "$prerelease_url"

        tar -xzf "/root/${prerelease_package}.tar.gz" -C /root
        mv "/root/${prerelease_package}/sing-box" "$prerelease_path"
        rm -r "/root/${prerelease_package}.tar.gz" "/root/${prerelease_package}"
        chown root:root "${prerelease_path}/sing-box"
        chmod +x "${prerelease_path}/sing-box"
        echo -e "\e[1;3;33m测试版已成功安装到: ${prerelease_path}/sing-box\e[0m"
    fi

    # 设置默认内核为正式版
    default_kernel="${release_path}/sing-box"
    current_link="/root/sbox/sing-box"
    if [ ! -L "$current_link" ]; then
        ln -sf "$default_kernel" "$current_link"
        echo -e "\e[1;3;32m默认内核已设置为正式版。\e[0m"
    else
        echo -e "\e[1;3;32m当前内核已是正式版，无需更改。\e[0m"
    fi
}

#singbox 内核切换
switch_kernel() {
# 检测当前使用的 sing-box 版本
current_version=$(/root/sbox/sing-box version | grep "sing-box version" | awk '{print $3}')
echo -e "\e[1;3;32m当前使用最新的 sing-box 版本: $current_version\e[0m"

    # 提供切换内核选项
    while true; do
        echo -e "\e[1;3;33m是否需要切换内核？\e[0m"
         echo -e "\e[1;3;36m1. \e[1;3;36m切换到 alpha 测试版\e[0m"
        echo -e "\e[1;3;32m2. \e[1;3;32m切换到正式版\e[0m"
        echo -e "\e[1;3;31m3. \e[1;3;31m不切换，退出\e[0m"
        echo -ne "\e[1;3;34m请输入选项 [1/2/3]:\e[0m"
        read -p "" choice
        case $choice in
            1)
                ln -sf /root/sbox/prerelease/sing-box /root/sbox/sing-box
                echo -e "\e[1;3;33m已切换到测试版内核。\e[0m"
                systemctl restart sing-box
                echo -e "\e[1;3;33m已重启sing-box服务，应用测试版内核。\e[0m"
                break
                ;;
            2)
                ln -sf /root/sbox/release/sing-box /root/sbox/sing-box
                echo -e "\e[1;3;32m已切换到正式版内核。\e[0m"
                systemctl restart sing-box
                echo -e "\e[1;3;32m已重启sing-box服务，应用正式版内核。\e[0m"
                break
                ;;
            3)
                echo -e "\e[1;3;36m未进行任何更改，退出。\e[0m"
                break
                ;;
            *)
                echo -e "\e[1;3;31m无效选项，请重新输入。\e[0m"
                ;;
        esac
    done
}

#生成协议链接
show_client_configuration() {
    # 检查配置文件是否存在
    if [[ ! -f /root/sbox/sbconfig_server.json ]]; then
        echo "配置文件不存在！"
        return 1
    fi
    echo ""
    # 获取所有安装的协议数量
    inbound_count=$(jq '.inbounds | length' /root/sbox/sbconfig_server.json)
    if [[ $inbound_count -eq 0 ]]; then
        echo "没有安装任何协议！"
        return 1
    fi
    # 获取服务器 IP 地址
    server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)
    # 生成 Reality 客户端链接
    if jq -e '.inbounds[] | select(.type == "vless")' /root/sbox/sbconfig_server.json > /dev/null; then
        # 获取 Reality 配置
        current_listen_port=$(jq -r '.inbounds[] | select(.type == "vless") | .listen_port' /root/sbox/sbconfig_server.json)
        current_server_name=$(jq -r '.inbounds[] | select(.type == "vless") | .tls.server_name' /root/sbox/sbconfig_server.json)
        uuid=$(jq -r '.inbounds[] | select(.type == "vless") | .users[0].uuid' /root/sbox/sbconfig_server.json)
        public_key=$(base64 --decode /root/sbox/public.key.b64)
        short_id=$(jq -r '.inbounds[] | select(.type == "vless") | .tls.reality.short_id[0]' /root/sbox/sbconfig_server.json)

        server_link="vless://$uuid@$server_ip:$current_listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$current_server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#SING-BOX-Reality"
        echo -e "\e[1;3;31mVless-tcp-Reality 客户端通用链接：\e[0m"
       echo -e "\e[1;3;33m$server_link\e[0m"
        echo ""
    fi
    # 生成 Hysteria2 客户端链接
    if jq -e '.inbounds[] | select(.type == "hysteria2")' /root/sbox/sbconfig_server.json > /dev/null; then
        hy_current_listen_port=$(jq -r '.inbounds[] | select(.type == "hysteria2") | .listen_port' /root/sbox/sbconfig_server.json)
        hy_current_server_name=$(openssl x509 -in /root/self-cert/cert.pem -noout -subject -nameopt RFC2253 | awk -F'=' '{print $NF}')
        hy_password=$(jq -r '.inbounds[] | select(.type == "hysteria2") | .users[0].password' /root/sbox/sbconfig_server.json)

        hy2_server_link="hysteria2://$hy_password@$server_ip:$hy_current_listen_port?insecure=1&sni=$hy_current_server_name"
         echo -e "\e[1;3;31mHysteria2 客户端通用链接：\e[0m"
         echo -e "\e[1;3;33m$hy2_server_link\e[0m"
         echo ""
    fi
   # 判断是否存在固定隧道配置 生成 VMess 客户端链接
      # 检查是否存在固定隧道
if [[ -f "/root/sbox/tunnel.json" || -f "/root/sbox/tunnel.yml" ]]; then
    # 使用固定隧道生成链接
        echo -e "\e[1;3;31m使用固定隧道生成的Vmess客户端通用链接,替换$argo_domain为cloudflare优选ip或域名,可获得极致速度体验！\e[0m"
      echo ""
      echo -e "\e[1;3;32m以下端口 443 可改为 2053 2083 2087 2096 8443\e[0m"
        # 生成固定隧道链接
        vmess_link_tls='vmess://'$(echo '{"add":"'$argo_domain'","aid":"0","host":"'$argo_domain'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"vmess-tls","tls":"tls","type":"none","allowInsecure":true,"v":"2"}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_tls\e[0m"
 echo ""
 echo -e "\e[1;3;32m以下端口 80 可改为 8080 8880 2052 2082 2086 2095\e[0m"
        vmess_link_no_tls='vmess://'$(echo '{"add":"'$argo_domain'","aid":"0","host":"'$argo_domain'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"vmess-no-tls","tls":"","type":"none","v":"2"}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_no_tls\e[0m"
        echo ""
else
    # 不存在固定隧道，生成临时隧道链接
   if jq -e '.inbounds[] | select(.type == "vmess")' /root/sbox/sbconfig_server.json > /dev/null; then
        vmess_uuid=$(jq -r '.inbounds[] | select(.type == "vmess") | .users[0].uuid' /root/sbox/sbconfig_server.json)
        ws_path=$(jq -r '.inbounds[] | select(.type == "vmess") | .transport.path' /root/sbox/sbconfig_server.json)
        argo=$(base64 --decode /root/sbox/argo.txt.b64)
        echo -e "\e[1;3;31m使用临时隧道生成的Vmess客户端通用链接，替换speed.cloudflare.com为自己的优选ip可获得极致体验\e[0m"
       echo -e "\e[1;3;32m以下端口 443 可改为 2053 2083 2087 2096 8443\e[0m"
        echo ""
        vmess_link_tls='vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"sing-box-vmess-tls","tls":"tls","type":"none","allowInsecure":true,"v":"2"}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_tls\e[0m"
        echo ""
        echo -e "\e[1;3;32m以下端口 80 可改为 8080 8880 2052 2082 2086 2095\e[0m" 
        echo ""
        vmess_link_no_tls='vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"sing-box-vmess","tls":"","type":"none","v":"2"}' | base64 -w 0)
          echo -e "\e[1;3;33m$vmess_link_no_tls\e[0m"
        echo ""
    fi
fi    
   # 生成 TUIC 客户端链接
if jq -e '.inbounds[] | select(.type == "tuic")' /root/sbox/sbconfig_server.json > /dev/null; then
    tuic_uuid=$(jq -r '.inbounds[] | select(.type == "tuic") | .users[0].uuid' /root/sbox/sbconfig_server.json)
    tuic_password=$(jq -r '.inbounds[] | select(.type == "tuic") | .users[0].password' /root/sbox/sbconfig_server.json)
    tuic_listen_port=$(jq -r '.inbounds[] | select(.type == "tuic") | .listen_port' /root/sbox/sbconfig_server.json)
    
    # 这里可以设置 SNI 和其他参数
    sni="www.bing.com"
    congestion_control="bbr"
    udp_relay_mode="native"
    alpn="h3"
    
    tuic_link="tuic://${tuic_uuid}:${tuic_password}@${server_ip}:${tuic_listen_port}?sni=${sni}&congestion_control=${congestion_control}&udp_relay_mode=${udp_relay_mode}&alpn=${alpn}&allow_insecure=1#${isp}"
    
    echo -e "\e[1;3;31mTUIC 客户端通用链接：\e[0m"
    echo -e "\e[1;3;33m$tuic_link\e[0m"
    echo ""
fi

}
#重启cloudflare隧道
restart_tunnel() {
    echo -e "\e[1;3;32m正在检测隧道类型并重启中...\e[0m"
    vmess_port=$(jq -r '.inbounds[] | select(.type == "vmess") | .listen_port' /root/sbox/sbconfig_server.json)
    echo ""

    # 停止现有的 cloudflared 进程和服务
    echo -e "\e[1;3;33m正在重启 cloudflared 服务...\e[0m"
    systemctl stop cloudflared
    pkill -f cloudflared-linux
    sleep 2  # 等待进程完全终止

    # 判断是固定隧道还是临时隧道
    if [ -f "/root/sbox/tunnel.json" ] || [ -f "/root/sbox/tunnel.yml" ]; then
        echo -e "\e[1;3;32m启动固定隧道...\e[0m"
        /root/sbox/cloudflared-linux tunnel --config /root/sbox/tunnel.yml run > /root/sbox/argo_run.log 2>&1 &
    else
        echo -e "\e[1;3;32m正在重新启动临时隧道...\e[0m"
        echo ""
        pid=$(pgrep -f cloudflared-linux)
        if [ -n "$pid" ]; then
            echo -e "\e[1;3;33m终止现有进程...\e[0m"
            pkill -f cloudflared-linux 2>/dev/null
            sleep 2  # 等待进程完全终止
        fi

        # 启动临时隧道
        /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol http2 > /root/sbox/argo.log 2>&1 &
        sleep 2
        echo -e "\e[1;3;33m等待 Cloudflare Argo 生成地址...\e[0m"
        sleep 5

        # 连接到域名
        argo=$(grep trycloudflare.com /root/sbox/argo.log | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
        echo "$argo" | base64 > /root/sbox/argo.txt.b64
        show_client_configuration
    fi
  
    # 检查是否存在 cloudflared.service 文件
    if [ ! -f "/etc/systemd/system/cloudflared.service" ]; then
        echo -e "\e[1;3;33m添加 cloudflared 服务开机启动配置...\e[0m"
        cat > /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
ExecStart=/bin/bash -c 'if [ -f "/root/sbox/tunnel.yml" ] || [ -f "/root/sbox/tunnel.json" ]; then /root/sbox/cloudflared-linux tunnel --config /root/sbox/tunnel.yml run; else /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol http2; fi'
Restart=always
User=root
StandardOutput=append:/root/sbox/argo_run.log
StandardError=append:/root/sbox/argo_run.log

[Install]
WantedBy=multi-user.target
EOF
    else
        echo -e "\e[1;3;32mcloudflared 服务已存在，无需重新创建。\e[0m"
    fi

    # 重新加载并启动 cloudflared 服务
    systemctl daemon-reload
    systemctl start cloudflared
    systemctl enable cloudflared
    echo -e "\e[1;3;32mCloudflare Tunnel 已重新启动！\e[0m"
}

#卸载sing-box程序
uninstall_singbox() {
 echo -e "\e[1;3;31m正在卸载sing-box服务...\e[0m"
    echo ""
    # 询问用户是否确认卸载
    while true; do
         read -p $'\e[1;3;33m您确定要卸载sing-box服务吗？(y/n) [默认y]: \e[0m' confirm
        confirm=${confirm,,}  # 将输入转换为小写
        
        # 如果输入为空，视为 'y'
        if [[ -z "$confirm" ]]; then
            confirm="y"
        fi
        case "$confirm" in
            y) 
                break  # 继续卸载
                ;;
            n) 
                echo "取消卸载。"
                return
                ;;
            *) 
                echo "无效输入，请输入 y 或 n。"
                ;;
        esac
    done
    # 停止 Cloudflare 隧道服务
    if systemctl is-active --quiet cloudflared; then
        echo -e "\e[1;3;33m正在停止 Cloudflare 隧道服务...\e[0m"
        systemctl stop cloudflared 2>/dev/null
        systemctl disable cloudflared 2>/dev/null
    fi
    # 停止现有的 cloudflared 进程
    pid=$(pgrep -f cloudflared-linux)
    if [ -n "$pid" ]; then
        pkill -f cloudflared-linux 2>/dev/null
    fi
    sleep 2
    # 停止并禁用 sing-box 服务
    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    # 定义要删除的文件和目录
    files_to_remove=(
        "/etc/systemd/system/sing-box.service"
        "/etc/systemd/system/cloudflared.service"
        "/root/sbox/sbconfig_server.json"
        "/root/sbox/sing-box"
        "/root/sbox/cloudflared-linux"
        "/root/sbox/argo.txt.b64"
        "/root/sbox/public.key.b64"
        "/root/self-cert/private.key"
        "/root/self-cert/cert.pem"
    )
    directories_to_remove=(
        "/root/self-cert/"
        "/etc/systemd/system/cloudflared.service"
        "/root/sbox/"
    )
    # 删除文件并检查是否成功
    for file in "${files_to_remove[@]}"; do
        if [ -e "$file" ]; then
            rm "$file" > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo "Failed to remove $file."
            fi
        fi
    done
    # 删除目录并检查是否成功
    for dir in "${directories_to_remove[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir" > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo "Failed to remove directory $dir."
            fi
        fi
    done
   #  重新加载系统的单元文件配置
    systemctl daemon-reload
   echo -e "\e[1;3;32msing-box已成功卸载!\e[0m"
echo -e "\e[1;3;32m所有sing-box配置文件已完全移除\e[0m"
 echo ""
}
# 安装sing-box
install_singbox() { 
    install_base
  while true; do
    echo -e "\e[1;3;33m请选择要安装的协议（输入数字，多个选择用空格分隔）:\e[0m"
    echo -e "\e[1;3;33m1) vless-Reality\e[0m"
    echo -e "\e[1;3;33m2) VMess\e[0m"
    echo -e "\e[1;3;33m3) Hysteria2\e[0m"
    echo -e "\e[1;3;33m4) Tuic\e[0m"
    echo -ne "\e[1;3;33m请输入你的选择: \e[0m" && read choices
    echo ""  
    # 检查输入是否为空
    if [[ -z "$choices" ]]; then
        echo "输入不能为空，请重新输入。"
        continue
    fi

    # 将用户输入的选择转为数组
    read -a selected_protocols <<< "$choices"
    
    # 检查输入的选择是否有效
    valid=true
    for choice in "${selected_protocols[@]}"; do
        if [[ ! "$choice" =~ ^[1-4]$ ]]; then
            valid=false
            break
        fi
    done

    if [ "$valid" = false ]; then
        echo "选择的协议无效，请选择 1 到 4 之间的数字，且不能为空。"
    else
        echo -e "\e[1;3;32m正在根据所选协议正在进行配置...\e[0m"
        sleep 2
        break  # 有效选择后退出循环
    fi
done

    # 初始化配置变量
    listen_port=443
    vmess_port=15555
    hy_listen_port=8443
    tuic_listen_port=8080
config="{
  \"log\": {
    \"disabled\": false,
    \"level\": \"info\",
    \"timestamp\": true
  },
  \"inbounds\": [ ],
  \"outbounds\": [
    {
      \"type\": \"direct\",
      \"tag\": \"direct\"
    }
  ]
}"
    for choice in $choices; do
        case $choice in
            1)
                show_notice "★ ★ ★ 开始配置Vless协议 ★ ★ ★"
                sleep 2
                echo -e "\e[1;3;33m正在生成vless密匙对...\e[0m" 
                key_pair=$(/root/sbox/sing-box generate reality-keypair)
                if [ $? -ne 0 ]; then
                    echo -e "\e[1;3;31m生成 Reality 密钥对失败。\e[0m"
                    exit 1
                fi
                echo -e "\e[1;3;32m生成vless密匙对成功\e[0m"
                sleep 1
                echo -e "\e[1;3;33m正在提取提取私钥和公钥...\e[0m"
                private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
                public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
                echo "$public_key" | base64 > /root/sbox/public.key.b64
                echo -e "\e[1;3;32m提取提取私钥和公钥成功\e[0m"
                echo -e "\e[1;3;33m正在随机生成UUID和短UUID\e[0m"
                uuid=$(/root/sbox/sing-box generate uuid)
                short_id=$(/root/sbox/sing-box generate rand --hex 8)
                sleep 1
                echo -e "\e[1;3;32mUUID为: $uuid\e[0m"
                echo -e "\e[1;3;32m短UUID为: $short_id\e[0m"
                sleep 1
                read -p $'\e[1;3;33m请输入 Reality 端口 (默认端口: 443): \e[0m' listen_port_input
                listen_port=${listen_port_input:-443}
                echo -e "\e[1;3;32mvless端口: $listen_port\e[0m"
                sleep 1
                read -p $'\e[1;3;33m请输入想要使用的域名 (默认域名: itunes.apple.com): \e[0m' server_name_input
                server_name=${server_name_input:-itunes.apple.com}
                echo -e "\e[1;3;32m使用的域名：$server_name\e[0m"
                echo ""
                config=$(echo "$config" | jq --arg listen_port "$listen_port" \
                    --arg server_name "$server_name" \
                    --arg private_key "$private_key" \
                    --arg short_id "$short_id" \
                    --arg uuid "$uuid" \
                    '.inbounds += [{
                        "type": "vless",
                        "tag": "vless-in",
                        "listen": "::",
                        "listen_port": ($listen_port | tonumber),
                        "users": [{
                            "uuid": $uuid,
                            "flow": "xtls-rprx-vision"
                        }],
                        "tls": {
                            "enabled": true,
                            "server_name": $server_name,
                            "reality": {
                                "enabled": true,
                                "handshake": {
                                    "server": $server_name,
                                    "server_port": 443
                                },
                                "private_key": $private_key,
                                "short_id": [$short_id]
                            }
                        }
                    }]')
                ;;

            2)
           show_notice "★ ★ ★ 开始配置Vmess协议 ★ ★ ★"
           sleep 2 
           echo -e "\e[1;3;33m正在自动生成Vmess-UUID\e[0m"
           sleep 1
           vmess_uuid=$(/root/sbox/sing-box generate uuid)
           echo -e "\e[1;3;32mvmess UUID为: $vmess_uuid\e[0m"
           sleep 1
           read -p $'\e[1;3;33m请输入 vmess 端口(默认端口:15555): \e[0m' vmess_port
           vmess_port=${vmess_port:-15555}
           echo -e "\e[1;3;32mvmess端口: $vmess_port\e[0m"
           sleep 1
           read -p $'\e[1;3;33mws 路径 (默认随机生成): \e[0m' ws_path
           sleep 1
           ws_path=${ws_path:-$(/root/sbox/sing-box generate rand --hex 6)}
           echo -e "\e[1;3;32mws路径为: $ws_path\e[0m"
# 提示用户选择使用固定 Argo 隧道或临时隧道
read -p $'\e[1;3;33mY 使用固定 Argo 隧道或 N 使用临时隧道？(Y/N，Enter 默认 Y): \e[0m' use_fixed
use_fixed=${use_fixed:-Y}

if [[ "$use_fixed" =~ ^[Yy]$ || -z "$use_fixed" ]]; then
   pid=$(pgrep -f cloudflared-linux)
if [ -n "$pid" ]; then
    # 终止现有进程
    pkill -f cloudflared-linux 2>/dev/null
fi
 echo -e "\033[1;3;33m请访问以下网站生成 Argo 固定隧道所需的Json配置信息。${RESET}"
        echo ""
        echo -e "${red}      https://fscarmen.cloudflare.now.cc/ ${reset}"
        echo ""
    # 确保输入有效的 Argo 域名
while true; do
    read -p $'\e[1;3;33m请输入你的 Argo 域名: \e[0m' argo_domain
    sleep 2
    if [[ -n "$argo_domain" ]] && [[ "$argo_domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo -e "\e[32;3;1m你的 Argo 域名为: $argo_domain\e[0m"
        break
    else
        echo -e "\e[1;3;31m输入无效，请输入一个有效的域名(不能为空)!\e[0m"
    fi
done
# 确保输入有效的 Argo token 或 json
while true; do
    # 提示用户输入 Argo 密钥，黄色斜体加粗
    read -s -p $'\e[1;3;33m请输入你的 Argo 密钥 (token 或 json): \e[0m' argo_auth
    echo
    # 检查输入是否为空
    if [[ -z "$argo_auth" ]]; then
        echo -e "\e[1;3;31m密钥不能为空！\e[0m"
        continue
    fi
    
    # 检查是否为有效的 Token 格式
    if [[ "$argo_auth" =~ ^[A-Za-z0-9-_=]{120,250}$ ]]; then
        echo -e "\e[32;3;1m你的 Argo 密钥为 Token 格式: $argo_auth\e[0m"
        break
    # 检查是否为有效的 JSON 格式
    elif [[ "$argo_auth" =~ ^\{.*\}$ ]]; then
        echo -e "\e[32;3;1m你的 Argo 密钥为 JSON 格式: $argo_auth\e[0m"
        break
    else
        # 如果输入无效，显示错误提示信息
        echo -e "\e[1;3;31m输入无效，请输入有效的 Token 或 JSON 格式的密钥!\e[0m"
    fi
done

    # 处理 Argo 的配置
    if [[ $argo_auth =~ TunnelSecret ]]; then
        # 创建 JSON 凭据文件
        echo "$argo_auth" > /root/sbox/tunnel.json

        # 生成 tunnel.yml 文件
 cat > /root/sbox/tunnel.yml << EOF
tunnel: $(echo "$argo_auth" | jq -r '.TunnelID')
credentials-file: /root/sbox/tunnel.json
protocol: http2

ingress:
  - hostname: $argo_domain
    service: http://localhost:$vmess_port
    originRequest:
      noTLSVerify: true
  - service: "http_status:404"
EOF

      #  echo "生成的 tunnel.yml 文件内容:"
      #  cat /root/sbox/tunnel.yml
        # 启动固定隧道
       /root/sbox/cloudflared-linux tunnel --config /root/sbox/tunnel.yml run > /root/sbox/argo_run.log 2>&1 &
       echo "" 
        echo -e "\e[1;3;32mCloudflared 固定隧道功能已启动！\e[0m"
    echo ""
    fi
else
    # 用户选择使用临时隧道
pid=$(pgrep -f cloudflared-linux)
if [ -n "$pid" ]; then
    # 终止现有进程
    pkill -f cloudflared-linux 2>/dev/null
fi

    # 启动临时隧道
 /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol http2 > /root/sbox/argo.log 2>&1 &
sleep 2
echo -e "\e[1;3;33m等待 Cloudflare Argo 生成地址...\e[0m"
sleep 5
echo ""
#连接到域名
argo=$(cat /root/sbox/argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
echo "$argo" | base64 > /root/sbox/argo.txt.b64
fi
# 生成vmess配置文件
 config=$(echo "$config" | jq --arg vmess_port "$vmess_port" \
                    --arg vmess_uuid "$vmess_uuid" \
                    --arg ws_path "$ws_path" \
                    '.inbounds += [{
                        "type": "vmess",
                        "tag": "vmess-in",
                        "listen": "::",
                        "listen_port": ($vmess_port | tonumber),
                        "users": [{
                            "uuid": $vmess_uuid,
                            "alterId": 0
                        }],
                        "transport": {
                            "type": "ws",
                            "path": $ws_path
                        }
                    }]')
                ;;

            3)
                show_notice "★ ★ ★ 开始配置Hysteria2协议 ★ ★ ★"
                sleep 2
                echo -e "\e[1;3;33m正在生成Hysteria2随机密码\e[0m"
                sleep 1
                hy_password=$(/root/sbox/sing-box generate rand --hex 8)
                echo -e "\e[1;3;32m随机生成的hy2密码: $hy_password\e[0m"
                sleep 1
                read -p $'\e[1;3;33m请输入 Hysteria2 监听端口 (default: 8443): \e[0m' hy_listen_port_input
                sleep 1
                hy_listen_port=${hy_listen_port_input:-8443}
                echo -e "\e[1;3;32mHysteria2端口: $hy_listen_port\e[0m"
                sleep 1
                read -p $'\e[1;3;33m请输入自签证书域名 (默认域名: bing.com): \e[0m' hy_server_name_input
                sleep 1
                hy_server_name=${hy_server_name_input:-bing.com}            
                mkdir -p /root/self-cert/
                openssl ecparam -genkey -name prime256v1 -out /root/self-cert/private.key
                openssl req -new -x509 -days 36500 -key /root/self-cert/private.key -out /root/self-cert/cert.pem -subj "/CN=${hy_server_name}"
                echo -e "\e[1;3;32m自签证书已生成成功\e[0m"
                echo ""
                config=$(echo "$config" | jq --arg hy_listen_port "$hy_listen_port" \
                    --arg hy_password "$hy_password" \
                    '.inbounds += [{
                        "type": "hysteria2",
                        "tag": "hy2-in",
                        "listen": "::",
                        "listen_port": ($hy_listen_port | tonumber),
                        "users": [{
                            "password": $hy_password
                        }],
                        "tls": {
                            "enabled": true,
                            "alpn": ["h3"],
                            "certificate_path": "/root/self-cert/cert.pem",
                            "key_path": "/root/self-cert/private.key"
                        }
                    }]')
                ;; 
           4)
    show_notice "★ ★ ★ 开始配置Tuic协议 ★ ★ ★"
    sleep 2
    echo -e "\e[1;3;33m正在自动生成Tuic随机密码\e[0m"
    sleep 1
    tuic_password=$(/root/sbox/sing-box generate rand --hex 8)
    echo -e "\e[1;3;32mTuic随机密码: $tuic_password\e[0m"
    sleep 1
    echo -e "\e[1;3;33m正在自动生成Tuic-UUID\e[0m"
    sleep 1
    tuic_uuid=$(/root/sbox/sing-box generate uuid)  # 生成 uuid
    echo -e "\e[1;3;33m随机生成Tuic-UUID：$tuic_uuid\e[0m"
    sleep 1
    read -p $'\e[1;3;33m请输入 TUIC 监听端口 (默认端口: 8080): \e[0m' tuic_listen_port_input
    sleep 1
    tuic_listen_port=${tuic_listen_port_input:-8080}
    echo -e "\e[1;3;32mTuic端口：$tuic_listen_port\e[0m"
    sleep 1
    read -p $'\e[1;3;33m输入 TUIC 自签证书域名 (默认域名: bing.com): \e[0m' tuic_server_name_input
    sleep 1
    tuic_server_name=${tuic_server_name_input:-bing.com}
    mkdir -p /root/self-cert/
    openssl ecparam -genkey -name prime256v1 -out /root/self-cert/private.key
    openssl req -new -x509 -days 36500 -key /root/self-cert/private.key -out /root/self-cert/cert.pem -subj "/CN=${tuic_server_name}"
    echo -e "\e[1;3;32m自签证书已生成成功\e[0m"
    echo ""

    config=$(echo "$config" | jq --arg tuic_listen_port "$tuic_listen_port" \
        --arg tuic_password "$tuic_password" \
        --arg tuic_uuid "$tuic_uuid" \
        '.inbounds += [{
            "type": "tuic",
            "tag": "tuic-in",
            "listen": "::",
            "listen_port": ($tuic_listen_port | tonumber),
            "users": [{
                "uuid": $tuic_uuid,
                "password": $tuic_password
            }],
            "tls": {
                "enabled": true,
                "alpn": ["h3"],
                "certificate_path": "/root/self-cert/cert.pem",
                "key_path": "/root/self-cert/private.key"
            }
        }]')
    ;;

              *)
                echo "无效选择: $choice"
                ;;    
        esac
    done
    # 生成最终配置文件
    echo "$config" > /root/sbox/sbconfig_server.json
  #  echo "配置文件已生成：/root/sbox/sbconfig_server.json"
}
#创建sing-box和cloudflare服务文件并启动
setup_services() {
    # 获取 vmess 端口
    local vmess_port=$(jq -r '.inbounds[] | select(.type == "vmess") | .listen_port' /root/sbox/sbconfig_server.json)
    local CLOUDFLARED_PATH="/root/sbox/cloudflared-linux"
    local CONFIG_PATH="/root/sbox/tunnel.yml"
    local JSON_PATH="/root/sbox/tunnel.json"
    local LOG_PATH="/root/sbox/argo_run.log"
    # 创建 sing-box 服务文件
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/root/sbox/sing-box run -c /root/sbox/sbconfig_server.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    # 如果存在 vmess 类型的配置，则创建 Cloudflare 服务文件
    if [ -n "$vmess_port" ]; then
        cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
ExecStart=/bin/bash -c 'if [ -f "$CONFIG_PATH" ] || [ -f "$JSON_PATH" ]; then $CLOUDFLARED_PATH tunnel --config "$CONFIG_PATH" run; else $CLOUDFLARED_PATH tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol http2; fi'
Restart=always
User=root
StandardOutput=append:$LOG_PATH
StandardError=append:$LOG_PATH

[Install]
WantedBy=multi-user.target
EOF
    fi

    # 检查配置并启动服务
    if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
        echo -e "\e[1;3;33m配置检查成功，正在启动 sing-box 服务...\e[0m"
        # 重新加载系统服务管理器
        systemctl daemon-reload
        # 启动并设置服务开机自启  
        systemctl start sing-box
        systemctl enable sing-box > /dev/null 2>&1

        if systemctl is-active --quiet sing-box; then
            echo -e "\e[1;3;32msing-box 服务已成功启动！\e[0m"
        else
            echo -e "\e[1;3;31msing-box 服务启动失败！\e[0m"
        fi

        # 如果 Cloudflare 服务文件存在，启动 Cloudflare 服务
        if [ -n "$vmess_port" ]; then
            systemctl start cloudflared
            systemctl enable cloudflared > /dev/null 2>&1

            if systemctl is-active --quiet cloudflared; then
                echo -e "\e[1;3;32mCloudflare Tunnel 服务已成功启动！\e[0m"
            else
                echo -e "\e[1;3;31mCloudflare Tunnel 服务启动失败！\e[0m"
            fi
        fi

        show_client_configuration
    else
        echo -e "\e[1;3;33m配置错误，sing-box 服务未启动！\e[0m"
    fi
}
#重新安装sing-box和cloudflare
reinstall_sing_box() {
    show_notice "将重新安装中..."
    # 停止和禁用 sing-box 服务
    systemctl stop sing-box
    systemctl disable sing-box > /dev/null 2>&1

    # 删除服务文件和配置文件，先检查是否存在
    [ -f /etc/systemd/system/sing-box.service ] && rm /etc/systemd/system/sing-box.service
    [ -f /root/sbox/sbconfig_server.json ] && rm /root/sbox/sbconfig_server.json
    [ -f /root/sbox/sing-box ] && rm /root/sbox/sing-box
    [ -f /root/sbox/cloudflared-linux ] && rm /root/sbox/cloudflared-linux
    [ -f /root/sbox/argo.txt.b64 ] && rm /root/sbox/argo.txt.b64
    [ -f /root/sbox/public.key.b64 ] && rm /root/sbox/public.key.b64

    # 删除证书和 sbox 目录
    rm -rf /root/self-cert/
    rm -rf /root/sbox/
    # 重新安装的步骤
        mkdir -p "/root/sbox/"
        download_singbox
        download_cloudflared
        install_singbox
}

check_services_status() {
    echo -e "\e[1;3;33m正在检查 cloudflared 和 sing-box 服务的当前状态...\e[0m"
    sleep 2
    # 检查 sing-box 服务状态
    singbox_status=$(systemctl status sing-box 2>&1)
    if echo "$singbox_status" | grep -q "active (running)"; then
        echo -e "\e[1;3;32mSing-box 服务启动正常\e[0m"
    elif echo "$singbox_status" | grep -q "inactive (dead)"; then
        echo -e "\e[1;3;31mSing-box 服务未启动。\e[0m"
    else
        echo -e "\e[1;3;33mSing-box 服务状态未知，请检查服务状态。\e[0m"
    fi
    sleep 2
    # 检查 cloudflared 服务状态
    cloudflared_status=$(systemctl status cloudflared 2>&1)
    if echo "$cloudflared_status" | grep -q "active (running)"; then
        echo -e "\e[1;3;32mCloudflare 服务启动正常\e[0m"
    elif echo "$cloudflared_status" | grep -q "inactive (dead)"; then
        echo -e "\e[1;3;31mCloudflare 服务未启动\e[0m"
    else
        echo -e "\e[1;3;33mCloudflare 服务状态未知，请检查服务状态。\e[0m"
    fi
    echo "" 
}

# 检测隧道状况
check_tunnel_status() {
    check_services_status
    sleep 2
    
    if [ -f "/root/sbox/tunnel.json" ] || [ -f "/root/sbox/tunnel.yml" ]; then
        # 检查固定隧道状态
        echo -e "\e[1;3;33m正在检查固定隧道状态...\e[0m"
        sleep 2
        echo ""
        
        # 检查 cloudflared-linux 进程是否在运行
        if pgrep -f cloudflared-linux > /dev/null; then
            if [ -f "/root/sbox/argo_run.log" ]; then
                if grep -q "Starting tunnel" /root/sbox/argo_run.log && grep -q "Registered tunnel connection" /root/sbox/argo_run.log; then
                    echo -e "\e[1;3;32mCloudflare 固定隧道正常运行。\e[0m"
                    echo ""
                else
                    echo -e "\e[1;3;31mCloudflare 固定隧道未能成功启动。\e[0m"
                    restart_tunnel  # 如果需要，可以调用重启函数
                fi
            else
                echo -e "\e[1;3;31m找不到日志文件，无法检查固定隧道状态。\e[0m"
            fi
        else
            echo -e "\e[1;3;31mCloudflare 固定隧道服务已停止\e[0m"
            echo ""
        fi
    else
        # 检查临时隧道状态
        echo -e "\e[1;3;33m正在检查临时隧道状态...\e[0m"
        sleep 2
        echo ""

        # 检查 cloudflared-linux 进程是否在运行
        if pgrep -f cloudflared-linux > /dev/null; then
            if [ -f "/root/sbox/argo.log" ]; then
                if grep -q "Your quick Tunnel has been created!" /root/sbox/argo.log; then
                    echo -e "\e[1;3;32mCloudflare 临时隧道正常运行!\e[0m"
                    echo ""
                else
                    echo -e "\e[1;3;31mCloudflare 临时隧道未能成功启动。\e[0m"
                    restart_tunnel  # 如果需要，可以调用重启函数
                fi
            else
                echo -e "\e[1;3;31m找不到日志文件，无法检查临时隧道状态。\e[0m"
            fi
        else
            echo -e "\e[1;3;31mCloudflare 临时隧道服务已停止\e[0m"
            echo ""
        fi
    fi
}

# 检测协议并提供修改选项
detect_protocols() {
    echo -e "\e[1;3;33m正在检测已安装的协议...\e[0m"
    sleep 3
    # 获取已安装的协议类型
    protocols=$(jq -r '.inbounds[] | .type' /root/sbox/sbconfig_server.json)
    echo -e "\e[1;3;33m已安装协议如下:\e[0m"
    echo -e "\e[1;3;32m$protocols\e[0m"  # 输出协议信息，绿色斜体加粗
    echo ""
    
    # 初始化选项数组
    options=()
    protocol_list=("vless" "vmess" "hysteria2" "tuic")
    
    # 根据检测到的协议生成选项
    for protocol in "${protocol_list[@]}"; do
        if echo "$protocols" | grep -q -i "$protocol"; then
            options+=("${protocol^}")  # 将首字母大写
        fi
    done
    
    # 输出可修改的协议选项
    if [ ${#options[@]} -eq 0 ]; then
        echo -e "\e[1;3;31m没有检测到可修改的协议。\e[0m"
        return 1  # 返回非零值表示未找到协议
    fi

    echo -e "\e[1;3;33m请选择要修改的协议：\e[0m"
    for i in "${!options[@]}"; do
        echo -e "\e[1;3;32m$((i + 1))) ${options[i]}\e[0m"
    done
    
    # 添加“全部修改”选项
    echo -e "\e[1;3;32m$((i + 2))) 全部修改\e[0m"
    
    # 读取用户输入
    while true; do
        echo -e -n "\e[1;3;33m请输入选项 :\e[0m "
        read modify_choice
        if [[ "$modify_choice" =~ ^[1-9][0-9]*$ ]] && [ "$modify_choice" -le $((i + 2)) ]; then
            break
        else
            echo -e "\e[1;3;31m无效选项，请重新输入。\e[0m"
        fi
    done
    
    # 根据用户选择进行修改
    if [ "$modify_choice" -eq $((i + 2)) ]; then
        echo -e "\e[1;3;33m正在修改所有协议...\e[0m"
           echo ""
        # 这里添加代码以修改所有协议
        for protocol in "${options[@]}"; do
            echo -e "\e[1;3;32m请按照提示进行修改...\e[0m"
            case $protocol in
                "Vless")
                    modify_vless
                    ;;
                "Hysteria2")
                    modify_hysteria2
                    ;;
                "Tuic")
                    modify_tuic  # 需要定义此函数
                    ;;
            esac
        done
    else
        selected_protocol=${options[$((modify_choice - 1))]}
        echo -e "\e[1;3;33m正在修改 $selected_protocol 协议...\e[0m"
        case $selected_protocol in
            "Vless")
                modify_vless
                ;;
            "Hysteria2")
                modify_hysteria2
                ;;
            "Tuic")
                modify_tuic  
                ;;
        esac
    fi
}
# 修改vless协议
modify_vless() {
    show_notice "开始修改 VLESS 配置"
    sleep 2

    # 获取当前 VLESS 监听端口
    current_listen_port=$(jq -r '.inbounds[] | select(.type == "vless") | .listen_port' /root/sbox/sbconfig_server.json)
    
    if [ -z "$current_listen_port" ]; then
        echo "未能获取当前 VLESS 端口，请检查配置文件。"
        return 1
    fi

    # 输入新的 VLESS 端口，提示范围
    while true; do
        printf "\e[1;3;33m请输入想要修改的 VLESS 端口号 (当前端口为: %s，范围: 1-65535):\e[0m " "$current_listen_port"
        read listen_port  
        sleep 1
        
        # 自动生成随机端口号
        if [ -z "$listen_port" ]; then
            listen_port=$((RANDOM % 64512 + 1024))  # 生成 1024 到 65535 之间的随机端口
            echo -e "\e[1;3;32m未输入，已自动生成新的 VLESS 端口: $listen_port\e[0m"
            break
        fi
        
        # 验证端口范围
        if [[ "$listen_port" =~ ^[1-9][0-9]{0,4}$ && "$listen_port" -le 65535 ]]; then
            break  # 输入有效，退出循环
        else
            echo -e "\e[31m无效的端口号，请输入范围在 1-65535 之间的数字。\e[0m"
        fi
    done

    echo -e "\e[1;3;32m新的 VLESS 端口: $listen_port\e[0m"
    sleep 1

    # 获取当前服务器名
    current_server_name=$(jq -r '.inbounds[] | select(.type == "vless") | .tls.server_name' /root/sbox/sbconfig_server.json)
    
    if [ -z "$current_server_name" ]; then
        echo "未能获取当前 VLESS h2 域名，请检查配置文件。"
        return 1
    fi

    printf "\e[1;3;33m请输入想要修改的 VLESS h2 域名 (当前域名为: %s):\e[0m " "$current_server_name"
    read server_name
    server_name=${server_name:-$current_server_name}  # 如果输入为空则使用当前服务器名
    echo -e "\e[1;3;32m新的 VLESS h2 域名: $server_name\e[0m"
    sleep 1

    # 修改配置文件，确保只修改 listen_port 和 server_name
    jq --argjson listen_port "$listen_port" --arg server_name "$server_name" \
       '(.inbounds[] | select(.type == "vless")) |= (.listen_port = $listen_port | .tls.server_name = $server_name)' \
       /root/sbox/sbconfig_server.json > /root/sbox/sbconfig_server_tmp.json

    # 用临时文件替换原文件
    mv /root/sbox/sbconfig_server_tmp.json /root/sbox/sbconfig_server.json

    echo -e "\e[1;3;32m=== VLESS 配置修改完成 ===\e[0m"
    echo ""
}

# 修改hysteria2协议
modify_hysteria2() {
    show_notice "开始修改 Hysteria2 配置"
    sleep 2

    # 获取当前 Hysteria2 端口
    hy_current_listen_port=$(jq -r '.inbounds[] | select(.type == "hysteria2") | .listen_port' /root/sbox/sbconfig_server.json)

    if [ -z "$hy_current_listen_port" ]; then
        echo "未能获取当前 Hysteria2 端口，请检查配置文件。"
        return 1
    fi
    # 输入新的 Hysteria2 端口，提示范围
    while true; do
        printf "\e[1;3;33m请输入想要修改的 Hysteria2 端口 (当前端口为: %s，范围: 1-65535):\e[0m " "$hy_current_listen_port"
        read hy_listen_port
        sleep 1
        # 自动生成随机端口号
        if [ -z "$hy_listen_port" ]; then
            hy_listen_port=$((RANDOM % 64512 + 1024))  # 生成 1024 到 65535 之间的随机端口
            echo -e "\e[1;3;32m未输入，已自动生成新的 Hysteria2 端口: $hy_listen_port\e[0m"
            break
        fi

        # 验证端口范围
        if [[ "$hy_listen_port" =~ ^[1-9][0-9]{0,4}$ && "$hy_listen_port" -le 65535 ]]; then
            break  # 输入有效，退出循环
            sleep 1
        else
            echo -e "\e[31m无效的端口号，请输入范围在 1-65535 之间的数字。\e[0m"
        fi
    done

    echo -e "\e[1;3;32m新的 Hysteria2 端口: $hy_listen_port\e[0m"
    sleep 1

    # 使用 jq 更新 listen_port
    jq --argjson hy_listen_port "$hy_listen_port" \
        '(.inbounds[] | select(.type == "hysteria2") | .listen_port) = $hy_listen_port' \
        /root/sbox/sbconfig_server.json > /root/sbox/sbconfig_server.json.tmp

    # 确保 jq 成功执行
    if [ $? -eq 0 ]; then
        mv /root/sbox/sbconfig_server.json.tmp /root/sbox/sbconfig_server.json
        echo -e "\e[1;3;32m=== Hysteria2 配置修改完成 ===\e[0m"
        echo ""
    else
        echo "修改配置文件时出错。"
        rm /root/sbox/sbconfig_server.json.tmp  # 清理临时文件
        return 1
    fi
}

# 修改tuic协议
modify_tuic() {
    show_notice "开始修改 TUIC 配置"
    sleep 2

    # 获取当前 TUIC 监听端口
    tuic_current_listen_port=$(jq -r '.inbounds[] | select(.type == "tuic") | .listen_port' /root/sbox/sbconfig_server.json)

    if [ -z "$tuic_current_listen_port" ]; then
        echo "未能获取当前 TUIC 端口，请检查配置文件。"
        return 1
    fi

    # 输入新的 TUIC 端口，提示范围
    while true; do
        printf "\e[1;3;33m请输入想要修改的 TUIC 监听端口 (当前端口为: %s，范围: 1-65535):\e[0m " "$tuic_current_listen_port"
        read tuic_listen_port_input
        
        # 自动生成随机端口号
        if [ -z "$tuic_listen_port_input" ]; then
            tuic_listen_port=$((RANDOM % 64512 + 1024))  # 生成 1024 到 65535 之间的随机端口
            echo -e "\e[1;3;32m未输入，已自动生成新的 TUIC 端口: $tuic_listen_port\e[0m"
            break
        fi

        # 验证端口范围
        if [[ "$tuic_listen_port_input" =~ ^[1-9][0-9]{0,4}$ && "$tuic_listen_port_input" -le 65535 ]]; then
            tuic_listen_port="$tuic_listen_port_input"  # 输入有效，使用输入的端口
            break  # 退出循环
        else
            echo -e "\e[31m无效的端口号，请输入范围在 1-65535 之间的数字。\e[0m"
        fi
    done

    echo -e "\e[1;3;32m新的 TUIC 端口: $tuic_listen_port\e[0m"
    sleep 1

    # 修改配置文件
    jq --argjson listen_port "$tuic_listen_port" \
       '(.inbounds[] | select(.type == "tuic") | .listen_port) = $listen_port' \
       /root/sbox/sbconfig_server.json > /root/sbox/sbconfig_server_tmp.json

    # 确保 jq 成功执行
    if [ $? -eq 0 ]; then
        mv /root/sbox/sbconfig_server_tmp.json /root/sbox/sbconfig_server.json
        echo -e "\e[1;3;32m=== TUIC 配置修改完成 ===\e[0m"
        echo ""
    else
        echo "修改配置文件时出错。"
        rm /root/sbox/sbconfig_server_tmp.json  # 清理临时文件
        return 1
    fi
}

# 用户交互界面
while true; do
clear
echo -e "\e[1;3;32m===欢迎使用sing-box服务===\e[0m" 
echo -e "\e[1;3;31m=== argo隧道配置文件生成网址 \e[1;3;33mhttps://fscarmen.cloudflare.now.cc/\e[1;3;31m ===\e[0m"
echo -e "\e[1;3;33m=== 脚本支持: VLESS VMESS HY2 协议 ===\e[0m" 
echo ""
echo -e "\e[1;3;33m=== 脚本快捷键指令键：a 或 5 ===\e[0m" 
echo -e "\e[1;3;31m***********************\e[0m"
echo -e "\e[1;3;36m请选择选项:\e[0m"  # 青色斜体加粗
echo ""
echo -e "\e[1;3;32m1. 安装sing-box服务\e[0m"  # 绿色斜体加粗
echo  "==============="
echo -e "\e[1;3;33m2. 重新安装\e[0m"  # 黄色斜体加粗
echo  "==============="
echo -e "\e[1;3;36m3. 修改配置\e[0m"  # 青色斜体加粗
echo  "==============="
echo -e "\e[1;3;34m4. 显示客户端配置\e[0m"  # 蓝色斜体加粗
echo  "==============="
echo -e "\e[1;3;31m5. 卸载Sing-box\e[0m"  # 红色斜体加粗
echo  "==============="
echo -e "\e[1;3;32m6. 更新SingBox内核\e[0m"  # 绿色斜体加粗
echo  "==============="
echo -e "\e[1;3;36m7. 手动重启cloudflared\e[0m"  # 青色斜体加粗
echo  "==============="
echo -e "\e[1;3;32m8. 手动重启SingBox服务\e[0m"  # 绿色斜体加粗
echo  "==============="
echo -e "\e[1;3;35m9. 切换sing-box内核\e[0m"
echo  "==============="
echo -e "\e[1;3;32m10. 实时查看系统服务状态\e[0m"
echo  "==============="
echo -e "\e[1;3;31m0. 退出脚本\e[0m"  # 红色斜体加粗
echo  "==============="
echo ""
echo -ne "\e[1;3;33m输入您的选择 (0-9): \e[0m " 
read -e choice
echo ""
case $choice in
    1)
        echo -e "\e[1;3;32m开始安装sing-box服务，请稍后...\e[0m"
        echo " "
          mkdir -p "/root/sbox/"
        download_singbox
        download_cloudflared
        install_singbox
        setup_services
        sleep 2
        ;;
    2)
       reinstall_sing_box
        ;;
    3)
       # 主逻辑
       detect_protocols
       # 重启服务并验证
       echo -e "\e[1;3;33m配置修改完成，正在重新启动 sing-box 服务...\e[0m"
       systemctl restart sing-box
       systemctl restart cloudflared > /dev/null 2>&1
        sleep 2
         if [ $? -eq 0 ]; then
             echo -e "\e[1;3;32msing-box 服务重启成功\e[0m"
         else
            echo -e "\e[1;3;31msing-box 服务重启失败，请检查日志\e[0m"
            # 恢复备份
            mv /root/sbox/sbconfig_server_backup.json /root/sbox/sbconfig_server.json
         fi
           show_client_configuration
        ;;
    4)  
        show_client_configuration
        ;;	
    5)
 
        uninstall_singbox
        ;;
    6)
        show_notice "正在更新 Sing-box内核..."
        download_singbox
        if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
            echo -e "\e[1;3;32m配置检查成功，启动sing-box服务...\e[0m"
            systemctl daemon-reload
            systemctl enable sing-box > /dev/null 2>&1
            systemctl start sing-box
            systemctl restart sing-box
        fi
        echo ""
        ;;
    7)
        restart_tunnel
        ;;
    8) 
       # 检查配置并启动服务
if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
    systemctl daemon-reload
    systemctl enable sing-box > /dev/null 2>&1
    systemctl start sing-box
    systemctl restart sing-box
    # 打印成功信息，绿色加粗斜体
    echo -e "\e[1;3;32m启动成功，sing-box 服务已启动！\e[0m"
else
    echo "Error in configuration. Aborting"
fi
        ;;
    9)
     switch_kernel
      ;;
      
    10) 
      check_tunnel_status
      ;;
      
    0)
        echo -e "\e[1;3;31m已退出脚本\e[0m"
        exit 0
        ;;
     *)
   
        echo -e "\033[31m\033[1;3m无效的选项,请重新输入!\033[0m"
        echo ""
        ;;
 esac
  # 使用 printf 来输出提示信息
printf "\e[1;3;33m按任意键返回...\e[0m"
# 不换行，使光标保持在提示信息后面
read -n 1 -s -r
    clear
done

 
