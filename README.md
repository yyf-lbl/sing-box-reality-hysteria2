# sing-Box-reality-hysteria2
One click reality and hysteria2 installer on sing-box core

## Features

- Easy installation and configuration
- No need for a domain name, just use a self-signed certificate to sign any domain.
- Ability to choose the desired reality port and SNI
- Ability to choose the desired hysteria2 port
- Real easy to use for the end-users

## Prerequisites

- Linux operating system
- Bash shell
- Internet connection

## Usage

To use sing-REALITY-box, simply execute the following command on your Linux machine:
Also updating the repo's is highly recommended (apt update && apt upgrade)
- This script uses JQ which will be automaticaly installed
- This script uses 443 as the default port number . change it if you want when the script asks you to.
- this script uses "itunes.apple.com" as the SNI . change it to your desired SNI when the script asks you to.

```bash
bash <(curl -fsSL https://github.com/vveg26/sing-box-reality-hysteria2/raw/main/install.sh)
```
|项目||
|:--|:--|
|程序|**/root/sing-box**|
|服务端配置|**/root/sbconfig_server.json**|
|客户端配置|**/root/sbconfig_client.json**|
|重启|`systemctl restart sing-box`|
|状态|`systemctl status sing-box`|
|查看日志|`journalctl -u sing-box -o cat -e`|
|实时日志|`journalctl -u sing-box -o cat -f`|

## Credit
- [sing-reality-box](https://github.com/deathline94/sing-REALITY-Box)
- [sing-box](https://github.com/SagerNet/sing-box)
