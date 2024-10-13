#!/bin/bash
# Function to print characters with delay
print_with_delay() {
    text="$1"
    delay="$2"
    for ((i = 0; i < ${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}
#notice
show_notice() {
    local message="$1"

    echo "#######################################################################################################################"
    echo "                                                                                                                       "
    echo "                                ${message}                                                                             "
    echo "                                                                                                                       "
    echo "#######################################################################################################################"
}
# Introduction animation
print_with_delay "欢迎使用sing-box服务" 0.05
echo ""
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
  pid=$(pgrep -f cloudflared)
  if [ -n "$pid" ]; then
    # 终止进程
    kill "$pid"
  fi
  vmess_port=$(jq -r '.inbounds[2].listen_port' /root/sbox/sbconfig_server.json)
  #生成地址
  /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux>argo.log 2>&1 &
  sleep 2
  clear
  echo 等待cloudflare argo生成地址
  sleep 5
  #连接到域名
  argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
  echo "$argo" | base64 > /root/sbox/argo.txt.b64
  rm -rf argo.log
  }
# download singbox and cloudflared
download_singbox(){
  arch=$(uname -m)
  echo "Architecture: $arch"
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
  echo "Latest version: $latest_version"
  package_name="sing-box-${latest_version}-linux-${arch}"
  url="https://github.com/SagerNet/sing-box/releases/download/${latest_version_tag}/${package_name}.tar.gz"
  curl -sLo "/root/${package_name}.tar.gz" "$url"
  tar -xzf "/root/${package_name}.tar.gz" -C /root
  mv "/root/${package_name}/sing-box" /root/sbox
  rm -r "/root/${package_name}.tar.gz" "/root/${package_name}"
  chown root:root /root/sbox/sing-box
  chmod +x /root/sbox/sing-box
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
    # 生成 VMess 客户端链接
    if jq -e '.inbounds[] | select(.type == "vmess")' /root/sbox/sbconfig_server.json > /dev/null; then
        vmess_uuid=$(jq -r '.inbounds[] | select(.type == "vmess") | .users[0].uuid' /root/sbox/sbconfig_server.json)
        ws_path=$(jq -r '.inbounds[] | select(.type == "vmess") | .transport.path' /root/sbox/sbconfig_server.json)
        argo=$(base64 --decode /root/sbox/argo.txt.b64)
        echo -e "\e[1;3;31mVmess 客户端通用链接，替换speed.cloudflare.com为自己的优选ip可获得极致体验\e[0m"
        echo ""
       echo -e "\e[1;3;32m以下端口 443 可改为 2053 2083 2087 2096 8443\e[0m"
        echo ""
        vmess_link_tls='vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"sing-box-vmess-tls","tls":"tls","type":"none","v":"2"}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_tls\e[0m"
        echo ""
        echo -e "\e[1;3;32m以下端口 80 可改为 8080 8880 2052 2082 2086 2095\e[0m" 
        echo ""
        vmess_link_no_tls='vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"sing-box-vmess","tls":"","type":"none","v":"2"}' | base64 -w 0)
          echo -e "\e[1;3;33m$vmess_link_no_tls\e[0m"
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
echo -e "\e[1;3;33m1) Reality\e[0m"
echo -e "\e[1;3;33m2) VMess\e[0m"
echo -e "\e[1;3;33m3) Hysteria2\e[0m"
   echo -e "\e[1;3;33m你的选择: \e[0m" && read choices
    # 将用户输入的选择转为数组
    read -a selected_protocols <<< "$choices"
    # 检查输入的选择是否有效
    valid=true
    for choice in "${selected_protocols[@]}"; do
        if ! [[ "$choice" =~ ^[1-3]$ ]]; then
            valid=false
            break
        fi
    done
    if $valid; then
        # 有效输入，跳出循环
        break
    else
        echo "输入无效，请选择 1, 2 或 3。"
    fi
done
    # 初始化配置变量
    listen_port=443
    vmess_port=15555
    hy_listen_port=8443
    config="{\"log\": {\"disabled\": false, \"level\": \"info\", \"timestamp\": true}, \"inbounds\": [], \"outbounds\": [{\"type\": \"direct\", \"tag\": \"direct\"}, {\"type\": \"block\", \"tag\": \"block\"}]}"
    for choice in $choices; do
        case $choice in
            1)
                echo "开始配置 Reality"
                echo ""
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
                echo "开始配置 VMess"
                echo ""

                echo "开始配置vmess"
echo ""
# Generate hysteria necessary values
vmess_uuid=$(/root/sbox/sing-box generate uuid)
read -p "请输入vmess端口，默认为15555: " vmess_port
vmess_port=${vmess_port:-15555}
echo ""
read -p "ws路径 (默认随机生成): " ws_path
ws_path=${ws_path:-$(/root/sbox/sing-box generate rand --hex 6)}
pid=$(pgrep -f cloudflared)
if [ -n "$pid" ]; then
  # 终止进程
  kill "$pid"
fi
#生成地址
/root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux>argo.log 2>&1 &
sleep 2
clear
echo 等待cloudflare argo生成地址
sleep 5
#连接到域名
argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
echo "$argo" | base64 > /root/sbox/argo.txt.b64
rm -rf argo.log
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
              *)
                echo "无效选择: $choice"
                ;;    
        esac
    done
    # 生成最终配置文件
    echo "$config" > /root/sbox/sbconfig_server.json
    echo "配置文件已生成：/root/sbox/sbconfig_server.json"
}

# 用户交互界面
 clear
echo -e "\e[1;3;33m脚本支持: VLESS VMESS HY2 协议\e[0m"  # 蓝色斜体加粗
echo -e "\e[1;3;36m请选择选项:\e[0m"  # 青色斜体加粗
echo ""
echo -e "\e[1;3;32m1. 安装sing-box服务\e[0m"  # 绿色斜体加粗
echo -e "\e[1;3;33m2. 重新安装\e[0m"  # 黄色斜体加粗
echo -e "\e[1;3;36m3. 修改配置\e[0m"  # 青色斜体加粗
echo -e "\e[1;3;34m4. 显示客户端配置\e[0m"  # 蓝色斜体加粗
echo -e "\e[1;3;31m5. 卸载\e[0m"  # 红色斜体加粗
echo -e "\e[1;3;32m6. 更新sing-box内核\e[0m"  # 绿色斜体加粗
echo -e "\e[1;3;36m7. 手动重启cloudflared\e[0m"  # 青色斜体加粗
echo -e "\e[1;3;32m8. 手动重启sing-box服务\e[0m"  # 绿色斜体加粗
echo -e "\e[1;3;31m0. 退出脚本\e[0m"  # 红色斜体加粗
echo ""
echo -ne "\e[1;3;33m输入您的选择 (0-10): \e[0m " 
read -e choice
  # 黄色斜体加粗
case $choice in
    1)
        echo -e "\e[1;3;32m开始安装sing-box服务...\e[0m"
          mkdir -p "/root/sbox/"
         download_singbox
        download_cloudflared
        install_singbox
        ;;
    2)
        show_notice "重新安装中..."
        systemctl stop sing-box
        systemctl disable sing-box > /dev/null 2>&1
        rm /etc/systemd/system/sing-box.service
        rm /root/sbox/sbconfig_server.json
        rm /root/sbox/sing-box
        rm /root/sbox/cloudflared-linux
        rm /root/sbox/argo.txt.b64
        rm /root/sbox/public.key.b64
        rm -rf /root/self-cert/
        rm -rf /root/sbox/  
        # 重新安装的步骤
        install_singbox
        ;;
    3)
        show_notice "开始修改reality端口和域名"
        current_listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
        read -p "请输入想要修改的端口号 (当前端口为 $current_listen_port): " listen_port
        listen_port=${listen_port:-$current_listen_port}
        
        current_server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
        read -p "请输入想要使用的h2域名 (当前域名为 $current_server_name): " server_name
        server_name=${server_name:-$current_server_name}

        show_notice "开始修改hysteria2端口"
        hy_current_listen_port=$(jq -r '.inbounds[1].listen_port' /root/sbox/sbconfig_server.json)
        read -p "请输入想要修改的端口 (当前端口为 $hy_current_listen_port): " hy_listen_port
        hy_listen_port=${hy_listen_port:-$hy_current_listen_port}

        jq --arg listen_port "$listen_port" --arg server_name "$server_name" --arg hy_listen_port "$hy_listen_port" \
            '.inbounds[1].listen_port = ($hy_listen_port | tonumber) | .inbounds[0].listen_port = ($listen_port | tonumber) | .inbounds[0].tls.server_name = $server_name | .inbounds[0].tls.reality.handshake.server = $server_name' \
            /root/sbox/sbconfig_server.json > /root/sb_modified.json

        mv /root/sb_modified.json /root/sbox/sbconfig_server.json

        echo "配置修改完成，重新启动sing-box服务..."
        systemctl restart sing-box
        show_client_configuration
        exit 0
        ;;
    4)  
        show_client_configuration
        exit 0
        ;;	
    5)
        uninstall_singbox
        exit 0
        ;;
    6)
        show_notice "更新 Sing-box..."
        download_singbox
        if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
            echo "配置检查成功，启动sing-box服务..."
            systemctl daemon-reload
            systemctl enable sing-box > /dev/null 2>&1
            systemctl start sing-box
            systemctl restart sing-box
        fi
        echo ""
        exit 1
        ;;
    7)
        regenarte_cloudflared_argo
        echo "重新启动完成，查看新的vmess客户端信息"
        show_client_configuration
        exit 1
        ;;
    8)  
       # 检查配置并启动服务
 if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
    systemctl daemon-reload
    systemctl enable sing-box > /dev/null 2>&1
    systemctl start sing-box
    systemctl restart sing-box
else
    echo "Error in configuration. Aborting"
fi
        ;;

    0)
        echo "已退出脚本"
        exit 0
        ;;
    *)
        echo "无效选项。正在退出。"
        exit 1
        ;;
esac
# Create sing-box.service
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


