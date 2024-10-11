install_singbox() {

    echo "开始配置 Reality"
    echo ""

    # 自动生成基本参数
    key_pair=$(/root/sbox/sing-box generate reality-keypair)
    if [ $? -ne 0 ]; then
        echo "生成 Reality 密钥对失败。"
        exit 1
    fi

    # 提取私钥和公钥
    private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
    public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')

    # 将公钥以 base64 编码保存到文件
    echo "$public_key" | base64 > /root/sbox/public.key.b64

    # 生成必要的值
    uuid=$(/root/sbox/sing-box generate uuid)
    short_id=$(/root/sbox/sing-box generate rand --hex 8)
    echo "UUID 和短 ID 生成完成"
    echo ""

    # 获取用户输入监听端口
    read -p "请输入 Reality 端口 (default: 443): " listen_port
    listen_port=${listen_port:-443}
    echo ""

    # 获取服务器名称 (SNI)
    read -p "请输入想要使用的域名 (default: itunes.apple.com): " server_name
    server_name=${server_name:-itunes.apple.com}
    echo ""

    # 开始配置 Hysteria2
    echo "开始配置 Hysteria2"
    echo ""

    # 生成 Hysteria 需要的值
    hy_password=$(/root/sbox/sing-box generate rand --hex 8)

    # 获取 Hysteria 监听端口
    read -p "请输入 Hysteria2 监听端口 (default: 8443): " hy_listen_port
    hy_listen_port=${hy_listen_port:-8443}
    echo ""

    # 获取自签名证书的域名
    read -p "输入自签证书域名 (default: bing.com): " hy_server_name
    hy_server_name=${hy_server_name:-bing.com}

    # 生成自签名证书
    mkdir -p /root/self-cert/
    openssl ecparam -genkey -name prime256v1 -out /root/self-cert/private.key
    openssl req -new -x509 -days 36500 -key /root/self-cert/private.key -out /root/self-cert/cert.pem -subj "/CN=${hy_server_name}"
    echo ""
    echo "自签证书生成完成"
    echo ""

    # 开始配置 VMess
    echo "开始配置 VMess"
    echo ""

    # 生成 VMess 需要的值
    vmess_uuid=$(/root/sbox/sing-box generate uuid)
    read -p "请输入 VMess 端口，默认为 15555: " vmess_port
    vmess_port=${vmess_port:-15555}
    echo ""

    read -p "ws 路径 (默认随机生成): " ws_path
    ws_path=${ws_path:-$(/root/sbox/sing-box generate rand --hex 6)}

    # 检查并终止 cloudflared 进程
    pid=$(pgrep -f cloudflared)
    if [ -n "$pid" ]; then
        # 终止进程
        kill "$pid"
    fi

    # 生成 Argo 地址
    /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux > argo.log 2>&1 &
    sleep 2
    clear
    echo "等待 Cloudflare Argo 生成地址..."
    sleep 5

    # 连接到域名
    argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    echo "$argo" | base64 > /root/sbox/argo.txt.b64
    rm -rf argo.log

    # 获取服务器 IP 地址
    server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)

    # 使用 jq 创建 reality.json
    jq -n --arg listen_port "$listen_port" \
          --arg vmess_port "$vmess_port" \
          --arg vmess_uuid "$vmess_uuid" \
          --arg ws_path "$ws_path" \
          --arg server_name "$server_name" \
          --arg private_key "$private_key" \
          --arg short_id "$short_id" \
          --arg uuid "$uuid" \
          --arg hy_listen_port "$hy_listen_port" \
          --arg hy_password "$hy_password" \
          --arg server_ip "$server_ip" '{
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

    echo "配置文件已生成：/root/sbox/sbconfig_server.json"
}
