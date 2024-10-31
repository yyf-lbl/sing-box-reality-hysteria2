#!/bin/bash
# Function to print characters with delay
print_with_delay() {
    local message="$1"
    local delay="$2"
    
    for (( i=0; i<${#message}; i++ )); do
        echo -ne "\e[1;3;32m${message:i:1}\e[0m"  # 打印每个字符，带有颜色和样式
        sleep "$delay"
    done
    echo  # 换行
}
#notice
show_notice() {
    local message="$1"
    local width=50  # 定义长方形的宽度
    local border_char="="  # 边框字符
    local yellow_color="\033[33m"  # 黄色
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
# install base
install_base(){
  # Check if jq is installed, and install it if not
  if ! command -v jq &> /dev/null; then
      echo "jq is not installed. Installing..."
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
# regenrate cloudflared argo
regenarte_cloudflared_argo(){
if [[ "$use_fixed" =~ ^[Yy]$ ]]; then
     pid=$(pgrep -f cloudflared-linux)
    if [ -n "$pid" ]; then
        # 终止现有进程
        kill "$pid"
    fi 
# 提示用户选择使用固定 Argo 隧道或临时隧道
read -p "Y 使用固定 Argo 隧道或 N 使用临时隧道？(Y/N，Enter 默认 Y): " use_fixed
use_fixed=${use_fixed:-Y}
    # 登录 CF 授权并下载证书
    /root/sbox/cloudflared-linux tunnel login
    # 设置证书路径
    export TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem
    # 用户输入 Argo 域名和密钥
    read -p "请输入你的 Argo 域名: " argo_domain
    read -p "请输入你的 Argo 密钥 (token 或 json): " argo_auth
    # 处理 Argo 的配置
    if [[ $argo_auth =~ TunnelSecret ]]; then
        # 创建 JSON 凭据文件
        echo "$argo_auth" > /root/sbox/tunnel.json

        # 生成 tunnel.yml 文件
        cat > /root/sbox/tunnel.yml << EOF
tunnel: $(echo "$argo_auth" | jq -r '.TunnelID')
credentials-file: /root/sbox/tunnel.json
origincert: $TUNNEL_ORIGIN_CERT
protocol: http2

ingress:
  - hostname: $argo_domain
    service: http://localhost:$vmess_port
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

        echo "生成的 tunnel.yml 文件内容:"
        cat /root/sbox/tunnel.yml
        # 启动固定隧道
       /root/sbox/cloudflared-linux tunnel --config /root/sbox/tunnel.yml run > /root/sbox/argo_run.log 2>&1 &
        echo "固定隧道已启动，日志输出到 /root/sbox/argo_run.log"
    fi
else
    # 用户选择使用临时隧道
    pid=$(pgrep -f cloudflared)
    if [ -n "$pid" ]; then
        # 终止现有进程
        kill "$pid"
    fi 
    # 启动临时隧道
    /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux > /root/sbox/argo.log 2>&1 & 
    sleep 2
    echo "等待 Cloudflare Argo 生成地址"
    sleep 5   
    # 获取连接到域名
    argo=$(grep "trycloudflare.com" /root/sbox/argo.log | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    echo "$argo" | base64 > /root/sbox/argo.txt.b64
fi
  rm -rf argo.log
  }
# download singbox and cloudflared
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
  echo ""
}
# download singbox 
download_singbox() {
    echo -e "\e[1;3;33m正在下载sing-box内核...\e[0m"
    sleep 3
    arch=$(uname -m)
    echo -e "\e[1;3;32m本机系统架构: $arch（ amd64，64-bit 架构）\e[0m"

    # Map architecture names
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

    latest_version_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | grep -Po '"tag_name": "\K.*?(?=")' | sort -V | tail -n 1)
    latest_version=${latest_version_tag#v}  # Remove 'v' prefix from version number
    echo -e "\e[1;3;32m当前最新版本: $latest_version\e[0m"

    package_name="sing-box-${latest_version}-linux-${arch}"
    download_path="/root/${package_name}.tar.gz"

    # Check if the package already exists
    if [ -f "/root/sbox/sing-box" ]; then
        echo -e "\e[1;3;32m文件已经存在，跳过下载。\e[0m"
    else
        # Download sing-box
        url="https://github.com/SagerNet/sing-box/releases/download/${latest_version_tag}/${package_name}.tar.gz"
        curl -sLo "$download_path" "$url"

        # 解压和移动文件
        tar -xzf "$download_path" -C /root
        mv "/root/${package_name}/sing-box" /root/sbox
        rm -r "$download_path" "/root/${package_name}"
        chown root:root /root/sbox/sing-box
        chmod +x /root/sbox/sing-box
    fi
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
         echo ""
         echo -e "\e[1;3;33m$hy2_server_link\e[0m"
         echo ""
    fi
  
   # 判断是否存在固定隧道配置 生成 VMess 客户端链接
# 检查是否存在固定隧道
if [ "$use_fixed" = "Y" ]; then
    # 使用固定隧道生成链接
    if jq -e '.ingress[] | select(.service == "http://localhost:$vmess_port")' /root/sbox/tunnel.yml > /dev/null; then
        fixed_tunnel_domain=$(jq -r '.ingress[] | select(.service == "http://localhost:$vmess_port") | .hostname' /root/sbox/tunnel.yml)
        echo -e "\e[1;3;31m使用固定隧道生成的 Vmess 客户端通用链接\e[0m"

        # 生成固定隧道链接
        vmess_link_tls='vmess://'$(echo '{"add":"'$fixed_tunnel_domain'","aid":"0","host":"'$fixed_tunnel_domain'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"sing-box-vmess-tls","tls":"tls","type":"none","v":"2"}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_tls\e[0m"

        vmess_link_no_tls='vmess://'$(echo '{"add":"'$fixed_tunnel_domain'","aid":"0","host":"'$fixed_tunnel_domain'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"sing-box-vmess","tls":"","type":"none","v":"2"}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_no_tls\e[0m"
    else
        echo -e "\e[1;3;31m未找到对应的固定隧道配置。\e[0m"
    fi
else
    # 不存在固定隧道，生成临时隧道链接
    if jq -e '.inbounds[] | select(.type == "vmess")' /root/sbox/sbconfig_server.json > /dev/null; then
        vmess_uuid=$(jq -r '.inbounds[] | select(.type == "vmess") | .users[0].uuid' /root/sbox/sbconfig_server.json)
        ws_path=$(jq -r '.inbounds[] | select(.type == "vmess") | .transport.path' /root/sbox/sbconfig_server.json)
        argo=$(base64 --decode /root/sbox/argo.txt.b64)

        echo -e "\e[1;3;31m使用临时隧道生成的 Vmess 客户端通用链接\e[0m"
        echo -e "\e[1;3;32m以下端口 443 可改为 2053 2083 2087 2096 8443\e[0m"
        
        vmess_link_tls='vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"sing-box-vmess-tls","tls":"tls","type":"none","v":"2","allowInsecure":true}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_tls\e[0m"
        
        echo -e "\e[1;3;32m以下端口 80 可改为 8080 8880 2052 2082 2086 2095\e[0m"
        
        vmess_link_no_tls='vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"sing-box-vmess","tls":"","type":"none","v":"2","allowInsecure":true}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_no_tls\e[0m"
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
uninstall_singbox() {
    echo -e "\e[1;3;31m正在卸载sing-box服务...\e[0m"
    sleep 3
    # 尝试停止并禁用singbox服务，如果未发现错误，则抑制错误
    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    # 定义要删除的文件和目录
    files_to_remove=(
        "/etc/systemd/system/sing-box.service"
        "/etc/systemd/system/argo.service"
        "/root/sbox/sbconfig_server.json"
        "/root/sbox/sing-box"
        "/root/sbox/cloudflared-linux"
        "/root/sbox/argo.txt.b64"
        "/root/sbox/public.key.b64"
        "/root/self-cert/private.key"
        "/root/self-cert/cert.pem"
        "/root/.cloudflared"
        "/root/sbox"
    )
    directories_to_remove=(
        "/root/self-cert/"
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
   echo -e "\e[1;3;32msing-box已成功卸载!\e[0m"
echo -e "\e[1;3;32m所有sing-box配置文件已完全移除\e[0m"

}
install_base
install_singbox() { 
  while true; do
   echo -e "\e[1;3;33m请选择要安装的协议（输入数字，多个选择用空格分隔）:\e[0m"
   echo -e "\e[1;3;33m1) vless-Reality\e[0m"
   echo -e "\e[1;3;33m2) VMess\e[0m"
   echo -e "\e[1;3;33m3) Hysteria2\e[0m"
   echo -e "\e[1;3;33m4) Tuic\e[0m"
   echo -ne "\e[1;3;33m请输入你的选择: \e[0m" && read choices
    # 将用户输入的选择转为数组
    read -a selected_protocols <<< "$choices"
    # 检查输入的选择是否有效
    valid=true
    for choice in "${selected_protocols[@]}"; do
        if ! [[ "$choice" =~ ^[1-4]$ ]]; then
            valid=false
            break
        fi
    done
    if $valid; then
        # 有效输入，跳出循环
        break
    else
        echo -e "\e[1;3;31m输入无效!请选择1-4\e[0m"
    fi
done
    # 初始化配置变量
    listen_port=443
    vmess_port=15555
    hy_listen_port=8443
    tuic_listen_port=8080
    config="{\"log\": {\"disabled\": false, \"level\": \"info\", \"timestamp\": true}, \"inbounds\": [], \"outbounds\": [{\"type\": \"direct\", \"tag\": \"direct\"}, {\"type\": \"block\", \"tag\": \"block\"}]}"
    for choice in $choices; do
        case $choice in
            1)
                echo "开始配置 Reality"
                sleep 3
                # 生成 Reality 密钥对
                key_pair=$(/root/sbox/sing-box generate reality-keypair)
                if [ $? -ne 0 ]; then
                    echo "生成 Reality 密钥对失败。"
                    exit 1
                fi
                private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
                public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
                echo "$public_key" | base64 > /root/sbox/public.key.b64
                uuid=$(/root/sbox/sing-box generate uuid)
                short_id=$(/root/sbox/sing-box generate rand --hex 8)
                echo "UUID 和短 ID 生成完成"
                echo ""
                read -p "请输入 Reality 端口 (default: 443): " listen_port_input
                listen_port=${listen_port_input:-443}
                read -p "请输入想要使用的域名 (default: itunes.apple.com): " server_name_input
                server_name=${server_name_input:-itunes.apple.com}
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
           echo "开始配置 vmess"
sleep 1

# 生成 vmess UUID
vmess_uuid=$(/root/sbox/sing-box generate uuid)

# 询问 vmess 端口
read -p "请输入 vmess 端口，默认为 15555: " vmess_port
vmess_port=${vmess_port:-15555}
echo ""

# 询问 ws 路径
read -p "ws 路径 (默认随机生成): " ws_path
ws_path=${ws_path:-$(/root/sbox/sing-box generate rand --hex 6)}

# 提示用户选择使用固定 Argo 隧道或临时隧道
read -p "Y 使用固定 Argo 隧道或 N 使用临时隧道？(Y/N，Enter 默认 Y): " use_fixed
use_fixed=${use_fixed:-Y}

if [[ "$use_fixed" =~ ^[Yy]$ ]]; then
     pid=$(pgrep -f cloudflared-linux)
    if [ -n "$pid" ]; then
        # 终止现有进程
        kill "$pid"
    fi 
    # 登录 CF 授权并下载证书
    /root/sbox/cloudflared-linux tunnel login

    # 设置证书路径
    export TUNNEL_ORIGIN_CERT=/root/.cloudflared/cert.pem

    # 用户输入 Argo 域名和密钥
    read -p "请输入你的 Argo 域名: " argo_domain
    read -p "请输入你的 Argo 密钥 (token 或 json): " argo_auth

    # 处理 Argo 的配置
    if [[ $argo_auth =~ TunnelSecret ]]; then
        # 创建 JSON 凭据文件
        echo "$argo_auth" > /root/sbox/tunnel.json

        # 生成 tunnel.yml 文件
        cat > /root/sbox/tunnel.yml << EOF
tunnel: $(echo "$argo_auth" | jq -r '.TunnelID')
credentials-file: /root/sbox/tunnel.json
origincert: $TUNNEL_ORIGIN_CERT
protocol: http2

ingress:
  - hostname: $argo_domain
    service: http://localhost:$vmess_port
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

        echo "生成的 tunnel.yml 文件内容:"
        cat /root/sbox/tunnel.yml
        # 启动固定隧道
       /root/sbox/cloudflared-linux tunnel --config /root/sbox/tunnel.yml run > /root/sbox/argo_run.log 2>&1 &
        echo "固定隧道已启动，日志输出到 /root/sbox/argo_run.log"
    fi
else
    # 用户选择使用临时隧道
    pid=$(pgrep -f cloudflared)
    if [ -n "$pid" ]; then
        # 终止现有进程
        kill "$pid"
    fi 
    # 启动临时隧道
    /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux > /root/sbox/argo.log 2>&1 & 
    sleep 2
    echo "等待 Cloudflare Argo 生成地址"
    sleep 2  

    # 获取连接到域名
    argo=$(grep "trycloudflare.com" /root/sbox/argo.log | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    echo "$argo" | base64 > /root/sbox/argo.txt.b64
fi

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
               echo "开始配置 Hysteria2"
                echo ""
                hy_password=$(/root/sbox/sing-box generate rand --hex 8)
                read -p "请输入 Hysteria2 监听端口 (default: 8443): " hy_listen_port_input
                hy_listen_port=${hy_listen_port_input:-8443}
                read -p "输入自签证书域名 (default: bing.com): " hy_server_name_input
                hy_server_name=${hy_server_name_input:-bing.com}
                mkdir -p /root/self-cert/
                openssl ecparam -genkey -name prime256v1 -out /root/self-cert/private.key
                openssl req -new -x509 -days 36500 -key /root/self-cert/private.key -out /root/self-cert/cert.pem -subj "/CN=${hy_server_name}"
                echo "自签证书生成完成"
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
    echo "开始配置 TUIC"
    echo ""
    tuic_password=$(/root/sbox/sing-box generate rand --hex 8)
    tuic_uuid=$(/root/sbox/sing-box generate uuid)  # 生成 uuid
    read -p "请输入 TUIC 监听端口 (default: 8080): " tuic_listen_port_input
    tuic_listen_port=${tuic_listen_port_input:-8080}
    read -p "输入 TUIC 自签证书域名 (default: bing.com): " tuic_server_name_input
    tuic_server_name=${tuic_server_name_input:-bing.com}

    mkdir -p /root/self-cert/
    openssl ecparam -genkey -name prime256v1 -out /root/self-cert/private.key
    openssl req -new -x509 -days 36500 -key /root/self-cert/private.key -out /root/self-cert/cert.pem -subj "/CN=${tuic_server_name}"
    echo "自签证书生成完成"
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
    echo "配置文件已生成：/root/sbox/sbconfig_server.json"
            # 创建服务启动文件
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
     # 检查配置并启动服务
   if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
      echo -e "\e[1;3;33m配置检查成功，正在启动 sing-box 服务...\e[0m"
      systemctl daemon-reload
      systemctl enable sing-box > /dev/null 2>&1
      systemctl start sing-box
    if systemctl is-active --quiet sing-box; then
        echo -e "\e[1;3;32msing-box 服务已成功启动！\e[0m"
    else
       echo -e "\e[1;3;31msing-box 服务启动失败！\e[0m"
    fi
    systemctl restart sing-box
    show_client_configuration
else
    echo -e "\e[1;3;33m配置错误，sing-box 服务未启动！\e[0m"
fi
}
reinstall_sing_box() {
    show_notice "重新安装中..."

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

# 用户交互界面
while true; do
# Introduction animation
clear
echo -e "\e[1;3;32m===欢迎使用sing-box服务===\e[0m" 
echo ""
echo -e "\e[1;3;33m=== 脚本支持: VLESS VMESS HY2 协议 ===\e[0m"  # 蓝色斜体加粗
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
echo -e "\e[1;3;31m5. 卸载SingBox\e[0m"  # 红色斜体加粗
echo  "==============="
echo -e "\e[1;3;32m6. 更新SingBox内核\e[0m"  # 绿色斜体加粗
echo  "==============="
echo -e "\e[1;3;36m7. 手动重启cloudflared\e[0m"  # 青色斜体加粗
echo  "==============="
echo -e "\e[1;3;32m8. 手动重启SingBox服务\e[0m"  # 绿色斜体加粗
echo  "==============="
echo -e "\e[1;3;31m0. 退出脚本\e[0m"  # 红色斜体加粗
echo  "==============="
echo ""
echo -ne "\e[1;3;33m输入您的选择 (0-8): \e[0m " 
read -e choice
  # 黄色斜体加粗
case $choice in
    1)

        echo -e "\e[1;3;32m开始安装sing-box服务，请稍后...\e[0m"
        echo " "
          mkdir -p "/root/sbox/"
         download_singbox
        download_cloudflared
        install_singbox
        sleep 2
        ;;
    2)
       reinstall_sing_box
        ;;
    3)
      # 检测协议并提供修改选项
detect_protocols() {
    echo "正在检测已安装的协议..."
    protocols=$(jq -r '.inbounds[] | .type' /root/sbox/sbconfig_server.json)

    echo "检测到的协议:"
    echo "$protocols"

    echo ""
    echo "请选择要修改的协议："
    echo "1) VLESS"
    echo "2) Hysteria2"
    echo "3) 全部修改"
    read -p "请输入选项 (1/2/3): " modify_choice
}
modify_vless() {
    show_notice "开始修改 VLESS 配置"

    # 获取当前端口
    current_listen_port=$(jq -r '.inbounds[] | select(.type == "vless") | .listen_port' /root/sbox/sbconfig_server.json)
    
    if [ -z "$current_listen_port" ]; then
        echo "未能获取当前 VLESS 端口，请检查配置文件。"
        return 1
    fi

    read -p "请输入想要修改的 VLESS 端口号 (当前端口为 $current_listen_port): " listen_port
    listen_port=${listen_port:-$current_listen_port}

    # 获取当前服务器名
    current_server_name=$(jq -r '.inbounds[] | select(.type == "vless") | .tls.server_name' /root/sbox/sbconfig_server.json)

    if [ -z "$current_server_name" ]; then
        echo "未能获取当前 VLESS h2 域名，请检查配置文件。"
        return 1
    fi

    read -p "请输入想要使用的 VLESS h2 域名 (当前域名为 $current_server_name): " server_name
    server_name=${server_name:-$current_server_name}

    # 修改配置文件
    jq --arg listen_port "$listen_port" --arg server_name "$server_name" \
        '.inbounds[] | select(.type == "vless") | .listen_port = ($listen_port | tonumber) | .tls.server_name = $server_name | .tls.reality.handshake.server = $server_name' \
        /root/sbox/sbconfig_server.json > /root/sb_modified_vless.json

    mv /root/sb_modified_vless.json /root/sbox/sbconfig_server.json
    echo "VLESS 配置修改完成"
}

modify_hysteria2() {
    show_notice "开始修改 Hysteria2 配置"
    hy_current_listen_port=$(jq -r '.inbounds[] | select(.type == "hysteria2") | .listen_port' /root/sbox/sbconfig_server.json)

    if [ -z "$hy_current_listen_port" ]; then
        echo "未能获取当前 Hysteria2 端口，请检查配置文件。"
        return 1
    fi

    read -p "请输入想要修改的 Hysteria2 端口 (当前端口为 $hy_current_listen_port): " hy_listen_port
    hy_listen_port=${hy_listen_port:-$hy_current_listen_port}

    jq --arg hy_listen_port "$hy_listen_port" \
        '.inbounds[] | select(.type == "hysteria2") | .listen_port = ($hy_listen_port | tonumber)' \
        /root/sbox/sbconfig_server.json > /root/sb_modified_hysteria.json

    # 使用 `sponge` 避免覆盖的问题，确保可以同时读取和写入
    mv /root/sb_modified_hysteria.json /root/sbox/sbconfig_server.json

    echo "Hysteria2 配置修改完成"
}

# 主逻辑
detect_protocols
# 根据用户选择进行修改
case $modify_choice in
    1)
        modify_vless
        ;;
    2)
        modify_hysteria2
        ;;
    3)
        modify_vless
        modify_hysteria2
        ;;
    *)
        echo "无效选项，退出"
        exit 1
        ;;
esac
# 重启服务并验证
echo "配置修改完成，重新启动 sing-box 服务..."
systemctl restart sing-box
if [ $? -eq 0 ]; then
    echo "sing-box 服务重启成功"
else
    echo "sing-box 服务重启失败，请检查日志"
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

        regenarte_cloudflared_argo
        echo "重新启动完成，查看新的vmess客户端信息"
        show_client_configuration
    
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

    0)
        echo -e "\e[1;3;31m已退出脚本\e[0m"
        exit 0
        ;;
    *)
   
        echo -e "\033[31m\033[1;3m无效的选项,请重新输入!\033[0m"
        ;;
 esac
  # 使用 printf 来输出提示信息
printf "\e[1;3;33m按任意键返回...\e[0m"
# 不换行，使光标保持在提示信息后面
read -n 1 -s -r
    clear
done

 
