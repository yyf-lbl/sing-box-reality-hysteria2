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
  # 获取系统架构
  arch=$(uname -m)
  echo "Architecture: $arch"
  # 根据系统架构映射名称
  case ${arch} in
      x86_64)
          arch="amd64"  # 64位架构
          ;;
      aarch64)
          arch="arm64"  # ARM 64位架构
          ;;
      armv7l)
          arch="armv7"  # ARM 32位架构
          ;;
  esac
  # 从 GitHub API 获取最新版本（包括预发行版本）
  # beta版本
  latest_version_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | grep -Po '"tag_name": "\K.*?(?=")' | sort -V | tail -n 1)
  latest_version=${latest_version_tag#v}  # 去掉版本号前的 'v'
  echo "Latest version: $latest_version"
  # 准备软件包名称
  package_name="sing-box-${latest_version}-linux-${arch}"
  # 准备下载 URL
  url="https://github.com/SagerNet/sing-box/releases/download/${latest_version_tag}/${package_name}.tar.gz"
  # 从 GitHub 下载最新发布的包 (.tar.gz)
  curl -sLo "/root/${package_name}.tar.gz" "$url"

  # 解压缩包并将二进制文件移动到 /root
  tar -xzf "/root/${package_name}.tar.gz" -C /root
  mv "/root/${package_name}/sing-box" /root/sbox

  # 清理下载的包
  rm -r "/root/${package_name}.tar.gz" "/root/${package_name}"
  # 设置权限
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
  echo ""
  server_link="vless://$uuid@$server_ip:$current_listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$current_server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#SING-BOX-Reality"
  echo ""
  echo ""
  echo "$server_link"
  echo ""
  echo ""
  # Print the server details
  show_notice "Reality 客户端通用参数" 
  echo ""
  echo ""
  echo "服务器ip: $server_ip"
  echo "监听端口: $current_listen_port"
  echo "UUID: $uuid"
  echo "域名SNI: $current_server_name"
  echo "Public Key: $public_key"
  echo "Short ID: $short_id"
  echo ""
  echo ""
  # Get current listen port
  hy_current_listen_port=$(jq -r '.inbounds[1].listen_port' /root/sbox/sbconfig_server.json)
  # Get current server name
  hy_current_server_name=$(openssl x509 -in /root/self-cert/cert.pem -noout -subject -nameopt RFC2253 | awk -F'=' '{print $NF}')
  # Get the password
  hy_password=$(jq -r '.inbounds[1].users[0].password' /root/sbox/sbconfig_server.json)
  # Generate the link
  
  hy2_server_link="hysteria2://$hy_password@$server_ip:$hy_current_listen_port?insecure=1&sni=$hy_current_server_name"

  show_notice "Hysteria2 客户端通用链接" 
  echo ""
  echo "官方 hysteria2通用链接格式"
  echo ""
  echo "$hy2_server_link"
  echo ""
  echo ""   
  # Print the server details
  show_notice "Hysteria2 客户端通用参数" 
  echo ""
  echo ""  
  echo "服务器ip: $server_ip"
  echo "端口号: $hy_current_listen_port"
  echo "password: $hy_password"
  echo "域名SNI: $hy_current_server_name"
  echo "跳过证书验证: True"
  echo ""
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
  vmess_uuid=$(jq -r '.inbounds[2].users[0].uuid' /root/sbox/sbconfig_server.json)
  ws_path=$(jq -r '.inbounds[2].transport.path' /root/sbox/sbconfig_server.json)
  show_notice "vmess ws 通用链接参数" 
  echo ""
  echo ""
  echo "以下为vmess链接，替换speed.cloudflare.com为自己的优选ip可获得极致体验"
  echo ""
  echo ""
  echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"sing-box-vmess-tls","tls":"tls","type":"none","v":"2"}' | base64 -w 0)
  echo ""
  echo ""
  echo -e "端口 443 可改为 2053 2083 2087 2096 8443"
  echo ""
  echo ""
  echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"sing-box-vmess","tls":"","type":"none","v":"2"}' | base64 -w 0)
  echo ""
  echo ""
  echo -e "端口 80 可改为 8080 8880 2052 2082 2086 2095" 
  echo ""
  echo ""
}
# 安装sing-box
install_singbox() {
    # 创建 sbox 目录
    mkdir -p "/root/sbox/"
    # 下载 sing-box 和 cloudflared
    download_singbox
    download_cloudflared

    # 用户选择安装的协议
    echo "请选择要安装的协议（可以多个，以空格分隔）："
    echo "1) VLESS"
    echo "2) VMess"
    echo "3) Hysteria2"
    read -p "输入选项（例如：1 2 3）: " selected_options
    # 配置选项
    for option in $selected_options; do
        case $option in
            1)
                install_vless
                ;;
            2)
                install_vmess
                ;;
            3)
               install_hysteria2
                ;;
            *)
                echo "无效的选项: $option"
                ;;
        esac
    done
    # 检索服务器 IP 地址
    server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)
      generate_sbconfig
      check_and_start_service
    # 检查配置文件和可执行文件是否存在
    if [ ! -f "/root/sbox/sbconfig_server.json" ]; then
        echo "sbconfig_server.json 文件不存在，请检查配置。"
        exit 1
    fi

    if [ ! -f "/root/sbox/sing-box" ]; then
        echo "sing-box 文件不存在，请检查下载是否成功。"
        exit 1
    fi
    echo "所有配置已完成，准备开始服务..."
    # 你可以在这里添加启动服务的命令
}
# 配置文件生成
generate_sbconfig() {
    # 确保在调用此函数之前已设置所需的变量
    # 例如: $uuid, $server_ip, $current_listen_port, $current_server_name, $public_key, $short_id, $hy_current_listen_port, $hy_password, $ws_path, $vmess_uuid, $argo

    cat << EOF > /root/sbox/sbconfig_server.json
{
    "dns": {
        "servers": [
            {
                "tag": "remote",
                "address": "https://1.1.1.1/dns-query",
                "detour": "select"
            },
            {
                "tag": "local",
                "address": "https://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "address": "rcode://success",
                "tag": "block"
            }
        ],
        "rules": [
            {
                "outbound": [
                    "any"
                ],
                "server": "local"
            },
            {
                "disable_cache": true,
                "geosite": [
                    "category-ads-all"
                ],
                "server": "block"
            },
            {
                "clash_mode": "global",
                "server": "remote"
            },
            {
                "clash_mode": "direct",
                "server": "local"
            },
            {
                "geosite": "cn",
                "server": "local"
            }
        ],
        "strategy": "prefer_ipv4"
    },
    "inbounds": [
        {
            "type": "tun",
            "inet4_address": "172.19.0.1/30",
            "inet6_address": "2001:0470:f9da:fdfa::1/64",
            "sniff": true,
            "sniff_override_destination": true,
            "domain_strategy": "prefer_ipv4",
            "stack": "mixed",
            "strict_route": true,
            "mtu": 9000,
            "endpoint_independent_nat": true,
            "auto_route": true
        },
        {
            "type": "socks",
            "tag": "socks-in",
            "listen": "127.0.0.1",
            "sniff": true,
            "sniff_override_destination": true,
            "domain_strategy": "prefer_ipv4",
            "listen_port": 2333,
            "users": []
        },
        {
            "type": "mixed",
            "tag": "mixed-in",
            "sniff": true,
            "sniff_override_destination": true,
            "domain_strategy": "prefer_ipv4",
            "listen": "127.0.0.1",
            "listen_port": 2334,
            "users": []
        }
    ],
    "experimental": {
        "clash_api": {
            "external_controller": "127.0.0.1:9090",
            "secret": "",
            "store_selected": true
        }
    },
    "log": {
        "disabled": false,
        "level": "info",
        "timestamp": true
    },
    "outbounds": [
        {
            "tag": "select",
            "type": "selector",
            "default": "urltest",
            "outbounds": [
                "urltest",
                "sing-box-reality",
                "sing-box-hysteria2",
                "sing-box-vmess"
            ]
        },
        {
            "type": "vless",
            "tag": "sing-box-reality",
            "uuid": "$uuid",
            "flow": "xtls-rprx-vision",
            "packet_encoding": "xudp",
            "server": "$server_ip",
            "server_port": $current_listen_port,
            "tls": {
                "enabled": true,
                "server_name": "$current_server_name",
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                },
                "reality": {
                    "enabled": true,
                    "public_key": "$public_key",
                    "short_id": "$short_id"
                }
            }
        },
        {
            "type": "hysteria2",
            "server": "$server_ip",
            "server_port": $hy_current_listen_port,
            "tag": "sing-box-hysteria2",
            "up_mbps": 100,
            "down_mbps": 100,
            "password": "$hy_password",
            "tls": {
                "enabled": true,
                "server_name": "$hy_current_server_name",
                "insecure": true,
                "alpn": [
                    "h3"
                ]
            }
        },
        {
            "server": "speed.cloudflare.com",
            "server_port": 443,
            "tag": "sing-box-vmess",
            "tls": {
                "enabled": true,
                "server_name": "$argo",
                "insecure": true,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$vmess_uuid"
        },
        {
            "tag": "direct",
            "type": "direct"
        },
        {
            "tag": "block",
            "type": "block"
        },
        {
            "tag": "dns-out",
            "type": "dns"
        },
        {
            "tag": "urltest",
            "type": "urltest",
            "outbounds": [
                "sing-box-reality",
                "sing-box-hysteria2",
                "sing-box-vmess"
            ]
        }
    ],
    "route": {
        "auto_detect_interface": true,
        "rules": [
            {
                "geosite": "category-ads-all",
                "outbound": "block"
            },
            {
                "outbound": "dns-out",
                "protocol": "dns"
            },
            {
                "clash_mode": "direct",
                "outbound": "direct"
            },
            {
                "clash_mode": "global",
                "outbound": "select"
            },
            {
                "geoip": [
                    "cn",
                    "private"
                ],
                "outbound": "direct"
            },
            {
                "geosite": "geolocation-!cn",
                "outbound": "select"
            },
            {
                "geosite": "cn",
                "outbound": "direct"
            }
        ],
        "geoip": {
            "download_detour": "select"
        },
        "geosite": {
            "download_detour": "select"
        }
    }
}
EOF
}

 # 检查配置并启动服务
check_and_start_service() { 
# 打印变量
echo "UUID: $uuid"
echo "Server Name: $server_name"
echo "Private Key: $private_key"
echo "Short ID: $short_id"
echo "HY Listen Port: $hy_listen_port"
echo "HY Password: $hy_password"
echo "VMess Port: $vmess_port"
echo "VMess UUID: $vmess_uuid"
echo "WS Path: $ws_path"
 # # 使用jq创建reality.json
jq -n --arg listen_port "$listen_port" --arg vmess_port "$vmess_port" --arg vmess_uuid "$vmess_uuid" \
--arg ws_path "$ws_path" --arg server_name "$server_name" --arg private_key "$private_key" \
--arg short_id "$short_id" --arg uuid "$uuid" --arg hy_listen_port "$hy_listen_port" \
--arg hy_password "$hy_password" '{
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
    },
    {
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
    },
    {
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
    }
  ],
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
# Check configuration and start the service
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
    echo "sing-box-reality-hysteria2已经安装"
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


