#!/bin/bash
# 全局数组 
declare -a uuids
declare -a listen_ports
declare -a vmess_uuids
declare -a short_ids
declare -a server_names
declare -a hy_listen_ports
declare -a hy_passwords
declare -a vmess_ports
declare -a ws_paths
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
print_with_delay "欢迎使用三协议一键脚本" 0.05
echo ""
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
  vmess_port=$vmess_ports
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
download_singbox(){
  arch=$(uname -m)
  echo "Architecture: $arch"
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
download_cloudflared(){
  arch=$(uname -m)
  # Map architecture names
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
   current_listen_port=${listen_ports[@]}
  current_server_name=${server_names[@]}
  uuid=${uuids[@]}
  public_key=$(base64 --decode /root/sbox/public.key.b64)
  short_id=${short_ids[@]}
  server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)
  echo ""
  echo ""
  show_notice "Reality 客户端通用链接" 
  echo ""
  echo ""
  server_link="vless://$uuid@$server_ip:$current_listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$current_server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#SING-BOX-Reality"
  echo ""
  echo ""
  echo "$server_link"
  echo ""
  show_notice "Reality 客户端通用参数" 
  echo ""
  echo "服务器ip: $server_ip"
  echo "监听端口: $current_listen_port"
  echo "UUID: $uuid"
  echo "域名SNI: $current_server_name"
  echo "Public Key: $public_key"
  echo "Short ID: $short_id"
  echo ""
  hy_current_listen_port=${listen_ports[@]}
  hy_current_server_name=${server_names[@]}
  hy_password=${hy_passwords[@]}
  hy2_server_link="hysteria2://$hy_password@$server_ip:$hy_current_listen_port?insecure=1&sni=$hy_current_server_name"
  show_notice "Hysteria2 客户端通用链接" 
  echo ""
  echo "官方 hysteria2通用链接格式"
  echo ""
  echo "$hy2_server_link"
  echo ""
  show_notice "Hysteria2 客户端通用参数" 
  echo ""
  echo "服务器ip: $server_ip"
  echo "端口号: $hy_current_listen_port"
  echo "password: $hy_password"
  echo "域名SNI: $hy_current_server_name"
  echo "跳过证书验证: True"
  echo ""
  show_notice "Hysteria2 客户端yaml文件" 
cat << EOF
server: $server_ip:$hy_current_listen_port
auth: $hy_password
tls:
  sni: $hy_current_server_name
  insecure: true
# 可自己修改对应带宽，不添加则默认为bbr，否则使用hy2的brutal拥塞控制
# bandwidth:
#   up: 100 mbps
#   down: 100 mbps
fastOpen: true
socks5:
  listen: 127.0.0.1:5080
EOF
  argo=$(base64 --decode /root/sbox/argo.txt.b64)
  vmess_uuid=${vmess_uuids[@]}
  ws_path=${ws_paths[@]}
  show_notice "vmess ws 通用链接参数" 
  echo ""
  echo "以下为vmess链接，替换speed.cloudflare.com为自己的优选ip可获得极致体验"
  echo ""
  echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"sing-box-vmess-tls","tls":"tls","type":"none","v":"2"}' | base64 -w 0)
  echo ""
  echo -e "端口 443 可改为 2053 2083 2087 2096 8443"
  echo ""
  echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"sing-box-vmess","tls":"","type":"none","v":"2"}' | base64 -w 0)
  echo ""
  echo -e "端口 80 可改为 8080 8880 2052 2082 2086 2095" 
  echo ""
}
uninstall_singbox() {
            echo "Uninstalling..."
          systemctl stop sing-box
          systemctl disable sing-box > /dev/null 2>&1
          rm /etc/systemd/system/sing-box.service
          rm /root/sbox/sbconfig_server.json
          rm /root/sbox/sing-box
          rm /root/sbox/cloudflared-linux
          rm /root/sbox/argo.txt.b64
          rm /root/sbox/public.key.b64
          rm /root/self-cert/private.key
          rm /root/self-cert/cert.pem
          rm -rf /root/self-cert/
          rm -rf /root/sbox/
          if [ -f /root/sbox/argo.txt.b64 ]; then
  rm /root/sbox/argo.txt.b64
fi
          echo "DONE!"
}
install_base

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
# 检测配置并启动服务
start_singbox(){
if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
    echo "Configuration checked successfully. Starting sing-box service..."
    systemctl daemon-reload
    systemctl enable sing-box > /dev/null 2>&1
    systemctl start sing-box
    systemctl restart sing-box
    show_client_configuration
else
    echo "Error in configuration. Aborting"
fi
}
configure_reality() {
    echo "开始配置Reality"
    echo ""
    echo "自动生成基本参数..."
    key_pair=$(/root/sbox/sing-box generate reality-keypair)    
    if [[ $? -ne 0 ]]; then
        echo "生成 key pair 失败，请检查 sing-box 是否正确安装。"
        return 1
    fi
    echo "Key pair生成完成"
    echo ""
    private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
    public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
    echo "$public_key" | base64 > /root/sbox/public.key.b64
    uuid=$(/root/sbox/sing-box generate uuid)
    short_id=$(/root/sbox/sing-box generate rand --hex 8) 
    if [[ $? -ne 0 ]]; then
        echo "生成 UUID 和短ID 失败。"
        return 1
    fi
    echo "uuid和短id 生成完成"
    echo ""
    read -p "请输入Reality端口 (default: 443): " listen_port
    listen_port=${listen_port:-443}
    echo "选择的Reality端口: $listen_port"
    echo ""
    read -p "请输入想要使用的域名 (default: itunes.apple.com): " server_name
    server_name=${server_name:-itunes.apple.com}
    echo "选择的域名: $server_name"
    echo ""
    listen_ports+=("$listen_port")
    uuids+=("$uuid")
    short_ids+=("$short_id")
    server_names+=("$server_name")
}
configure_hysteria2() {
    echo "开始配置hysteria2"
    echo ""
    hy_password=$(/root/sbox/sing-box generate rand --hex 8)
    if [[ $? -ne 0 ]]; then
        echo "生成随机密码失败。"
        return 1
    fi
    read -p "请输入hysteria2监听端口 (default: 8443): " hy_listen_port
    hy_listen_port=${hy_listen_port:-8443}
    echo "选择的监听端口: $hy_listen_port"
    echo ""
    read -p "输入自签证书域名 (default: bing.com): " hy_server_name
    hy_server_name=${hy_server_name:-bing.com}
    echo "选择的自签证书域名: $hy_server_name"
    mkdir -p /root/self-cert/
    openssl ecparam -genkey -name prime256v1 -out /root/self-cert/private.key
    if [[ $? -ne 0 ]]; then
        echo "生成私钥失败。"
        return 1
    fi
    openssl req -new -x509 -days 36500 -key /root/self-cert/private.key -out /root/self-cert/cert.pem -subj "/CN=${hy_server_name}"
    if [[ $? -ne 0 ]]; then
        echo "生成自签证书失败。"
        return 1
    fi

    echo "自签证书生成完成"
    echo ""
     listen_ports+=("$hy_listen_port")
    hy_uuids+=("$hy_uuid")  # 假设这里使用密码作为唯一标识
    server_names+=("$hy_server_name")
    hy_passwords+=("$hy_password")
}
configure_vmess() {
    echo "开始配置vmess"
    echo ""   
    vmess_uuid=$(/root/sbox/sing-box generate uuid)
    if [[ $? -ne 0 ]]; then
        echo "生成UUID失败。"
        return 1
    fi
    read -p "请输入vmess端口，默认为15555: " vmess_port
    vmess_port=${vmess_port:-15555}
    echo ""
    read -p "ws路径 (默认随机生成): " ws_path
    ws_path=${ws_path:-$(/root/sbox/sing-box generate rand --hex 6)}
    if [[ $? -ne 0 ]]; then
        echo "生成随机路径失败。"
        return 1
    fi
    vmess_ports+=("$vmess_port")
    vmess_uuids+=("$vmess_uuid")
    ws_paths+=("$ws_path")
    pid=$(pgrep -f cloudflared)
    if [ -n "$pid" ]; then
        kill "$pid"
        echo "已终止正在运行的cloudflared进程: $pid"
    fi
    /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux > argo.log 2>&1 &
    sleep 2
    clear
    echo "等待cloudflare argo生成地址..."
    sleep 5
    argo=$(grep trycloudflare.com argo.log | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    
    if [[ -z "$argo" ]]; then
        echo "未能获取Cloudflare地址，请检查日志。"
        return 1
    fi
    echo "$argo" | base64 > /root/sbox/argo.txt.b64
    echo "生成的Cloudflare地址已保存。"
    rm -rf argo.log
}
#配置文件生成
generate_config() {
    jq -n \
      --arg listen_port "${listen_ports}" \
      --arg vmess_port "${vmess_ports}" \
      --arg uuid "${uuids}" \
      --arg ws_path "${ws_paths}" \
      --arg server_name "${server_names}" \
      --arg private_key "$private_key" \
      --arg short_id "${short_ids}" \
      --arg hy_listen_port "${hy_listen_ports}" \
      --arg hy_password "${hy_passwords}" \
      --arg server_ip "$server_ip" \
    '{
        "listen_ports": [$listen_port],
        "vmess_ports": $vmess_port,
        "vmess_uuids": $uuid,
        "ws_paths": $ws_path,
        "server_names": $server_name,
        "private_key": $private_key,
        "short_ids": $short_id,
        "hy_listen_ports": $hy_listen_port,
        "hy_passwords": $hy_password,
        "server_ip": $server_ip
    }' \
    '{
      "log": {
        "disabled": false,
        "level": "info",
        "timestamp": true
      },
      "inbounds": [
        {
          "type": "vless",
          "tag": "vless-in",
          "listen": "::",
          "listen_port": $listen_port,
          "users": [
            {
              "uuid": $uuid,
              "flow": "xtls-rprx-vision"
            }
          ],
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
        },
        ...
      ]
    }' > /root/sbox/sbconfig_server.json
}

# 显示界面
menu() {
    mkdir -p "/root/sbox/"
    download_singbox
    download_cloudflared
    echo ""
    echo "请选择选项:"
    echo ""
    echo "1. 安装sing-box"
    echo "2. 重新安装"
    echo "3. 修改配置"
    echo "4. 显示客户端配置"
    echo "5. 卸载"
    echo "6. 更新sing-box内核"
    echo "7. 手动重启cloudflared"
    echo "8. 手动重启sing-box"
    echo "0. 退出脚本"
    echo ""

    read -p "Enter your choice (0-8): " choice

    case $choice in
        1)
            echo "请选择要安装的协议（可以选择多个，用空格分隔）："
            echo "1. VLESS"
            echo "2. VMESS"
            echo "3. Hysteria2"
            read -p "Enter your choices (e.g., 1 2 3): " protocols

            for protocol in $protocols; do
                case $protocols in
                    1)
                        echo "正在安装 VLESS..."
                        configure_reality
                        ;;
                    2)
                        echo "正在安装 VMESS..."
                        configure_vmess
                        ;;
                    3)
                        echo "正在安装 Hysteria2..."
                        configure_hysteria2
                        ;;
                    *)
                        echo "无效的协议选择: $protocols"
                        ;;
                esac
            done
             server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)
# Debugging output before generating config
echo "监听端口: ${listen_ports[*]}"
echo "UUIDs: ${uuids[*]}"
echo "短ID: ${short_ids[*]}"
echo "服务器名称: ${server_names[*]}"
echo "hysteria2 端口: $hy_listen_ports"
echo "hysteria2 密码: $hy_passwords"
echo "vmess 端口: ${vmess_ports[*]}"
echo "ws路径: ${ws_paths[*]}"
       
        generate_config 
        systemctl daemon-reload
        systemctl enable sing-box
        systemctl start sing-box
        echo "服务已启动" 
        show_client_configuration
            ;;
        2)
            show_notice "Reinstalling..."
            systemctl stop sing-box
            systemctl disable sing-box > /dev/null 2>&1
            rm -rf /etc/systemd/system/sing-box.service /root/sbox/sbconfig_server.json /root/sbox/sing-box /root/sbox/cloudflared-linux /root/sbox/argo.txt.b64 /root/sbox/public.key.b64 /root/self-cert/private.key /root/self-cert/cert.pem /root/self-cert/
            ;;
        3)
            show_notice "开始修改reality端口和域名"
            current_listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
            read -p "请输入想要修改的端口号 (当前端口为 $current_listen_port): " listen_port
            listen_port=${listen_port:-$current_listen_port}
            current_server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
            read -p "请输入想要使用的h2域名 (当前域名为 $current_server_name): " server_name
            server_name=${server_name:-$current_server_name}
            echo ""
            show_notice "开始修改hysteria2端口"
            hy_current_listen_port=$(jq -r '.inbounds[1].listen_port' /root/sbox/sbconfig_server.json)
            read -p "请输入想要修改的端口 (当前端口为 $hy_current_listen_port): " hy_listen_port
            hy_listen_port=${hy_listen_port:-$hy_current_listen_port}
            jq --arg listen_port "$listen_port" --arg server_name "$server_name" --arg hy_listen_port "$hy_listen_port" \
                '.inbounds[1].listen_port = ($hy_listen_port | tonumber) | .inbounds[0].listen_port = ($listen_port | tonumber) | .inbounds[0].tls.server_name = $server_name | .inbounds[0].tls.reality.handshake.server = $server_name' \
                /root/sbox/sbconfig_server.json > /root/sb_modified.json 
            mv /root/sb_modified.json /root/sbox/sbconfig_server.json
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
                echo "配置检查成功. 启动sing-box服务..."
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
            start_singbox
            exit 0
            ;;   
        0)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效的选择. 退出."
            exit 1
            ;;
    esac
}
menu

