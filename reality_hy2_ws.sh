#!/bin/bash
install_vless(){
 # reality
echo "开始配置Reality"
echo ""
# 生成密钥对
echo "自动生成基本参数"
echo ""
key_pair=$(/root/sbox/sing-box generate reality-keypair)
echo "Key pair生成完成"
echo ""

# 提取私钥和公钥
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')

# 使用base64编码将公钥保存在文件中
echo "$public_key" | base64 > /root/sbox/public.key.b64

# 生成必要的值
uuid=$(/root/sbox/sing-box generate uuid)
short_id=$(/root/sbox/sing-box generate rand --hex 8)
echo "uuid和短id 生成完成"
echo ""
# 请求监听端口
read -p "请输入Reality端口 (default: 443): " listen_port
listen_port=${listen_port:-443}
echo ""
# 询问服务器名称（sni）
read -p "请输入想要使用的域名 (default: itunes.apple.com): " server_name
server_name=${server_name:-itunes.apple.com}
echo ""
}
install_vmess(){
  echo "开始配置vmess"
echo ""
# 生成vmess必要参数
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

}
install_hysteria(){
 echo "开始配置hysteria2"
echo ""
# 生成 hysteria 必要参数
hy_password=$(/root/sbox/sing-box generate rand --hex 8)

# 请求监听端口
read -p "请输入hysteria2监听端口 (default: 8443): " hy_listen_port
hy_listen_port=${hy_listen_port:-8443}
echo ""

# 请求自签名证书域
read -p "输入自签证书域名 (default: bing.com): " hy_server_name
hy_server_name=${hy_server_name:-bing.com}
mkdir -p /root/self-cert/ && openssl ecparam -genkey -name prime256v1 -out /root/self-cert/private.key && openssl req -new -x509 -days 36500 -key /root/self-cert/private.key -out /root/self-cert/cert.pem -subj "/CN=${hy_server_name}"
echo ""
echo "自签证书生成完成"
echo ""
}
# 基础安装依赖
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
# 生成 cloudflared argo隧道配置文件
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
  # Fetch the latest (including pre-releases) release version number from GitHub API
  # 正式版
  #latest_version_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | grep -Po '"tag_name": "\K.*?(?=")' | head -n 1)
  #beta版本
  latest_version_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | grep -Po '"tag_name": "\K.*?(?=")' | sort -V | tail -n 1)
  latest_version=${latest_version_tag#v}  # Remove 'v' prefix from version number
  echo "Latest version: $latest_version"
  # Detect server architecture
  # Prepare package names
  package_name="sing-box-${latest_version}-linux-${arch}"
  # Prepare download URL
  url="https://github.com/SagerNet/sing-box/releases/download/${latest_version_tag}/${package_name}.tar.gz"
  # Download the latest release package (.tar.gz) from GitHub
  curl -sLo "/root/${package_name}.tar.gz" "$url"

  # Extract the package and move the binary to /root
  tar -xzf "/root/${package_name}.tar.gz" -C /root
  mv "/root/${package_name}/sing-box" /root/sbox

  # 清理解压文件
  rm -r "/root/${package_name}.tar.gz" "/root/${package_name}"

  # 设置权限
  chown root:root /root/sbox/sing-box
  chmod +x /root/sbox/sing-box
}
# 下载 singbox and cloudflared
download_cloudflared(){
  arch=$(uname -m)
  # 选择架构名称
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

  # 安装cloudflared linux
  cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
  curl -sLo "/root/sbox/cloudflared-linux" "$cf_url"
  chmod +x /root/sbox/cloudflared-linux
  echo ""
}
install_singbox() {
    echo "欢迎安装 Sing-box 服务，请继续..."
       mkdir -p "/root/sbox/"
    # 安装sing-box
    download_singbox
    download_cloudflared
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
    # 获取本机ip地址
server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)

    # 根据用户选择动态生成对应协议的配置文件
  config_inbounds=()

  if [[ "$protocol_choice" == "1" || "$protocol_choice" == "4" ]]; then
    vless_config=$(jq -n --arg listen_port "$listen_port" --arg server_name "$server_name" --arg private_key "$private_key" --arg short_id "$short_id" --arg uuid "$uuid" '{
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
    config_inbounds+=("$vless_config")
  fi

  if [[ "$protocol_choice" == "2" || "$protocol_choice" == "4" ]]; then
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
    config_inbounds+=("$vmess_config")
  fi

  if [[ "$protocol_choice" == "3" || "$protocol_choice" == "4" ]]; then
    hysteria_config=$(jq -n --arg hy_listen_port "$hy_listen_port" --arg hy_password "$hy_password" --arg server_ip "$server_ip" '{
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
    config_inbounds+=("$hysteria_config")
  fi

  # 将所有生成的配置合并到一个配置文件中
  jq -n --argjson inbounds "$(printf '%s\n' "${config_inbounds[@]}" | jq -s '.')" '{
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

  echo "配置文件生成完成: /root/sbox/sbconfig_server.json"
}
uninstall_singbox() {
            echo "Uninstalling..."
          # 停止并禁用sing-box服务
          systemctl stop sing-box
          systemctl disable sing-box > /dev/null 2>&1
	  
          # 删除文件    
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
install_base
# 创建sing-box.service
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
    echo "Configuration checked successfully. Starting sing-box service..."
    systemctl daemon-reload
    systemctl enable sing-box > /dev/null 2>&1
    systemctl start sing-box
    systemctl restart sing-box

    show_client_configuration


else
    echo "Error in configuration. Aborting"
fi
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
        2)  # 修改配置
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
        3)  # 显示客户端配置
            show_client_configuration
            exit 0
            ;;
        4)  # 卸载
            uninstall_singbox
            exit 0
            ;;
        5)  # 更新 sing-box 内核
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
        6)  # 手动重启 cloudflared
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
