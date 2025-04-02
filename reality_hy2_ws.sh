#!/bin/bash  

add_aliases() {
    ALIAS_CMD="alias a='bash <(curl -fsSL https://github.com/yyf-lbl/sing-box-reality-hysteria2/raw/main/reality_hy2_ws.sh)'"
    ALIAS_CMD2="alias 5='bash <(curl -fsSL https://github.com/yyf-lbl/sing-box-reality-hysteria2/raw/main/reality_hy2_ws.sh)'"
    MARKER="# ALIASES_ADDED"

    # 检测当前 shell 类型
    if [[ $SHELL == *"zsh"* ]]; then
        SHELL_RC="~/.zshrc"
    else
        SHELL_RC="~/.bashrc"
    fi

    # 检查标记是否存在，避免重复添加
    if grep -q "$MARKER" "$SHELL_RC"; then
        echo "✅ 快捷指令已存在，无需重复添加。"
        return
    fi

    # 添加 alias 并写入标记（静默执行）
    {
        echo "$MARKER"
        echo "$ALIAS_CMD"
        echo "$ALIAS_CMD2"
    } >> "$SHELL_RC"

    # 让 alias 立即生效
    source "$SHELL_RC"

    echo "✅ 快捷指令已成功添加并自动生效！现在你可以直接输入 'a' 或 '5' 来运行脚本。🚀"
}

add_aliases

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
install_base

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
      pkill -f cloudflared 2>/dev/null
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
        /root/sbox/cloudflared tunnel --config /root/sbox/tunnel.yml run > /root/sbox/argo_run.log 2>&1 &
      else
        if [[ -n "$argo_auth" ]]; then
          echo "正在使用令牌启动Argo隧道..."
          /root/sbox/cloudflared tunnel --token "$argo_auth" run > /root/sbox/argo_run.log 2>&1 &
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
      pkill -f cloudflared 2>/dev/null
    fi

    # 启动临时隧道
  nohup /root/sbox/cloudflared tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol http2 > /root/sbox/argo.log 2>&1 &
    sleep 2
    echo -e "\e[1;3;33m等待 Cloudflare Argo 生成地址...\e[0m"
    sleep 5

    # 获取生成的 Argo 域名
    argo=$(cat /root/sbox/argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    echo "$argo" | base64 > /root/sbox/argo.txt.b64
  fi
}

#重启sing-box服务
restart_singbox() {
    # 获取 sing-box 配置文件路径
    SBOX_DIR="/root/sbox"
    CONFIG_FILE="$SBOX_DIR/sbconfig_server.json"
    SING_BOX_BIN="$SBOX_DIR/sing-box"

    # 检查 sing-box 是否安装
    if [ ! -f "$SING_BOX_BIN" ]; then
        echo -e "\e[1;3;31m错误: sing-box 未找到！请先运行 download_singbox()\e[0m"
        exit 1
    fi

    # 获取 sing-box 版本
    SING_BOX_VERSION=$("$SING_BOX_BIN" version 2>/dev/null | head -n1 | grep -oP '\d+\.\d+\.\d+')

    if [[ "$SING_BOX_VERSION" > "1.10.2" ]]; then
        CONFIG_FILE="$SBOX_DIR/sbconfig1_server.json"
    else
        CONFIG_FILE="$SBOX_DIR/sbconfig_server.json"
    fi

    echo -e "\e[1;3;35m正在重启sing-box服务...\e[0m"
    sleep 2
    # 检查 sing-box 配置文件是否有效
    if $SING_BOX_BIN check -c "$CONFIG_FILE"; then
        echo -e "\e[1;3;33m配置检查成功，正在重启 sing-box...\e[0m"

        # 重启 sing-box 服务
        systemctl daemon-reload
        systemctl restart sing-box

        if systemctl is-active --quiet sing-box; then
            echo -e "\e[1;3;32m === sing-box-$SING_BOX_VERSION 已成功重启！===\e[0m"
        else
            echo -e "\e[1;3;31msing-box 重启失败！\e[0m"
        fi
    else
        echo -e "\e[1;3;31m配置错误，sing-box 无法重启！\e[0m"
    fi
}
# 下载 cloudflared 官方版
download_cloudflared() {
    official_dir="/root/sbox/"
    mkdir -p "$official_dir" 
    
    # 检测系统架构
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
        *)
            echo -e "\e[1;31mUnsupported architecture: ${arch}\e[0m"  
            return 1
            ;;
    esac

    # cloudflared 下载 URL
    cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
    
    # 下载 cloudflared 官方版并保存到指定目录
    curl -sLo "/root/sbox/cloudflared-linux" "$cf_url"
    
    if [[ $? -ne 0 ]]; then
        echo -e "\e[1;31mFailed to download cloudflared.\e[0m"
        return 1
    fi

    # 为下载的文件设置可执行权限
    chmod +x "/root/sbox/cloudflared-linux" 
    
    # 重命名文件为 cloudflared
    mv "/root/sbox/cloudflared-linux" "/root/sbox/cloudflared"

    # 安装成功提示
    echo -e "\e[1;3;32mcloudflared安装成功\e[0m"

    echo -e "\e[1;35m======================\e[0m"
}
# 下载singbox
download_singbox() {
    echo -e "\e[1;3;33m请选择要下载的版本:\e[0m"
    echo -e "\e[1;3;32m1. 更新最新版本 (正式版 + 测试版)\e[0m"
    echo -e "\e[1;3;32m2. 使用旧版本 (正式版 + 测试版)\e[0m"
    read -p $'\e[1;3;33m请输入选项 (1-2): \e[0m' version_choice

    arch=$(uname -m)
    echo -e "\e[1;3;32m=== 本机系统架构: $arch ===\e[0m"

    case ${arch} in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
    esac

    release_path="/root/sbox/latest_version"
    old_version_path="/root/sbox/old_version"
    mkdir -p "$release_path" "$old_version_path"

    if [ "$version_choice" == "1" ]; then
        # 获取最新正式版 & 测试版版本号
        latest_release_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | jq -r '.[] | select(.prerelease == false) | .tag_name' | sort -V | tail -n 1)
        latest_release_version=${latest_release_tag#v}
        latest_prerelease_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | jq -r '.[] | select(.prerelease == true) | .tag_name' | sort -V | tail -n 1)
        latest_prerelease_version=${latest_prerelease_tag#v}

        release_package="sing-box-${latest_release_version}-linux-${arch}.tar.gz"
        release_url="https://github.com/SagerNet/sing-box/releases/download/${latest_release_tag}/${release_package}"
        prerelease_package="sing-box-${latest_prerelease_version}-linux-${arch}.tar.gz"
        prerelease_url="https://github.com/SagerNet/sing-box/releases/download/${latest_prerelease_tag}/${prerelease_package}"

        # 下载正式版（如果不存在）
        if [ ! -f "$release_path/sing-box-$latest_release_version" ]; then
            echo -e "\e[1;3;32m下载最新正式版: $latest_release_version\e[0m"
            if curl -sLo "/root/${release_package}" "$release_url"; then
                tar -xzf "/root/${release_package}" -C /root
                mv "/root/sing-box-${latest_release_version}-linux-${arch}/sing-box" "$release_path/sing-box-$latest_release_version"
                rm -r "/root/${release_package}" "/root/sing-box-${latest_release_version}-linux-${arch}"
                chmod +x "$release_path/sing-box-$latest_release_version"
                echo -e "\e[1;3;32m  最新正式版已下载: $latest_release_version\e[0m"
            else
                echo -e "\e[1;3;31m✖ 正式版下载失败，请检查网络连接。\e[0m"
            fi
        fi

        # 下载测试版（如果不存在）
        if [ ! -f "$release_path/sing-box-test-$latest_prerelease_version" ]; then
            echo -e "\e[1;3;33m下载最新测试版: $latest_prerelease_version\e[0m"
            if curl -sLo "/root/${prerelease_package}" "$prerelease_url"; then
                tar -xzf "/root/${prerelease_package}" -C /root
                mv "/root/sing-box-${latest_prerelease_version}-linux-${arch}/sing-box" "$release_path/sing-box-$latest_prerelease_version"
                rm -r "/root/${prerelease_package}" "/root/sing-box-${latest_prerelease_version}-linux-${arch}"
                chmod +x "$release_path/sing-box-$latest_prerelease_version"
                echo -e "\e[1;3;33m  最新测试版已下载: $latest_prerelease_version\e[0m"
            else
                echo -e "\e[1;3;31m✖ 测试版下载失败，请检查网络连接。\e[0m"
            fi
        fi
        echo -e "\e[1;35m======================\e[0m"
        # 选择使用哪个版本
        echo -e "\e[1;3;33m请选择要使用的版本启动服务:\e[0m"
        echo -e "\e[1;3;32m1. 最新正式版 ($latest_release_version)\e[0m"
        echo -e "\e[1;3;33m2. 最新测试版 ($latest_prerelease_version)\e[0m"
        read -p $'\e[1;3;33m请输入选项 (1-2): \e[0m' latest_choice

        rm -f /root/sbox/sing-box
        if [ "$latest_choice" == "1" ]; then
            ln -sf "$release_path/sing-box-$latest_release_version" /root/sbox/sing-box
            echo -e "\e[1;3;32m  使用最新正式版: $latest_release_version\e[0m"
        else
            ln -sf "$release_path/sing-box-$latest_prerelease_version" /root/sbox/sing-box
            echo -e "\e[1;3;33m  使用最新测试版: $latest_prerelease_version\e[0m"
        fi

    elif [ "$version_choice" == "2" ]; then
        rm -f /root/sbox/sing-box

        old_release_version="1.10.2"
        old_prerelease_version="1.11.0-alpha.19"

        old_release_path="$old_version_path/sing-box-$old_release_version"
        old_prerelease_path="$old_version_path/sing-box-$old_prerelease_version"

        old_release_url="https://github.com/yyf-lbl/sing-box-reality-hysteria2/releases/download/sing-box/sing-box-${old_release_version}"
        old_prerelease_url="https://github.com/yyf-lbl/sing-box-reality-hysteria2/releases/download/sing-box/sing-box-${old_prerelease_version}"

        if [ ! -f "$old_release_path" ]; then
            echo -e "\e[1;3;32m下载旧正式版: $old_release_version\e[0m"
            curl -sLo "$old_release_path" "$old_release_url" && chmod +x "$old_release_path"
        fi

        if [ ! -f "$old_prerelease_path" ]; then
            echo -e "\e[1;3;33m下载旧测试版: $old_prerelease_version\e[0m"
            curl -sLo "$old_prerelease_path" "$old_prerelease_url" && chmod +x "$old_prerelease_path"
        fi
        echo -e "\e[1;35m======================\e[0m"
        echo -e "\e[1;3;33m请选择要使用的旧版本启动服务:\e[0m"
        echo -e "\e[1;3;32m1. 旧正式版 ($old_release_version)\e[0m"
        echo -e "\e[1;3;33m2. 旧测试版 ($old_prerelease_version)\e[0m"
        read -p $'\e[1;3;33m请输入选项 (1-2): \e[0m' old_choice

        if [ "$old_choice" == "1" ]; then
            ln -sf "$old_release_path" /root/sbox/sing-box
            echo -e "\e[1;3;32m   使用旧正式版: $old_release_version\e[0m"
        else
            ln -sf "$old_prerelease_path" /root/sbox/sing-box
            echo -e "\e[1;3;33m   使用旧测试版: $old_prerelease_version\e[0m"
        fi
    fi

    echo -e "\e[1;3;32m 下载任务完成！\e[0m"
}
# 下载singbox最新测试版内核和正式版
download_sing-box() {
    local version_type="$1"
    local arch=$(uname -m)
    case ${arch} in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
    esac

    release_path="/root/sbox/latest_version"
    old_version_path="/root/sbox/old_version"
    mkdir -p "$release_path" "$old_version_path"

    if [[ "$version_type" == "latest_release" || "$version_type" == "latest_prerelease" ]]; then
        latest_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | jq -r ".[] | select(.prerelease == $( [ "$version_type" == "latest_prerelease" ] && echo "true" || echo "false" )) | .tag_name" | sort -V | tail -n 1)
        latest_version=${latest_tag#v}
        package="sing-box-${latest_version}-linux-${arch}.tar.gz"
        url="https://github.com/SagerNet/sing-box/releases/download/${latest_tag}/${package}"
        target_path="$release_path/sing-box-${latest_version}"

        # 检查是否已经存在 sing-box 文件
        if [ -f "$target_path" ]; then
            echo -e "\e[1;3;32m已存在最新版本 sing-box-${latest_version} \e[0m"
            return 0  # 如果文件已经存在，跳过下载
        fi

    elif [[ "$version_type" == "old_release" || "$version_type" == "old_prerelease" ]]; then
   
        if [[ "$version_type" == "old_release" ]]; then
            old_version="1.10.2"
         
        elif [[ "$version_type" == "old_prerelease" ]]; then
            old_version="1.11.0-alpha.19"
        fi
        
     url="https://github.com/yyf-lbl/sing-box-reality-hysteria2/releases/download/sing-box/sing-box-${old_version}"
       package="sing-box-${old_version}"
        target_path="$old_version_path/sing-box-${old_version}"

        # 检查是否已经存在 sing-box 文件
        if [ -f "$target_path" ]; then
            echo -e "\e[1;3;32m已存在旧版本 sing-box-${old_version} \e[0m"
            return 0  # 如果文件已经存在，跳过下载
        fi
    else
        echo -e "\e[1;3;31m无效的下载选项。\e[0m"
        exit 1
    fi

    # 下载并设置执行权限
    echo -e "\e[1;3;32m下载 sing-box 版本: $latest_version\e[0m"
     sleep 2
    if curl -sLo "/root/${package}" "$url"; then
        if [[ "$version_type" == "latest_release" || "$version_type" == "latest_prerelease" ]]; then
            tar -xzf "/root/${package}" -C /root
            mv "/root/sing-box-${latest_version}-linux-${arch}/sing-box" "$target_path"
            rm -r "/root/${package}" "/root/sing-box-${latest_version}-linux-${arch}"
        else
            mv "/root/${package}" "$target_path"
        fi
        chmod +x "$target_path"
    else
        echo -e "\e[1;3;31m下载失败，请检查网络连接。\e[0m"
        exit 1
    fi

    # 软链接到 sing-box 目录
    ln -sf "$target_path" /root/sbox/sing-box
     #echo -e "\e[1;3;32m=== sing-box版本切换成功 ===\e[0m"
}
#切换内核
switch_kernel() {
 # 检测当前 sing-box 版本
    current_version=$(/root/sbox/sing-box version 2>/dev/null | head -n 1 | awk '{print $NF}')
    echo -e "\e[1;3;32m=== 当前正在运行 sing-box 版本: $current_version ===\e[0m"
    echo ""
    echo -e "\e[1;3;33m请选择要切换的 sing-box 版本:\e[0m"
    echo -e "\e[1;3;32m1. 最新正式版\e[0m"
    echo -e "\e[1;3;33m2. 最新测试版\e[0m"
    echo -e "\e[1;3;32m3. 旧正式版\e[0m"
    echo -e "\e[1;3;33m4. 旧测试版\e[0m"
    read -p $'\e[1;3;31m请输入选项 (1-4): \e[0m' version_choice
    echo -e "\e[1;35m======================\e[0m"
    # 选择要下载的版本
   case $version_choice in
        1) 
            echo -e "\e[1;3;32m 最新正式版正在切换中...\e[0m"
            sleep 2
            download_sing-box latest_release
            CONFIG_FILE="/root/sbox/sbconfig1_server.json" 
            version_type="latest_release"
            ;;
        2)
            echo -e "\e[1;3;33m 最新测试版正在切换中...\e[0m"
            sleep 2
            download_sing-box latest_prerelease
            CONFIG_FILE="/root/sbox/sbconfig1_server.json"
            version_type="latest_prerelease"
            ;;
        3)
            echo -e "\e[1;3;32m 旧正式版正在切换中...\e[0m"
            sleep 2
            download_sing-box old_release
            CONFIG_FILE="/root/sbox/sbconfig_server.json"
            version_type="old_release"
            ;;
        4)
            echo -e "\e[1;3;33m 旧测试版正在切换中...\e[0m"
            sleep 2
            download_sing-box old_prerelease
            CONFIG_FILE="/root/sbox/sbconfig1_server.json"
            version_type="old_prerelease"
            ;;
        *)
            echo -e "\e[1;3;31m无效选择，请输入 1-4 之间的数字。\e[0m"
            exit 1
            ;;
    esac

    # 确保配置文件存在
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "\e[1;3;31m错误: 找不到配置文件 $CONFIG_FILE\e[0m"
        exit 1
    fi

    # 删除旧的软链接（如果存在）
    if [ -L /root/sbox/sing-box ]; then
       # echo -e "\e[1;3;32m删除旧的软链接...\e[0m"
        rm -f /root/sbox/sing-box
    fi

    # 根据版本类型设置目标路径
    if [[ "$version_type" == "latest_release" || "$version_type" == "latest_prerelease" ]]; then
        target_path="/root/sbox/latest_version/sing-box-${latest_version}"
    else
        if [[ "$version_type" == "old_release" ]]; then
            old_version="1.10.2"  # 旧正式版的版本号
        elif [[ "$version_type" == "old_prerelease" ]]; then
            old_version="1.11.0-alpha.19"  # 旧测试版的版本号
        fi
        target_path="/root/sbox/old_version/sing-box-${old_version}"
    fi

    # 创建新的软链接
   # echo -e "\e[1;3;32m创建新的软链接指向: $target_path\e[0m"
    ln -sf "$target_path" /root/sbox/sing-box
     current_version=$(/root/sbox/sing-box version 2>/dev/null | head -n 1 | awk '{print $NF}')
    echo -e "\e[1;3;32m=== 已切换为:sing-box-$current_version ===\e[0m"
    echo "======================"
    # 启动服务
    setup_services "$CONFIG_FILE" || {
        echo -e "\e[1;3;31m服务启动失败！请检查日志。\e[0m"
        exit 1
    }
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

        hy2_server_link="hysteria2://$hy_password@$server_ip:$hy_current_listen_port?insecure=1&sni=$hy_current_server_name&alpn=h3"
        echo -e "\e[1;3;31mHysteria2 客户端通用链接：\e[0m"
        echo -e "\e[1;3;33m$hy2_server_link\e[0m"
        echo ""
    fi

    # 生成 TUIC 客户端链接
    if jq -e '.inbounds[] | select(.type == "tuic")' /root/sbox/sbconfig_server.json > /dev/null; then
        tuic_listen_port=$(jq -r '.inbounds[] | select(.type == "tuic") | .listen_port' /root/sbox/sbconfig_server.json)
        tuic_server_name=$(openssl x509 -in /root/self-cert/cert.pem -noout -subject -nameopt RFC2253 | awk -F'=' '{print $NF}')
        tuic_password=$(jq -r '.inbounds[] | select(.type == "tuic") | .users[0].password' /root/sbox/sbconfig_server.json)

        tuic_server_link="tuic://$tuic_password@$server_ip:$tuic_listen_port?sni=$tuic_server_name"
        echo -e "\e[1;3;31mTUIC 客户端通用链接：\e[0m"
        echo -e "\e[1;3;33m$tuic_server_link\e[0m"
        echo ""
    fi

    # 判断是否存在固定隧道配置 生成 VMess 客户端链接
    if [[ -f "/root/sbox/tunnel.json" || -f "/root/sbox/tunnel.yml" ]]; then
        echo -e "\e[1;3;31m使用固定隧道生成的Vmess客户端通用链接,替换$argo_domain为cloudflare优选ip或域名,可获得极致速度体验！\e[0m"
        echo ""
        echo -e "\e[1;3;32m以下端口 443 可改为 2053 2083 2087 2096 8443\e[0m"
        vmess_link_tls='vmess://'$(echo '{"add":"'$argo_domain'","aid":"0","host":"'$argo_domain'","id":"'$vmess_uuid'","scy":"none","net":"ws","path":"'$ws_path'","port":"443","ps":"vmess-tls","tls":"tls","type":"none","sni":"'$argo_domain'","allowInsecure":true,"v":"2"}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_tls\e[0m"
        echo ""
        echo -e "\e[1;3;32m以下端口 80 可改为 8080 8880 2052 2082 2086 2095\e[0m"
        vmess_link_no_tls='vmess://'$(echo '{"add":"'$argo_domain'","aid":"0","host":"'$argo_domain'","id":"'$vmess_uuid'","scy":"none","net":"ws","path":"'$ws_path'","port":"80","ps":"vmess-no-tls","tls":"","type":"none","v":"2"}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_no_tls\e[0m"
        echo ""
    else
        # 生成临时隧道链接
        if jq -e '.inbounds[] | select(.type == "vmess")' /root/sbox/sbconfig_server.json > /dev/null; then
            vmess_uuid=$(jq -r '.inbounds[] | select(.type == "vmess") | .users[0].uuid' /root/sbox/sbconfig_server.json)
            ws_path=$(jq -r '.inbounds[] | select(.type == "vmess") | .transport.path' /root/sbox/sbconfig_server.json)
            argo=$(base64 --decode /root/sbox/argo.txt.b64)
            echo -e "\e[1;3;31m使用临时隧道生成的Vmess客户端通用链接，替换speed.cloudflare.com为自己的优选ip可获得极致体验\e[0m"
       echo -e "\e[1;3;32m以下端口 443 可改为 2053 2083 2087 2096 8443\e[0m"
        echo ""
        vmess_link_tls='vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"vmess-tls","tls":"tls","type":"none","sni":"'$argo'","allowInsecure":true,"v":"2"}' | base64 -w 0)
        echo -e "\e[1;3;33m$vmess_link_tls\e[0m"
        echo ""
        echo -e "\e[1;3;32m以下端口 80 可改为 8080 8880 2052 2082 2086 2095\e[0m" 
        echo ""
        vmess_link_no_tls='vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"vmess-no-tls","tls":"","type":"none","v":"2"}' | base64 -w 0)
          echo -e "\e[1;3;33m$vmess_link_no_tls\e[0m"
        echo ""
        fi
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
    pkill -f cloudflared
    sleep 2  # 等待进程完全终止

    # 判断是固定隧道还是临时隧道
    if [ -f "/root/sbox/tunnel.json" ] || [ -f "/root/sbox/tunnel.yml" ]; then
        echo -e "\e[1;3;32m启动固定隧道...\e[0m"
        /root/sbox/cloudflared tunnel --config /root/sbox/tunnel.yml run > /root/sbox/argo_run.log 2>&1 &
    else
        echo -e "\e[1;3;32m正在重新启动临时隧道...\e[0m"
        echo ""
        pid=$(pgrep -f cloudflared)
        if [ -n "$pid" ]; then
            echo -e "\e[1;3;33m终止现有进程...\e[0m"
            pkill -f cloudflared 2>/dev/null
            sleep 2  # 等待进程完全终止
        fi

        # 启动临时隧道
       nohup /root/sbox/cloudflared tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol http2 > /root/sbox/argo.log 2>&1 &
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
Type=simple
ExecStartPre=/bin/bash -c 'if pgrep -x "cloudflared-linux" > /dev/null; then echo -e "\e[32m\e[3mCloudflared is already running\e[0m"; exit 0; fi'
ExecStart=/bin/bash -c 'if [ -f "/root/sbox/tunnel.yml" ] || [ -f "/root/sbox/tunnel.json" ]; then /root/sbox/cloudflared tunnel --config /root/sbox/tunnel.yml run > /root/sbox/argo_run.log 2>&1; else /root/sbox/cloudflared tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol http2 > /root/sbox/argo_run.log 2>&1; fi'
Restart=always
RestartSec=5s
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
    echo -e "\e[1;3;31m正在卸载 sing-box 服务...\e[0m"
    echo ""

    # 询问用户是否确认卸载
    while true; do
        read -p $'\e[1;3;33m您确定要卸载 sing-box 服务吗？(y/n) [默认 y]: \e[0m' confirm
        confirm=${confirm,,}  # 转换为小写
        [[ -z "$confirm" ]] && confirm="y"  # 默认值为 y
        case "$confirm" in
            y) break ;;  # 继续卸载
            n) echo "取消卸载。"; return ;;
            *) echo "无效输入，请输入 y 或 n。" ;;
        esac
    done

    # 停止并禁用 Cloudflare 隧道服务
    if systemctl is-active --quiet cloudflared; then
        echo -e "\e[1;3;33m正在停止 Cloudflare 隧道服务...\e[0m"
        systemctl stop cloudflared >/dev/null 2>&1
        systemctl disable cloudflared >/dev/null 2>&1
    fi

    # 停止现有的 cloudflared 进程
    pkill -f cloudflared-linux >/dev/null 2>&1
    sleep 2

    # 停止并禁用 sing-box 服务
    systemctl stop sing-box >/dev/null 2>&1
    systemctl disable sing-box >/dev/null 2>&1

    # 定义要删除的文件和目录
    files_to_remove=(
        "/etc/systemd/system/sing-box.service"
        "/etc/systemd/system/cloudflared.service"
        "/root/sbox/sbconfig_server.json"
        "/root/sbox/sbconfig1_server.json"
        "/root/sbox/latest_version"
        "/root/sbox/old_version"
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

    # 删除文件（隐藏错误信息）
    for file in "${files_to_remove[@]}"; do
        rm -f "$file" >/dev/null 2>&1
    done

    # 删除目录（隐藏错误信息）
    for dir in "${directories_to_remove[@]}"; do
        rm -rf "$dir" >/dev/null 2>&1
    done

    echo -e "\e[1;3;32m✔ sing-box 卸载完成！\e[0m"
}

# 安装sing-box
install_singbox() {     
  while true; do
    echo -e "\e[1;3;33m请选择要安装的协议（输入数字，多个选择用空格分隔）:\e[0m"
    echo -e "\e[1;3;33m1) vless-Reality\e[0m"
    echo -e "\e[1;3;33m2) VMess\e[0m"
    echo -e "\e[1;3;33m3) Hysteria2\e[0m"
    echo -e "\e[1;3;33m4) Tuic\e[0m"
    read -p $'\e[1;3;33m请输入你的选择: \e[0m' choices
    echo ""  
    if [[ -z "$choices" ]]; then
        echo "输入不能为空，请重新输入。"
        continue
    fi
    read -a selected_protocols <<< "$choices"
    valid=true
    for choice in "${selected_protocols[@]}"; do
        if [[ ! "$choice" =~ ^[1-4]$ ]]; then
            valid=false
            break
        fi
    done

    if [ "$valid" = false ]; then
        echo -e "\033[1;3;31m选择的协议无效，请选择 1 到 4 之间的数字，且不能为空。\033[0m"
    else
        echo -e "\e[1;3;32m正在根据所选协议正在进行配置...\e[0m"
        sleep 2
        break  # 有效选择后退出循环
    fi
done
    listen_port=443
    vmess_port=15555
    hy_listen_port=8443
    tuic_listen_port=8080
dns_servers=("1.1.1.1" "8.8.8.8" "9.9.9.9")
dns_names=("cloudflare" "google" "quad9")
latencies=()
min_latency=9999
fastest_dns=""
for i in "${!dns_servers[@]}"; do
    latency=$(ping -c 1 -W 1 "${dns_servers[i]}" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
    if [[ $latency =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        latencies[i]=$latency
      echo -e "\033[1;3;35m${dns_names[i]} DNS 延迟: ${latency}ms\033[0m"
    else
        latencies[i]=9999
        echo "${dns_names[i]} DNS latency: Unreachable"
    fi
done
for i in "${!latencies[@]}"; do
    if (( $(echo "${latencies[i]} < $min_latency" | bc -l) )); then
        min_latency=${latencies[i]}
        fastest_dns=${dns_names[i]}
    fi
done
if [[ -n $fastest_dns ]]; then
   echo -e "\033[1;3;33m最快的 DNS 是 ${fastest_dns}，延迟为 ${min_latency} 毫秒。\033[0m"
else
    echo -e "\033[1;3;31m找不到可访问的DNS。\033[0m"
fi
config="{
  \"log\": {
    \"disabled\": false,
    \"level\": \"info\",
    \"output\": \"/root/sbox/sb.log\",
    \"timestamp\": true
  },
  \"dns\": {
    \"servers\": [
      {
        \"tag\": \"cloudflare\",
        \"address\": \"https://1.1.1.1/dns-query\",
        \"strategy\": \"prefer_ipv4\",
        \"detour\": \"direct\"
      },
      {
        \"tag\": \"google\",
        \"address\": \"tls://8.8.8.8\",
        \"strategy\": \"prefer_ipv4\",
        \"detour\": \"direct\"
      },
      {
        \"tag\": \"quad9\",
        \"address\": \"https://9.9.9.9/dns-query\",
        \"strategy\": \"prefer_ipv4\",
        \"detour\": \"direct\"
      }
    ],
        \"final\": \"$fastest_dns\",  
        \"strategy\": \"prefer_ipv4\",
        \"disable_cache\": false,
        \"disable_expire\": false
  },
  \"inbounds\": [],
 \"outbounds\": [
    {
      \"type\": \"direct\",
      \"tag\": \"direct\"
    },
    {
      \"type\": \"direct\",
      \"tag\": \"direct-ipv4-prefer-out\",
      \"domain_strategy\": \"prefer_ipv4\"
    },
    {
      \"type\": \"direct\",
      \"tag\": \"direct-ipv4-only-out\",
      \"domain_strategy\": \"ipv4_only\"
    },
    {
      \"type\": \"wireguard\",
      \"tag\": \"wireguard-out\",
      \"server\": \"engage.cloudflareclient.com\",
      \"server_port\": 2408,
      \"local_address\": [
        \"172.16.0.2/32\",
        \"2606:4700:110:812a:4929:7d2a:af62:351c/128\"
      ],
      \"private_key\": \"gBthRjevHDGyV0KvYwYE52NIPy29sSrVr6rcQtYNcXA=\",
      \"peer_public_key\": \"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=\",
      \"mtu\": 1420,
      \"reserved\": [6,146,6]
    },
    {
      \"type\": \"direct\",
      \"tag\": \"wireguard-ipv4-prefer-out\",
      \"detour\": \"wireguard-out\",
      \"domain_strategy\": \"prefer_ipv4\"
    },
    {
      \"type\": \"direct\",
      \"tag\": \"wireguard-ipv4-only-out\",
      \"detour\": \"wireguard-out\",
      \"domain_strategy\": \"ipv4_only\"
    }
  ],
  \"route\": {
    \"rule_set\": [
      {
        \"tag\": \"geosite-netflix\",
        \"type\": \"remote\",
        \"format\": \"binary\",
        \"url\": \"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-netflix.srs\",
        \"update_interval\": \"1d\"
      },
      {
        \"tag\": \"geosite-openai\",
        \"type\": \"remote\",
        \"format\": \"binary\",
        \"url\": \"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/openai.srs\",
        \"update_interval\": \"1d\"
      }
    ],
    \"rules\": [
      {
        \"rule_set\": [
          \"geosite-netflix\"
        ],
        \"outbound\": \"wireguard-ipv4-only-out\"
      },
      {
        \"domain\": [
          \"api.statsig.com\",
          \"browser-intake-datadoghq.com\",
          \"cdn.openai.com\",
          \"chat.openai.com\",
          \"auth.openai.com\",
          \"chat.openai.com.cdn.cloudflare.net\",
          \"ios.chat.openai.com\",
          \"o33249.ingest.sentry.io\",
          \"openai-api.arkoselabs.com\",
          \"openaicom-api-bdcpf8c6d2e9atf6.z01.azurefd.net\",
          \"openaicomproductionae4b.blob.core.windows.net\",
          \"production-openaicom-storage.azureedge.net\",
          \"static.cloudflareinsights.com\"
        ],
        \"domain_suffix\": [
          \".algolia.net\",
          \".auth0.com\",
          \".chatgpt.com\",
          \".challenges.cloudflare.com\",
          \".client-api.arkoselabs.com\",
          \".events.statsigapi.net\",
          \".featuregates.org\",
          \".identrust.com\",
          \".intercom.io\",
          \".intercomcdn.com\",
          \".launchdarkly.com\",
          \".oaistatic.com\",
          \".oaiusercontent.com\",
          \".observeit.net\",
          \".openai.com\",
          \".openaiapi-site.azureedge.net\",
          \".openaicom.imgix.net\",
          \".segment.io\",
          \".sentry.io\",
          \".stripe.com\"
        ],
        \"domain_keyword\": [
          \"openaicom-api\"
        ],
        \"outbound\": \"wireguard-ipv4-prefer-out\"
      }
    ],
    \"final\": \"direct\"
  },
  \"experimental\": {
    \"cache_file\": {
      \"enabled\": true,
      \"path\": \"/root/sbox/cache.db\",
      \"cache_id\": \"mycacheid\",
      \"store_fakeip\": true
    }
  }
} "
  config1="{
  \"log\": {
    \"disabled\": false,
    \"level\": \"info\",
    \"output\": \"/root/sbox/sb.log\",
    \"timestamp\": true
  },
  \"dns\": {
    \"servers\": [
      {
        \"tag\": \"cloudflare\",
        \"address\": \"https:\/\/1.1.1.1\/dns-query\",
        \"strategy\": \"ipv4_only\",
        \"detour\": \"direct\"
      },
      {
        \"tag\": \"google\",
        \"address\": \"tls:\/\/8.8.8.8\",
        \"strategy\": \"ipv4_only\",
        \"detour\": \"direct\"
      },
      {
        \"tag\": \"quad9\",
        \"address\": \"https:\/\/9.9.9.9\/dns-query\",
        \"strategy\": \"ipv4_only\",
        \"detour\": \"direct\"
      }
    ],
    \"rules\": [
      {
        \"domain_suffix\": \"google.com\",
        \"server\": \"google\"
      },
      {
        \"domain_suffix\": \"cloudflare.com\",
        \"server\": \"cloudflare\"
      },
      {
        \"domain_suffix\": \"quad9.net\",
        \"server\": \"quad9\"
      }
    ],
    \"final\": \"$fastest_dns\",
    \"strategy\": \"ipv4_only\",
    \"disable_cache\": false,
    \"disable_expire\": false
  },
  \"inbounds\": [],
  \"outbounds\": [
    {
      \"type\": \"direct\",
      \"tag\": \"direct\"
    }
  ],
  \"endpoints\": [
    {
      \"type\": \"wireguard\",
      \"tag\": \"warp-ep\",
      \"mtu\": 1280,
      \"address\": [
        \"172.16.0.2\/32\",
        \"2606:4700:110:8a36:df92:102a:9602:fa18\/128\"
      ],
      \"private_key\": \"gBthRjevHDGyV0KvYwYE52NIPy29sSrVr6rcQtYNcXA=\",
      \"peers\": [
        {
          \"address\": \"engage.cloudflareclient.com\",
          \"port\": 2408,
          \"public_key\": \"bmXOC+F1FxEMF9dyiK2H5\/1SUtzH0JuVo51h2wPfgyo=\",
          \"allowed_ips\": [
            \"0.0.0.0\/0\",
            \"::\/0\"
          ],
          \"reserved\": [6, 146, 6]
        }
      ]
    }
  ],
  \"route\": {
    \"rule_set\": [
      {
        \"tag\": \"geosite-openai\",
        \"type\": \"remote\",
        \"format\": \"binary\",
        \"url\": \"https:\/\/raw.githubusercontent.com\/MetaCubeX\/meta-rules-dat\/sing\/geo\/geosite\/openai.srs\",
        \"update_interval\": \"1d\"
      }
    ],
    \"rules\": [
      {
        \"action\": \"sniff\"
      },
      {
        \"action\": \"resolve\",
        \"domain\": [
          \"api.statsig.com\",
          \"browser-intake-datadoghq.com\",
          \"cdn.openai.com\",
          \"chat.openai.com\",
          \"auth.openai.com\",
          \"chat.openai.com.cdn.cloudflare.net\",
          \"ios.chat.openai.com\",
          \"o33249.ingest.sentry.io\",
          \"openai-api.arkoselabs.com\",
          \"openaicom-api-bdcpf8c6d2e9atf6.z01.azurefd.net\",
          \"openaicomproductionae4b.blob.core.windows.net\",
          \"production-openaicom-storage.azureedge.net\",
          \"static.cloudflareinsights.com\"
        ],
        \"domain_suffix\": [
          \".algolia.net\",
          \".auth0.com\",
          \".chatgpt.com\",
          \".challenges.cloudflare.com\",
          \".client-api.arkoselabs.com\",
          \".events.statsigapi.net\",
          \".featuregates.org\",
          \".identrust.com\",
          \".intercom.io\",
          \".intercomcdn.com\",
          \".launchdarkly.com\",
          \".oaistatic.com\",
          \".oaiusercontent.com\",
          \".observeit.net\",
          \".openai.com\",
          \".openaiapi-site.azureedge.net\",
          \".openaicom.imgix.net\",
          \".segment.io\",
          \".sentry.io\",
          \".stripe.com\"
        ],
        \"strategy\": \"prefer_ipv4\"
      },
      {
        \"action\": \"resolve\",
        \"rule_set\": [\"geosite-openai\"],
        \"strategy\": \"prefer_ipv6\"
      },
      {
        \"domain\": [\"api.openai.com\"],
        \"rule_set\": [\"geosite-openai\"],
        \"outbound\": \"warp-ep\"
      }
    ]
  },
  \"experimental\": {
    \"cache_file\": {
      \"enabled\": true,
      \"path\": \"\/root\/sbox\/cache.db\",
      \"cache_id\": \"mycacheid\",
      \"store_fakeip\": true
    }
  }
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
                # 提示用户输入自定义端口，或者选择随机生成端口
read -p $'\e[1;3;33m请输入 VLESS 监听端口 (默认端口: 443)，或输入 y 生成随机端口, 直接回车使用默认端口: \e[0m' vless_listen_port_input
sleep 1

# 如果用户输入 y 或 Y，则随机生成端口（范围为10000到65535）
if [[ "$vless_listen_port_input" == "y" || "$vless_listen_port_input" == "Y" ]]; then
    vless_listen_port=$((RANDOM % 55536 + 10000))
    echo -e "\e[1;3;32m自动生成的 VLESS 端口: $vless_listen_port\e[0m"
# 如果用户输入了自定义端口且输入有效，使用自定义端口
elif [[ "$vless_listen_port_input" =~ ^[0-9]+$ ]] && [ "$vless_listen_port_input" -ge 10000 ] && [ "$vless_listen_port_input" -le 65535 ]; then
    vless_listen_port=$vless_listen_port_input
    echo -e "\e[1;3;32m使用自定义的 VLESS 端口: $vless_listen_port\e[0m"
else
    # 否则使用默认的已设置端口
    echo -e "\e[1;3;32m使用默认的 VLESS 端口: $vless_listen_port\e[0m"
fi
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
                    config1=$(echo "$config1" | jq --arg listen_port "$listen_port" \
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
# 提示用户输入自定义端口，或者选择随机生成端口
read -p $'\e[1;3;33m请输入 vmess 端口(默认端口: 15555)，或输入 y 生成随机端口, 直接回车使用默认端口: \e[0m' user_input

# 如果用户输入 y 或 Y，则随机生成端口（范围为10000到65535）
if [[ "$user_input" == "y" || "$user_input" == "Y" ]]; then
    # 随机生成端口范围（10000 到 65535）
    vmess_port=$((RANDOM % 55536 + 10000))
    echo -e "\e[1;3;32m自动生成的 vmess 端口: $vmess_port\e[0m"
# 如果用户输入了自定义端口且输入有效，使用自定义端口
elif [[ "$user_input" =~ ^[0-9]+$ ]] && [ "$user_input" -ge 10000 ] && [ "$user_input" -le 65535 ]; then
    vmess_port=$user_input
   echo -e "\e[1;3;32m使用自定义的 vmess 端口: $vmess_port\e[0m"
else
    # 否则使用已设置的默认端口
    echo -e "\e[1;3;32m使用默认的 vmess 端口: $vmess_port\e[0m"
fi
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
        echo "$argo_auth" > /root/sbox/tunnel.json
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
       /root/sbox/cloudflared tunnel --config /root/sbox/tunnel.yml run > /root/sbox/argo_run.log 2>&1 &
       echo "" 
        echo -e "\e[1;3;32mCloudflared 固定隧道功能已启动！\e[0m"
    echo ""
    fi
else
pid=$(pgrep -f cloudflared)
if [ -n "$pid" ]; then
    pkill -f cloudflared 2>/dev/null
fi
nohup /root/sbox/cloudflared tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol http2 > /root/sbox/argo.log 2>&1 &
sleep 2
echo -e "\e[1;3;33m等待 Cloudflare Argo 生成地址...\e[0m"
sleep 5
echo ""
argo=$(cat /root/sbox/argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
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
                            "uuid": $vmess_uuid
                        }],
                        "transport": {
                            "type": "ws",
                            "path": $ws_path,
                            "early_data_header_name": "Sec-WebSocket-Protocol"
                        }
                    }]')
                    config1=$(echo "$config1" | jq --arg vmess_port "$vmess_port" \
                    --arg vmess_uuid "$vmess_uuid" \
                    --arg ws_path "$ws_path" \
                    '.inbounds += [{
                        "type": "vmess",
                        "tag": "vmess-in",
                        "listen": "::",
                        "listen_port": ($vmess_port | tonumber),
                        "users": [{
                            "uuid": $vmess_uuid
                        }],
                        "transport": {
                            "type": "ws",
                            "path": $ws_path,
                            "early_data_header_name": "Sec-WebSocket-Protocol"
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
read -p $'\e[1;3;33m请输入 Hysteria2 监听端口 (默认端口: 8443)，或输入 y 生成随机端口, 直接回车使用默认端口: \e[0m' hy_listen_port_input
sleep 1
if [[ "$hy_listen_port_input" == "y" || "$hy_listen_port_input" == "Y" ]]; then
    hy_listen_port=$((RANDOM % 55536 + 10000))
    echo -e "\e[1;3;32m自动生成的 Hysteria2 端口: $hy_listen_port\e[0m"
elif [[ "$hy_listen_port_input" =~ ^[0-9]+$ ]] && [ "$hy_listen_port_input" -ge 10000 ] && [ "$hy_listen_port_input" -le 65535 ]; then
    hy_listen_port=$hy_listen_port_input
    echo -e "\e[1;3;32m使用自定义的 Hysteria2 端口: $hy_listen_port\e[0m"
else
    echo -e "\e[1;3;32m使用默认的 Hysteria2 端口: $hy_listen_port\e[0m"
fi
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
                    config1=$(echo "$config1" | jq --arg hy_listen_port "$hy_listen_port" \
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
read -p $'\e[1;3;33m请输入 TUIC 监听端口 (默认端口: 8080)，或输入 y 生成随机端口, 直接回车使用默认端口: \e[0m' tuic_listen_port_input
sleep 1
if [[ "$tuic_listen_port_input" == "y" || "$tuic_listen_port_input" == "Y" ]]; then
    tuic_listen_port=$((RANDOM % 55536 + 10000))
    echo -e "\e[1;3;32m自动生成的 TUIC 端口: $tuic_listen_port\e[0m"
elif [[ "$tuic_listen_port_input" =~ ^[0-9]+$ ]] && [ "$tuic_listen_port_input" -ge 10000 ] && [ "$tuic_listen_port_input" -le 65535 ]; then
    tuic_listen_port=$tuic_listen_port_input
    echo -e "\e[1;3;32m使用自定义的 TUIC 端口: $tuic_listen_port\e[0m"
else
    echo -e "\e[1;3;32m使用默认的 TUIC 端口: $tuic_listen_port\e[0m"
fi
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
            "congestion_control": "bbr",
            "tls": {
                "enabled": true,
                "alpn": ["h3"],
                "certificate_path": "/root/self-cert/cert.pem",
                "key_path": "/root/self-cert/private.key"
            }
        }]')
        config1=$(echo "$config1" | jq --arg tuic_listen_port "$tuic_listen_port" \
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
            "congestion_control": "bbr",
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
    echo "$config" > /root/sbox/sbconfig_server.json
    echo "$config1" > /root/sbox/sbconfig1_server.json
   # echo "配置文件已生成：/root/sbox/sbconfig_server.json"
   # echo "配置文件已生成：/root/sbox/sbconfig1_server.json"
}
#创建sing-box和cloudflare服务文件并启动
setup_services() {
    # 设置路径变量
    SBOX_DIR="/root/sbox"
    CLOUDFLARED_PATH="$SBOX_DIR/cloudflared"
    CONFIG_PATH="$SBOX_DIR/tunnel.yml"
    JSON_PATH="$SBOX_DIR/tunnel.json"
    LOG_PATH="$SBOX_DIR/argo_run.log"
    
    # 直接使用 /root/sbox/sing-box，因为 download_singbox() 已经确保它是用户选择的版本
    SING_BOX_BIN="$SBOX_DIR/sing-box"

    # 获取 sing-box 版本
   if [ -f "$SING_BOX_BIN" ]; then
    SING_BOX_VERSION=$("$SING_BOX_BIN" version 2>/dev/null | head -n1 | grep -oP '\d+\.\d+\.\d+(-[a-zA-Z0-9\.]+)?')
   # echo -e "\e[1;3;32m检测到 sing-box 版本: $SING_BOX_VERSION\e[0m"
else
    echo -e "\e[1;3;31m错误: sing-box 未找到！请先运行 download_singbox()\e[0m"
   exit 1
fi
    # 选择配置文件（按照版本自动适配）
    if [[ "$SING_BOX_VERSION" > "1.10.2" ]]; then
        CONFIG_FILE="$SBOX_DIR/sbconfig1_server.json"
    else
        CONFIG_FILE="$SBOX_DIR/sbconfig_server.json"
    fi
 

    # 获取 vmess 端口（如果有）
    VMESS_PORT=$(jq -r '.inbounds[] | select(.type == "vmess") | .listen_port' "$CONFIG_FILE")

    # **创建 sing-box systemd 服务**
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=$SBOX_DIR
ExecStart=$SING_BOX_BIN run -c $CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    # **如果有 vmess 端口，创建 Cloudflare Tunnel systemd 服务**
    if [ -n "$VMESS_PORT" ] && [ ! -f /etc/systemd/system/cloudflared.service ]; then
        cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'if [ -f "$CONFIG_PATH" ] || [ -f "$JSON_PATH" ]; then $CLOUDFLARED_PATH tunnel --config $CONFIG_PATH run > $LOG_PATH 2>&1; else $CLOUDFLARED_PATH tunnel --url http://localhost:$VMESS_PORT --no-autoupdate --edge-ip-version auto --protocol http2 > $LOG_PATH 2>&1; fi'
Restart=always
RestartSec=5s
User=root
StandardOutput=append:$LOG_PATH
StandardError=append:$LOG_PATH

[Install]
WantedBy=multi-user.target
EOF
    fi

    # **启动 sing-box**
    if $SING_BOX_BIN check -c "$CONFIG_FILE"; then
        echo -e "\e[1;3;33m配置检查成功，正在启动 sing-box...\e[0m"
        systemctl daemon-reload
        systemctl restart sing-box
        systemctl enable sing-box > /dev/null 2>&1

        if systemctl is-active --quiet sing-box; then
            echo -e "\e[1;3;32msing-box-$SING_BOX_VERSION 已成功启动！\e[0m"

            # **如果有 vmess 端口，启动 Cloudflare Tunnel**
            if [ -n "$VMESS_PORT" ]; then
                systemctl restart cloudflared
                systemctl enable cloudflared > /dev/null 2>&1

                if systemctl is-active --quiet cloudflared; then
                    echo -e "\e[1;3;32mCloudflare Tunnel 已成功启动！\e[0m"
                    
                   echo -e "\e[1;35m======================\e[0m"
                else
                    echo -e "\e[1;3;31mCloudflare Tunnel 启动失败！\e[0m"
                    
                      echo -e "\e[1;35m======================\e[0m"
                fi
            fi
        else
            echo -e "\e[1;3;31msing-box 启动失败！\e[0m"
        fi
    else
        echo -e "\e[1;3;31m配置错误，sing-box 未启动！\e[0m"
    fi
}

#重新安装sing-box和cloudflare
reinstall_sing_box() {
    show_notice "将重新安装中..."
    # 停止和禁用 sing-box 服务
    systemctl stop sing-box
    pkill -f sing-box
    systemctl stop cloudflared
    pgrep -f cloudflared
    systemctl disable sing-box > /dev/null 2>&1
    systemctl disable cloudflared > /dev/null 2>&1
    # 删除服务文件和配置文件，先检查是否存在
    [ -f /etc/systemd/system/cloudflared.service ] && rm /etc/systemd/system/cloudflared.service
    [ -f /etc/systemd/system/sing-box.service ] && rm /etc/systemd/system/sing-box.service   
    [ -f /root/sbox/sbconfig_server.json ] && rm /root/sbox/sbconfig_server.json
    [ -f /root/sbox/cloudflared-linux ] && rm /root/sbox/cloudflared-linux
    [ -f /root/sbox/public.key.b64 ] && rm /root/sbox/public.key.b64
    [ -f /root/sbox/argo.txt.b64 ] && rm /root/sbox/argo.txt.b64
    [ -f /root/sbox/sing-box ] && rm /root/sbox/sing-box
    
    # 删除证书和 sbox 目录
    rm -rf /root/self-cert/
    rm -rf /root/sbox/
    # 重新安装的步骤
        mkdir -p "/root/sbox/"
        download_singbox
        download_cloudflared
        install_singbox
        setup_services
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
        if pgrep -f cloudflared > /dev/null; then
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
        if pgrep -f cloudflared > /dev/null; then
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
    sleep 2

    # 读取已安装协议
    protocols=$(jq -r '.inbounds[]?.type' /root/sbox/sbconfig_server.json 2>/dev/null)

    if [ -z "$protocols" ]; then
        echo -e "\e[1;3;31m未检测到任何协议。\e[0m"
        return 1
    fi

    echo -e "\e[1;3;33m已安装协议如下:\e[0m"
    echo -e "\e[1;3;32m$protocols\e[0m"

    # 预设支持的协议列表
    declare -A protocol_funcs=(
        ["vless"]="modify_vless"
        ["vmess"]="modify_vmess"
        ["hysteria2"]="modify_hysteria2"
        ["tuic"]="modify_tuic"
    )

    # 生成可选协议
    options=()
    for proto in "${!protocol_funcs[@]}"; do
        if echo "$protocols" | grep -Eiq "^$proto$"; then
            options+=("$proto")
        fi
    done

    if [ ${#options[@]} -eq 0 ]; then
        echo -e "\e[1;3;31m没有可修改的协议。\e[0m"
        return 1
    fi

    # 显示选项
    echo -e "\e[1;3;33m请选择要修改的协议:\e[0m"
    for i in "${!options[@]}"; do
        echo -e "\e[1;3;32m$((i + 1))) ${options[i]}\e[0m"
    done
    echo -e "\e[1;3;32m$((i + 2))) 全部修改\e[0m"

    # 获取用户输入
    while true; do
        echo -e -n "\e[1;3;33m请输入选项 (可用逗号分隔多个，如 1,2) :\e[0m "
        read -r modify_choice
        IFS=',' read -ra choices <<< "$modify_choice"

        valid=true
        for choice in "${choices[@]}"; do
            if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#options[@]} + 1 )); then
                valid=false
                break
            fi
        done

        if $valid; then
            break
        else
            echo -e "\e[1;3;31m无效选项，请重新输入。\e[0m"
        fi
    done

    # 记录是否修改
    modified=false

    # 执行修改
    for choice in "${choices[@]}"; do
        if [ "$choice" -eq $(( ${#options[@]} + 1 )) ]; then
            echo -e "\e[1;3;33m正在修改所有协议...\e[0m"
            for proto in "${options[@]}"; do
                echo -e "\e[1;3;33m修改 $proto 协议...\e[0m"
                "${protocol_funcs[$proto]}" && modified=true
            done
            break
        else
            proto="${options[$((choice - 1))]}"
            echo -e "\e[1;3;33m修改 $proto 协议...\e[0m"
            "${protocol_funcs[$proto]}" && modified=true
        fi
    done

    # 重新启动服务
    if $modified; then
        echo -e "\e[1;3;33m正在应用新配置...\e[0m"
        setup_services && echo -e "\e[1;3;32m✔ 配置修改成功，sing-box 已重新启动！\e[0m" || {
            echo -e "\e[1;3;31m服务启动失败！请检查日志。\e[0m"
            exit 1
        }
    else
        echo -e "\e[1;3;32m✔ 没有进行任何修改，服务未重启。\e[0m"
    fi
}

# 修改vless协议
modify_vless() {
   VLESS_MODIFIED=false
    show_notice "开始修改 VLESS 配置"
    sleep 2
    VLESS_MODIFIED=true
    # 配置文件列表
    config_files=(
        "/root/sbox/sbconfig_server.json"
        "/root/sbox/sbconfig1_server.json"
    )

    # 获取当前 VLESS 监听端口（从第一个配置文件获取）
    current_listen_port=$(jq -r '.inbounds[] | select(.type == "vless") | .listen_port' "${config_files[0]}")

    if [ -z "$current_listen_port" ]; then
        echo -e "\e[31m未能获取当前 VLESS 端口，请检查配置文件。\e[0m"
        return 1
    fi

    # 让用户输入新的端口（或者自动生成）
    while true; do
        printf "\e[1;3;33m请输入想要修改的 VLESS 端口号 (当前端口为: %s，范围: 1-65535):\e[0m " "$current_listen_port"
        read listen_port  
        sleep 1
        
        # 如果用户没有输入，则自动生成一个 1024-65535 之间的端口
        if [ -z "$listen_port" ]; then
            listen_port=$((RANDOM % 64512 + 1024))  
            echo -e "\e[1;3;32m未输入，已自动生成新的 VLESS 端口: $listen_port\e[0m"
            break
        fi
        
        # 端口号验证
        if [[ "$listen_port" =~ ^[1-9][0-9]{0,4}$ && "$listen_port" -le 65535 ]]; then
            break  # 输入有效，退出循环
        else
            echo -e "\e[31m无效的端口号，请输入范围在 1-65535 之间的数字。\e[0m"
        fi
    done

    echo -e "\e[1;3;32m新的 VLESS 端口: $listen_port\e[0m"
    sleep 1

    # 获取当前服务器名（从第一个配置文件获取）
    current_server_name=$(jq -r '.inbounds[] | select(.type == "vless") | .tls.server_name' "${config_files[0]}")

    if [ -z "$current_server_name" ]; then
        echo -e "\e[31m未能获取当前 VLESS h2 域名，请检查配置文件。\e[0m"
        return 1
    fi

    # 让用户输入新的域名（默认使用当前值）
    printf "\e[1;3;33m请输入想要修改的 VLESS h2 域名 (当前域名为: %s):\e[0m " "$current_server_name"
    read server_name
    server_name=${server_name:-$current_server_name}  
    echo -e "\e[1;3;32m新的 VLESS h2 域名: $server_name\e[0m"
    sleep 1

    # 遍历所有配置文件并更新
    for config_file in "${config_files[@]}"; do
        jq --argjson listen_port "$listen_port" --arg server_name "$server_name" \
           '(.inbounds[] | select(.type == "vless")) |= (.listen_port = $listen_port | .tls.server_name = $server_name)' \
           "$config_file" > "${config_file}.tmp"

        mv "${config_file}.tmp" "$config_file"
    done

    echo -e "\e[1;3;32m=== VLESS 配置修改完成 ===\e[0m"
    echo ""
}

# 修改hysteria2协议
modify_hysteria2() {
    show_notice "开始修改 Hysteria2 配置"
    sleep 2

    # 配置文件列表
    config_files=(
        "/root/sbox/sbconfig_server.json"
        "/root/sbox/sbconfig1_server.json"
    )

    # 获取当前 Hysteria2 监听端口（从第一个配置文件获取）
    hy_current_listen_port=$(jq -r '.inbounds[] | select(.type == "hysteria2") | .listen_port' "${config_files[0]}")

    if [ -z "$hy_current_listen_port" ]; then
        echo -e "\e[31m未能获取当前 Hysteria2 端口，请检查配置文件。\e[0m"
        return 1
    fi

    # 让用户输入新的端口（或者自动生成）
    while true; do
        printf "\e[1;3;33m请输入想要修改的 Hysteria2 端口 (当前端口为: %s，范围: 1-65535):\e[0m " "$hy_current_listen_port"
        read hy_listen_port
        sleep 1

        # 如果用户没有输入，则自动生成一个 1024-65535 之间的端口
        if [ -z "$hy_listen_port" ]; then
            hy_listen_port=$((RANDOM % 64512 + 1024))  
            echo -e "\e[1;3;32m未输入，已自动生成新的 Hysteria2 端口: $hy_listen_port\e[0m"
            break
        fi

        # 端口号验证
        if [[ "$hy_listen_port" =~ ^[1-9][0-9]{0,4}$ && "$hy_listen_port" -le 65535 ]]; then
            break  # 输入有效，退出循环
        else
            echo -e "\e[31m无效的端口号，请输入范围在 1-65535 之间的数字。\e[0m"
        fi
    done

    echo -e "\e[1;3;32m新的 Hysteria2 端口: $hy_listen_port\e[0m"
    sleep 1

    # 遍历所有配置文件并更新
    for config_file in "${config_files[@]}"; do
        jq --argjson hy_listen_port "$hy_listen_port" \
           '(.inbounds[] | select(.type == "hysteria2")) |= (.listen_port = $hy_listen_port)' \
           "$config_file" > "${config_file}.tmp"

        if [ $? -eq 0 ]; then
            mv "${config_file}.tmp" "$config_file"
        else
            echo -e "\e[31m修改 $config_file 失败，检查 JSON 结构。\e[0m"
            rm "${config_file}.tmp"
            return 1
        fi
    done

    echo -e "\e[1;3;32m=== Hysteria2 配置修改完成 ===\e[0m"
    echo ""
}

# 修改tuic协议
modify_tuic() {
    show_notice "开始修改 TUIC 配置"
    sleep 2

    # 配置文件列表
    config_files=(
        "/root/sbox/sbconfig_server.json"
        "/root/sbox/sbconfig1_server.json"
    )

    # 获取当前 TUIC 监听端口（从第一个配置文件获取）
    tuic_current_listen_port=$(jq -r '.inbounds[] | select(.type == "tuic") | .listen_port' "${config_files[0]}")

    if [ -z "$tuic_current_listen_port" ]; then
        echo -e "\e[31m未能获取当前 TUIC 端口，请检查配置文件。\e[0m"
        return 1
    fi

    # 让用户输入新的端口（或者自动生成）
    while true; do
        printf "\e[1;3;33m请输入想要修改的 TUIC 监听端口 (当前端口为: %s，范围: 1-65535):\e[0m " "$tuic_current_listen_port"
        read tuic_listen_port_input

        # 如果用户没有输入，则自动生成一个 1024-65535 之间的端口
        if [ -z "$tuic_listen_port_input" ]; then
            tuic_listen_port=$((RANDOM % 64512 + 1024))
            echo -e "\e[1;3;32m未输入，已自动生成新的 TUIC 端口: $tuic_listen_port\e[0m"
            break
        fi

        # 端口号验证
        if [[ "$tuic_listen_port_input" =~ ^[1-9][0-9]{0,4}$ && "$tuic_listen_port_input" -le 65535 ]]; then
            tuic_listen_port="$tuic_listen_port_input"  # 输入有效，使用用户输入的端口
            break
        else
            echo -e "\e[31m无效的端口号，请输入范围在 1-65535 之间的数字。\e[0m"
        fi
    done

    echo -e "\e[1;3;32m新的 TUIC 端口: $tuic_listen_port\e[0m"
    sleep 1

    # 遍历所有配置文件并更新
    for config_file in "${config_files[@]}"; do
        jq --argjson listen_port "$tuic_listen_port" \
           '(.inbounds[] | select(.type == "tuic")) |= (.listen_port = $listen_port)' \
           "$config_file" > "${config_file}.tmp"

        if [ $? -eq 0 ]; then
            mv "${config_file}.tmp" "$config_file"
        else
            echo -e "\e[31m修改 $config_file 失败，检查 JSON 结构。\e[0m"
            rm "${config_file}.tmp"
            return 1
        fi
    done

    echo -e "\e[1;3;32m=== TUIC 配置修改完成 ===\e[0m"
    echo ""
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
echo -e "\e[1;3;32m6. 更新或切换内核\e[0m"  # 绿色斜体加粗
echo  "==============="
echo -e "\e[1;3;36m7. 手动重启cloudflared\e[0m"  # 青色斜体加粗
echo  "==============="
echo -e "\e[1;3;32m8. 手动重启SingBox服务\e[0m"  # 绿色斜体加粗
echo  "==============="
echo -e "\e[1;3;32m9. 实时查看系统服务状态\e[0m"
echo  "==============="
echo -e "\e[1;3;32m10.切换sing-box内核\e[0m"
echo  "==============="
echo -e "\e[1;3;31m0. 退出脚本\e[0m"  # 红色斜体加粗
echo  "==============="
echo ""
echo -ne "\e[1;3;33m输入您的选择 (0-10):\e[0m"
read -p " " choice
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
        show_client_configuration
        sleep 2
        ;;
    2)
       reinstall_sing_box
        ;;
    3)
       # 主逻辑
       detect_protocols
       # 重启服务并验证
       
           show_client_configuration
        ;;
    4)  
        show_client_configuration
        ;;	
    5)
        uninstall_singbox
        ;;
    6)
        show_notice "正在等待执行..."
        download_singbox
        setup_services
        ;;
    7)
        restart_tunnel
        ;;
    8)       
     restart_singbox
        ;;
    9) 
      check_tunnel_status
      ;;
    10) 
      switch_kernel
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

 
