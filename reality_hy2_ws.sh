#!/bin/bash
# 函数：安装VLESS
install_vless() {
    echo "开始配置Reality..."
    # 自动生成密钥对
    key_pair=$(/root/sbox/sing-box generate reality-keypair)
    if [ $? -ne 0 ]; then
        echo "生成密钥对失败"
        return 1
    fi
    echo "密钥对生成完成"
    private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
    public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
    echo "$public_key" | base64 > /root/sbox/public.key.b64
    # 生成UUID和短ID
    uuid=$(/root/sbox/sing-box generate uuid)
    short_id=$(/root/sbox/sing-box generate rand --hex 8)
    # 获取用户输入
    read -p "请输入Reality端口 (default: 443): " listen_port
    listen_port=${listen_port:-443} 
    read -p "请输入想要使用的域名 (default: itunes.apple.com): " server_name
    server_name=${server_name:-itunes.apple.com}
}
# 函数：安装VMess
install_vmess() {
    echo "开始配置VMess..."
    # 生成UUID
    vmess_uuid=$(/root/sbox/sing-box generate uuid)
    if [ $? -ne 0 ]; then
        echo "生成UUID失败"
        return 1
    fi
    # 获取用户输入
    read -p "请输入VMess端口 (default: 15555): " vmess_port
    vmess_port=${vmess_port:-15555}
    read -p "WS路径 (default: 随机生成): " ws_path
    ws_path=${ws_path:-$(/root/sbox/sing-box generate rand --hex 6)}
    # 终止Cloudflared进程
    pgrep -f cloudflared | xargs -r kill
    # 启动Cloudflared隧道
    /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux > /root/sbox/argo.log 2>&1 &
    sleep 5

    argo=$(awk '/trycloudflare.com/ {print $2}' /root/sbox/argo.log | head -n 1 | awk -F// '{print $2}')
    echo "$argo" | base64 > /root/sbox/argo.txt.b64
    rm -f /root/sbox/argo.log
}
# 函数：安装Hysteria2
install_hysteria2() {
    echo "开始配置Hysteria2..."
    
    hy_password=$(/root/sbox/sing-box generate rand --hex 8)

    read -p "请输入Hysteria2监听端口 (default: 8443): " hy_listen_port
    hy_listen_port=${hy_listen_port:-8443}

    read -p "输入自签证书域名 (default: bing.com): " hy_server_name
    hy_server_name=${hy_server_name:-bing.com}

    mkdir -p /root/self-cert/
    openssl ecparam -genkey -name prime256v1 -out /root/self-cert/private.key
    openssl req -new -x509 -days 36500 -key /root/self-cert/private.key -out /root/self-cert/cert.pem -subj "/CN=${hy_server_name}"
    echo "自签证书生成完成"
}
  # 检查是否安装了jq，如果没有安装，则安装它
install_base() {
    if ! command -v jq &> /dev/null; then
        echo "jq未安装，正在安装..."
        if command -v apt &> /dev/null; then
            apt update && apt install -y jq
        elif command -v yum &> /dev/null; then
            yum install -y epel-release jq
        elif command -v dnf &> /dev/null; then
            dnf install -y jq
        else
            echo "无法安装jq，请手动安装并重新运行脚本。"
            exit 1
        fi
    fi
}
# 重新生成 Cloudflared Argo 隧道
regenarte_cloudflared_argo() {
  # 获取 cloudflared 进程的 PID
  pid=$(pgrep -f cloudflared)
  
  if [ -n "$pid" ]; then
    # 如果进程存在，则终止它
    kill "$pid"
  fi
  # 从配置文件中获取 VMess 端口
  vmess_port=$(jq -r '.inbounds[2].listen_port' /root/sbox/sbconfig_server.json)
  # 生成 Argo 隧道，并将输出重定向到 argo.log
  /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux > argo.log 2>&1 &
  # 等待 2 秒，以确保隧道启动
  sleep 2
  clear
  echo 等待 Cloudflare Argo 生成地址
  sleep 5
  # 从日志文件中提取 Argo 地址
  argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
  # 将 Argo 地址编码为 Base64 并保存到文件
  echo "$argo" | base64 > /root/sbox/argo.txt.b64
  # 删除临时日志文件
  rm -rf argo.log
}
# 下载 Sing-Box 和 Cloudflared
download_singbox() {
  arch=$(uname -m)
  echo "Architecture: $arch"
  case ${arch} in
      x86_64) arch="amd64";;
      aarch64) arch="arm64";;
      armv7l) arch="armv7";;
  esac

  latest_version_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | grep -Po '"tag_name": "\K.*?(?=")' | sort -V | tail -n 1)
  latest_version=${latest_version_tag#v}
  echo "Latest version: $latest_version"

  package_name="sing-box-${latest_version}-linux-${arch}"
  url="https://github.com/SagerNet/sing-box/releases/download/${latest_version_tag}/${package_name}.tar.gz"
  
  mkdir -p /root/sbox
  curl -sLo "/root/${package_name}.tar.gz" "$url"
  tar -xzf "/root/${package_name}.tar.gz" -C /root
  ls /root/${package_name}  # 查看解压内容
  mv "/root/${package_name}/sing-box" /root/sbox
  if [ -f /root/sbox/sing-box ]; then echo "File moved successfully."; fi
  
  rm -r "/root/${package_name}.tar.gz" "/root/${package_name}"
  chown root:root /root/sbox/sing-box
  chmod +x /root/sbox/sing-box
}

# 下载 Cloudflared
download_cloudflared() {
  # 获取系统架构
  arch=$(uname -m)
  # 根据系统架构映射名称
  case ${arch} in
      x86_64)
          cf_arch="amd64"  # 64位架构
          ;;
      aarch64)
          cf_arch="arm64"  # ARM 64位架构
          ;;
      armv7l)
          cf_arch="arm"    # ARM 32位架构
          ;;
  esac
  # 安装 Cloudflared
  cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
  curl -sLo "/root/sbox/cloudflared-linux" "$cf_url"  # 下载 Cloudflared
  chmod +x /root/sbox/cloudflared-linux  # 赋予执行权限
  echo ""
}
# 显示客户端配置
show_client_configuration() {
  # 检查是否安装了 VLESS
  if jq -e '.inbounds[0].protocol == "vless"' /root/sbox/sbconfig_server.json > /dev/null; then
    # Get current listen port
    current_listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
    # Get current server name
    current_server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
    # Get the UUID
    uuid=$(jq -r '.inbounds[0].users[0].uuid' /root/sbox/sbconfig_server.json)
    # Get the public key from the file, decoding it from base64
    public_key=$(base64 --decode /root/sbox/public.key.b64)
    # Get the short ID
    short_id=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /root/sbox/sbconfig_server.json)
    # Retrieve the server IP address
    server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)

    echo ""
    echo ""
    show_notice "Reality 客户端通用链接"
    echo ""
    server_link="vless://$uuid@$server_ip:$current_listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$current_server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#SING-BOX-Reality"
    echo "$server_link"
    echo ""

    # Print the server details
    show_notice "Reality 客户端通用参数"
    echo ""
    echo "服务器ip: $server_ip"
    echo "监听端口: $current_listen_port"
    echo "UUID: $uuid"
    echo "域名SNI: $current_server_name"
    echo "Public Key: $public_key"
    echo "Short ID: $short_id"
    echo ""
  fi

  # 检查是否安装了 Hysteria2
  if jq -e '.inbounds[1].protocol == "hysteria"' /root/sbox/sbconfig_server.json > /dev/null; then
    # Get current listen port
    hy_current_listen_port=$(jq -r '.inbounds[1].listen_port' /root/sbox/sbconfig_server.json)
    # Get current server name
    hy_current_server_name=$(openssl x509 -in /root/self-cert/cert.pem -noout -subject -nameopt RFC2253 | awk -F'=' '{print $NF}')
    # Get the password
    hy_password=$(jq -r '.inbounds[1].users[0].password' /root/sbox/sbconfig_server.json)

    # Generate the link
    hy2_server_link="hysteria2://$hy_password@$server_ip:$hy_current_listen_port?insecure=1&sni=$hy_current_server_name"
    show_notice "Hysteria2 客户端通用链接"
    echo "$hy2_server_link"

    # Print the server details
    show_notice "Hysteria2 客户端通用参数"
    echo "服务器ip: $server_ip"
    echo "端口号: $hy_current_listen_port"
    echo "password: $hy_password"
    echo "域名SNI: $hy_current_server_name"
    echo "跳过证书验证: True"
    echo ""

    # Print YAML configuration
    show_notice "Hysteria2 客户端yaml文件"
    cat << EOF
server: $server_ip:$hy_current_listen_port
auth: $hy_password
tls:
  sni: $hy_current_server_name
  insecure: true
fastOpen: true
socks5:
  listen: 127.0.0.1:5080
EOF
  fi

  # 检查是否安装了 VMess
  if jq -e '.inbounds[2].protocol == "vmess"' /root/sbox/sbconfig_server.json > /dev/null; then
    argo=$(base64 --decode /root/sbox/argo.txt.b64)
    vmess_uuid=$(jq -r '.inbounds[2].users[0].uuid' /root/sbox/sbconfig_server.json)
    ws_path=$(jq -r '.inbounds[2].transport.path' /root/sbox/sbconfig_server.json)

    show_notice "vmess ws 通用链接参数"
    echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"sing-box-vmess-tls","tls":"tls","type":"none","v":"2"}' | base64 -w 0)
    echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"sing-box-vmess","tls":"","type":"none","v":"2"}' | base64 -w 0)
  fi
}

# 安装sing-box
install_singbox() {
    echo "安装 Sing-box 和协议配置开始..."

    # 安装所需协议
    echo "选择要安装的协议:"
    echo "1. VLESS (Reality)"
    echo "2. VMess"
    echo "3. Hysteria2"
    echo "4. 全部安装"
    read -p "输入选择的协议编号 (1, 2, 3 或 4): " protocol_choice

    # 根据用户选择调用相应的安装函数
    case $protocol_choice in
        1)
            install_vless
            ;;
        2)
            install_vmess
            ;;
        3)
            install_hysteria2
            ;;
        4)
            install_vless
            install_vmess
            install_hysteria2
            ;;
        *)
            echo "无效的选择。"
            return 1
            ;;
    esac
    mkdir -p "/root/sbox/"
    # 安装sing-box
    download_singbox
    # 调用生成配置文件的函数
    generate_config_file
    # 检查配置文件并启动服务
    check_and_start_service
}
# 配置文件生成
generate_config_file() {
    echo "生成配置文件..."

    # 输出调试信息，检查变量是否有值
    echo "调试信息："
    echo "VLESS 监听端口: $listen_port"
    echo "VMess 监听端口: $vmess_port"
    echo "VMess UUID: $vmess_uuid"
    echo "WebSocket 路径: $ws_path"
    echo "服务器名称: $server_name"
    echo "Reality 私钥: $private_key"
    echo "短 ID: $short_id"
    echo "VLESS UUID: $uuid"
    echo "Hysteria2 监听端口: $hy_listen_port"
    echo "Hysteria2 密码: $hy_password"

    # 检查必要的变量是否为空
    if [ -z "$listen_port" ] || [ -z "$uuid" ]; then
        echo "错误: 必要的变量为空。请检查配置。"
        return 1
    fi

    # 初始化inbounds为空数组
    inbound_config="[]"

    # 如果 VLESS 安装了，生成 VLESS 配置
    if [ -n "$listen_port" ] && [ -n "$uuid" ]; then
        vless_config=$(jq -n --arg listen_port "$listen_port" --arg uuid "$uuid" \
            --arg server_name "$server_name" --arg private_key "$private_key" \
            --arg short_id "$short_id" '{
            "type": "vless",
            "tag": "vless-in",
            "listen": "::",
            "listen_port": ($listen_port | tonumber),
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
        }')
        inbound_config=$(echo $inbound_config | jq --argjson vless "$vless_config" '. += [$vless]')
    fi

    # 如果 VMess 安装了，生成 VMess 配置
    if [ -n "$vmess_port" ] && [ -n "$vmess_uuid" ]; then
        vmess_config=$(jq -n --arg vmess_port "$vmess_port" --arg vmess_uuid "$vmess_uuid" --arg ws_path "$ws_path" '{
            "type": "vmess",
            "tag": "vmess-in",
            "listen": "::",
            "listen_port": ($vmess_port | tonumber),
            "users": [
                {
                    "uuid": $vmess_uuid,
                    "alterId": 0
                }
            ],
            "transport": {
                "type": "ws",
                "path": $ws_path
            }
        }')
        inbound_config=$(echo $inbound_config | jq --argjson vmess "$vmess_config" '. += [$vmess]')
    fi

    # 如果 Hysteria2 安装了，生成 Hysteria2 配置
    if [ -n "$hy_listen_port" ] && [ -n "$hy_password" ]; then
        hysteria_config=$(jq -n --arg hy_listen_port "$hy_listen_port" --arg hy_password "$hy_password" '{
            "type": "hysteria2",
            "tag": "hy2-in",
            "listen": "::",
            "listen_port": ($hy_listen_port | tonumber),
            "users": [
                {
                    "password": $hy_password
                }
            ],
            "tls": {
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/root/self-cert/cert.pem",
                "key_path": "/root/self-cert/private.key"
            }
        }')
        inbound_config=$(echo $inbound_config | jq --argjson hysteria "$hysteria_config" '. += [$hysteria]')
    fi

    # 最终生成完整的配置文件
    jq -n --argjson inbounds "$inbound_config" '{
      "log": {
        "disabled": false,
        "level": "info",
        "timestamp": true
      },
      "inbounds": $inbounds,
      "outbounds": [
        {
          "type": "direct",
          "tag": "direct"
        },
        {
          "type": "block",
          "tag": "block"
        }
      ]
    }' > /root/sbox/sbconfig_server.json

    # 输出生成的 JSON 文件内容，供调试用
    cat /root/sbox/sbconfig_server.json
}
# 检查配置并启动服务
check_and_start_service() {
    echo "检查配置文件并启动 sing-box 服务..."

    # 检查配置文件是否有效
    if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
        echo "配置文件有效。启动 sing-box 服务..."
        systemctl daemon-reload
        systemctl enable sing-box > /dev/null 2>&1
        systemctl start sing-box
        systemctl restart sing-box
        show_client_configuration
    else
        echo "配置文件无效，终止启动。"
    fi
}
# 卸载sing-box
uninstall_singbox() {
    echo "Uninstalling..."    
    # 停止并禁用 sing-box 服务
    systemctl stop sing-box
    systemctl disable sing-box > /dev/null 2>&1
   # 删除相关文件
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
    echo "DONE!"
}
menu() {
    # 检查必要文件是否存在
clear
    echo ""
    echo "请选择选项:"
    echo ""
    echo "1. 安装sing-box"
    echo "2. 卸载sing-box"
    echo "3. 修改配置"
    echo "4. 显示客户端配置"
    echo "5. 卸载"
    echo "6. 更新sing-box内核"
    echo "7. 手动重启cloudflared"
    echo ""

    read -p "Enter your choice (1-7): " choice
    case $choice in
        1)  # 安装sing-box
            install_base
            install_singbox
            check_and_start_service
            ;;
        2)  # 卸载sing-box
            uninstall_singbox
            ;;
        3)  # 修改配置
            show_notice "开始修改reality端口和域名"
            # 获取当前监听端口
            current_listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
            read -p "请输入想要修改的端口号 (当前端口为 $current_listen_port): " listen_port
            listen_port=${listen_port:-$current_listen_port}
            # 获取当前服务器名称
            current_server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
            read -p "请输入想要使用的h2域名 (当前域名为 $current_server_name): " server_name
            server_name=${server_name:-$current_server_name}
            # 修改 hysteria2 配置
            show_notice "开始修改hysteria2端口"
            hy_current_listen_port=$(jq -r '.inbounds[1].listen_port' /root/sbox/sbconfig_server.json)
            read -p "请属于想要修改的端口 (当前端口为 $hy_current_listen_port): " hy_listen_port
            hy_listen_port=${hy_listen_port:-$hy_current_listen_port}
            # 使用 jq 修改配置文件
            jq --arg listen_port "$listen_port" --arg server_name "$server_name" --arg hy_listen_port "$hy_listen_port" \
               '.inbounds[1].listen_port = ($hy_listen_port | tonumber) | .inbounds[0].listen_port = ($listen_port | tonumber) | .inbounds[0].tls.server_name = $server_name | .inbounds[0].tls.reality.handshake.server = $server_name' \
               /root/sbox/sbconfig_server.json > /root/sb_modified.json
            mv /root/sb_modified.json /root/sbox/sbconfig_server.json
            # 重启 sing-box 服务
            systemctl restart sing-box
            show_client_configuration
            exit 0
            ;;
        4)  # 显示客户端配置
            show_client_configuration
            exit 0
            ;;
        5)  # 卸载
            uninstall_singbox
            exit 0
            ;;
        6)  # 更新 sing-box 内核
            show_notice "Update Sing-box..."
            download_singbox
            if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
                echo "Configuration checked successfully. Starting sing-box service..."
                systemctl daemon-reload
                systemctl enable sing-box > /dev/null 2>&1
                systemctl start sing-box
                systemctl restart sing-box
            fi
            echo ""
            exit 1
            ;;
        7)  # 手动重启 cloudflared
            regenarte_cloudflared_argo
            echo "重新启动完成，查看新的 vmess 客户端信息"
            show_client_configuration
            exit 1
            ;;
        *)  # 处理无效选择
            echo "无效选择。退出。"
            exit 1
            ;;
    esac
}
menu


