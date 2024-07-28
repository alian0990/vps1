#!/bin/bash

#
# Hysteria one-click installation script
# https://github.com/evozi/hysteria-install
#

export LANG=en_US.UTF-8

DEFAULT_SNI="www.bing.com"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN='\033[0m'

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f")

[[ $EUID -ne 0 ]] && red "Note: Please run the script under the root user" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
    fi
done

[[ -z $SYSTEM ]] && red "Does not support the current VPS system, please use the mainstream operating system" && exit 1

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

APP_IMPORT_GUIDE="Open 'HTTP Injector' app -> Tunnel Type set 'Hysteria' -> Settings -> Hysteria -> Paste Hysteria config URI to import"

realIp(){
    ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k)
}

realHost(){
    hy_host=$(curl -s4m8 ip.sb -k) || hy_host=$(curl -s6m8 ip.sb -k)
}

inst_cert(){
    green "Methods of applying certificate ："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Self-signed certificate ${YELLOW} (default) ${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} ACME script auto-apply"
    echo -e " ${GREEN}3.${PLAIN} Custom Certificate Path"
    echo ""
    read -rp "Please enter options [1-3]: " certInput
    if [[ $certInput == 2 ]]; then
        cert_path="/root/cert.crt"
        key_path="/root/private.key"

        chmod -R 777 /root # Let the Hysteria main program access the /root directory

        if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
            sni_host=$(cat /root/ca.log)
            green "Legacy domain name detected: certificate for $sni_host, applying"
            hy_host=$sni_host
        else
            WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
                wg-quick down wgcf >/dev/null 2>&1
                systemctl stop warp-go >/dev/null 2>&1
                realIp
                wg-quick up wgcf >/dev/null 2>&1
                systemctl start warp-go >/dev/null 2>&1
            else
                realIp
            fi
            
            read -p "Please enter the domain name to apply for a certificate：" sni_host
            [[ -z $sni_host ]] && red "No domain name entered, unable to perform operation！" && exit 1
            green "Domain name entered：$sni_host" && sleep 1
            domainIP=$(curl -sm8 ipget.net/?ip="${sni_host}")
            if [[ $domainIP == $ip ]]; then
                ${PACKAGE_INSTALL[int]} curl wget sudo socat openssl
                if [[ $SYSTEM == "CentOS" ]]; then
                    ${PACKAGE_INSTALL[int]} cronie
                    systemctl start crond
                    systemctl enable crond
                else
                    ${PACKAGE_INSTALL[int]} cron
                    systemctl start cron
                    systemctl enable cron
                fi
                curl https://get.acme.sh | sh -s email=$(date +%s%N | md5sum | cut -c 1-16)@gmail.com
                source ~/.bashrc
                bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
                bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                if [[ -n $(echo $ip | grep ":") ]]; then
                    bash ~/.acme.sh/acme.sh --issue -d ${sni_host} --standalone -k ec-256 --listen-v6 --insecure
                else
                    bash ~/.acme.sh/acme.sh --issue -d ${sni_host} --standalone -k ec-256 --insecure
                fi
                bash ~/.acme.sh/acme.sh --install-cert -d ${sni_host} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
                if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]]; then
                    echo $sni_host > /root/ca.log
                    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
                    echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
                    green "Successful! The certificate (cer.crt) and private key (private.key) files applied by the script have been saved to the /root folder"
                    yellow "The certificate crt file path is as follows: /root/cert.crt"
                    yellow "The private key file path is as follows: /root/private.key"
                    hy_host=$sni_host
                fi
            else
                red "The IP resolved by the current domain name does not match the real IP used by the current VPS"
                green "suggestions below:"
                yellow "1. Please make sure CloudFlare is turned off (DNS only), other domain name resolution or CDN website settings are the same"
                yellow "2. Please check whether the IP set by the DNS resolution is the real IP of the VPS"
                yellow "3. The script may not keep up with the times, it is recommended to post screenshots to GitHub Issues, or TG groups for inquiries"
                exit 1
            fi
        fi
    elif [[ $certInput == 3 ]]; then
        read -p "Please enter the path of the public key file crt: " cert_path
        yellow "The path of the public key file crt: $cert_path"
        read -p "Please enter the path of the key file key: " key_path
        yellow "The path of the key file key: $key_path"
        read -p "Please enter the domain name of the certificate: " sni_host
        yellow "Certificate domain name: $sni_host"
        hy_host=$sni_host
    else
        inst_sni
        green "will use $sni_host self-signed certificates for Hysteria"

        cert_path="/etc/hysteria/cert.crt"
        key_path="/etc/hysteria/private.key"
        openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
        openssl req -new -x509 -days 36500 -key /etc/hysteria/private.key -out /etc/hysteria/cert.crt -subj "/CN=$sni_host"
        chmod 777 /etc/hysteria/cert.crt
        chmod 777 /etc/hysteria/private.key
        hy_host=$sni_host
    fi
}

inst_protocol(){
    green "The Hysteria server protocol is as follows:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} UDP ${YELLOW}(default)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} wechat-video"
    echo -e " ${GREEN}3.${PLAIN} faketcp"
    echo ""
    read -rp "Please enter options [1-3]: " proInput
    if [[ $proInput == 2 ]]; then
        protocol="wechat-video"
    elif [[ $proInput == 3 ]]; then
        protocol="faketcp"
    else
        protocol="udp"
    fi
    yellow "Will use $protocol as Hysteria's server protocol"
}

inst_port(){
    read -p "Set the Hysteria port [1-65535] (Enter will randomly assign the port): " port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} The port is already occupied by another program, please change the port and try again!  "
            read -p "Set the Hysteria port [1-65535] (Enter will randomly assign the port): " port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    delPortHoppingNat

    green "The port that will be used on the Hysteria server is: $port"

    if [[ $protocol == "udp" ]]; then
        inst_jump
    fi
}

delPortHoppingNat(){
    iptables -t nat -F PREROUTING  2>/dev/null
    ip6tables -t nat -F PREROUTING  2>/dev/null
    if systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        netfilter-persistent save 2> /dev/null
    fi
}

inst_jump(){
    yellow "The protocol you currently choose is UDP, which supports port hopping function"
    green "The Hysteria port usage pattern is as follows: "
    echo ""
    echo -e " ${GREEN}1.${PLAIN} single port ${YELLOW} (default) ${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} port hopping"
    echo ""
    read -rp "Please enter options [1-2]: " jumpInput
    if [[ $jumpInput == 2 ]]; then
        read -p "Set the starting port of the range port (recommended between 10000-65535)：" firstport
        read -p "Set the end port of a range port (recommended between 10000-65535, must be larger than the start port above)：" endport

        firstport="${firstport:=10000}"
        endport="${endport:=65535}"

        if [[ $firstport -ge $endport ]]; then
            until [[ $firstport -le $endport ]]; do
                if [[ $firstport -ge $endport ]]; then
                    red "The start port you set is less than the end port, please re-enter the start and end port"
                    read -p "Set the starting port of the range port (recommended between 10000-65535): " firstport
                    read -p "Set the end port of a range port (recommended between 10000-65535, must be larger than the start port above):" endport
                fi
            done
        fi
        delPortHoppingNat
        iptables -t nat -A PREROUTING -p udp --dport $firstport:$endport -m comment --comment "NAT $firstport:$endport to $port (PortHopping-hysteria)" -j DNAT --to-destination :$port
        ip6tables -t nat -A PREROUTING -p udp --dport $firstport:$endport -m comment --comment "NAT $firstport:$endport to $port (PortHopping-hysteria)" -j DNAT --to-destination :$port
        if systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
            netfilter-persistent save >/dev/null 2>&1
        else 
            red "netfilter-persistent not enabled, PortHopping forwarding rules cannot be persisted and will fail after restarting the system. Please manually execute netfilter-persistent save. Continuing to execute the script will not affect subsequent configurations..."
        fi
    else
        red "Will continue to use single port mode"
    fi
}


inst_verification(){
    input_verification

    if [[ $encryptionType == 2 ]]; then
        inst_pwd
    else
        inst_obfs
    fi
}

input_verification(){
    green "Select Hysteria verification method:"
    yellow "Tips: If you use obfuscation encryption, the anti-blocking ability is better and can be identified as unknown UDP traffic, but it will increase the CPU load and cause the peak speed to decrease. If you are pursuing performance and are not blocked, it is not recommended to use Obfs."
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Obfuscation (obfs+auth_str) ${YELLOW} (default) ${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} Authentication password (auth_str)"
    echo ""
    read -rp "Please enter options [1-2]: " encryptionType
}

inst_obfs(){
    read -p "Set Hysteria obfuscation password (Enter for random password) :  " obfs_pwd
    [[ -z $obfs_pwd ]] && obfs_pwd=$(date +%s%N | md5sum | cut -c 1-16)
    yellow "The obfs password used on the Hysteria server is: $obfs_pwd"
    auth_pwd=$obfs_pwd
}

inst_pwd(){
    read -p "Set Hysteria authentication password (Enter for random password) :  " auth_pwd
    [[ -z $auth_pwd ]] && auth_pwd=$(date +%s%N | md5sum | cut -c 1-16)
    yellow "The auth password used on the Hysteria server is: $auth_pwd"
    obfs_pwd=""
}

inst_speed(){
    read -p "Enter your download speed (Mbps) (default: 100): " down_mbps
    read -p "Enter your upload speed (Mbps) (default: 50): " up_mbps
    down_mbps="${down_mbps:=100}"
    up_mbps="${up_mbps:=50}"
}

inst_sni(){
    read -p "Enter your SNI (Default: $DEFAULT_SNI) : " sni_host
    sni_host="${sni_host:=$DEFAULT_SNI}"
}

inst_resolv(){
    green "The Hysteria domain name resolution mode is as follows:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} IPv4 priority ${YELLOW}(default)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} IPv6 priority"
    echo ""
    read -rp "Please enter options [1-2]: " resolvInput
    if [[ $resolvInput == 2 ]]; then
        yellow "Hysteria name resolution mode has been set to IPv6 first"
        resolv=64
    else
        yellow "Hysteria name resolution mode has been set to IPv4 first"
        resolv=46
    fi
}

installHysteria(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo qrencode procps iptables-persistent netfilter-persistent

    wget -N https://raw.githubusercontent.com/evozi/hysteria-install/main/hy1/install_server.sh
    bash install_server.sh
    rm -f install_server.sh

    if [[ -f "/usr/local/bin/hysteria1" ]]; then
        green "Hysteria installed successfully!  "
    else
        red "Hysteria installation failed!  "
        exit 1
    fi

    # Ask user for Hysteria configuration
    inst_cert
    inst_protocol
    inst_port
    inst_verification
    inst_speed
    inst_resolv

    # Setting up the Hysteria configuration file
    cat <<EOF > /etc/hysteria/config.json
{
    "protocol": "$protocol",
    "listen": ":$port",
    "resolve_preference": "$resolv",
    "cert": "$cert_path",
    "key": "$key_path",
    "alpn": "h3",
    "obfs": "$obfs_pwd",
    "auth": {
        "mode": "password",
        "config": {
            "password": "${auth_pwd}"
        }
    }
}
EOF

    # Determine the final inbound port range
    if [[ -n $firstport ]]; then
        last_port="$port,$firstport-$endport"
    else
        last_port=$port
    fi

    # Add brackets to the IPv6 address
    if [[ -n $(echo $ip | grep ":") ]]; then
        last_ip="[$ip]"
    else
        last_ip=$ip
    fi

    # Determine whether the certificate is self-signed, if so, use the IP as the server inbound
    if [[ $hy_host == $sni_host ]]; then
        WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
            wg-quick down wgcf >/dev/null 2>&1
            systemctl stop warp-go >/dev/null 2>&1
            realHost
            wg-quick up wgcf >/dev/null 2>&1
            systemctl start warp-go >/dev/null 2>&1
        else
            realHost
        fi
    fi

    # Set up V2ray and Clash Meta configuration files
    mkdir /root/hy >/dev/null 2>&1
    cat <<EOF > /root/hy/hy-client.json
{
    "protocol": "$protocol",
    "server": "$hy_host:$last_port",
    "server_name": "$sni_host",
    "alpn": "h3",
    "up_mbps": "$up_mbps",
    "down_mbps": "$down_mbps",
    "auth_str": "$auth_pwd",
    "obfs": "$obfs_pwd",
    "insecure": true,
    "retry": 3,
    "retry_interval": 3,
    "fast_open": true,
    "lazy_start": true,
    "hop_interval": 60,
    "socks5": {
        "listen": "127.0.0.1:5080"
    }
}
EOF

    cat <<EOF > /root/hy/clash-meta.yaml
mixed-port: 7890
external-controller: 127.0.0.1:9090
allow-lan: false
mode: rule
log-level: debug
ipv6: true
dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 8.8.8.8
    - 1.1.1.1
    - 114.114.114.114
proxies:
  - name: HttpInjector-Hysteria1
    type: hysteria
    server: $hy_host
    port: $port
    auth_str: $auth_pwd
    obfs: $obfs_pwd
    alpn:
      - h3
    protocol: $protocol
    up: $up_mbps
    down: $down_mbps
    sni: $sni_host
    skip-cert-verify: true
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - HttpInjector-Hysteria1

rules:
  - DOMAIN-SUFFIX,speedtest.net,DIRECT
  - DOMAIN-SUFFIX,fast.com,DIRECT
  - DOMAIN-SUFFIX,speed.cloudflare.com,DIRECT
  - DOMAIN-SUFFIX,ir,DIRECT
  - DOMAIN-SUFFIX,cn,DIRECT
  - GEOIP,IR,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF
    url="hysteria://$hy_host:$last_port?protocol=$protocol&upmbps=$up_mbps&downmbps=$down_mbps&auth=$auth_pwd&obfsParam=$obfs_pwd&peer=$sni_host&insecure=1&alpn=h3#HttpInjector-Hysteria1"
    echo $url > /root/hy/url.txt

    systemctl daemon-reload
    systemctl enable hysteria1-server
    systemctl start hysteria1-server

    if [[ -n $(systemctl status hysteria1-server 2>/dev/null | grep -w active) && -f '/etc/hysteria/config.json' ]]; then
        green "Hysteria service started successfully"
    else
        red "The Hysteria1-server service failed to start, please run systemctl status hysteria1-server to view the service status and give feedback, the script exits" && exit 1
    fi
    red "======================================================================================"
    green "Hysteria proxy service installation complete"
    #yellow "The content of the client configuration file hy-client.json is as follows and saved to /root/hy/hy-client.json"
    #cat /root/hy/hy-client.json
    #yellow "Clash Meta client configuration file saved to /root/hy/clash-meta.yaml"
    green "$APP_IMPORT_GUIDE"
    yellow "Hysteria config URI is as follows and saved to /root/hy/url.txt"
    red $(cat /root/hy/url.txt)
}

uninstallHysteria(){
    systemctl stop hysteria1-server.service >/dev/null 2>&1
    systemctl disable hysteria1-server.service >/dev/null 2>&1
    rm -f /etc/systemd/system/hysteria1-server.service /etc/systemd/system/hysteria1-server@.service
    rm -rf /usr/local/bin/hysteria1 /etc/hysteria /root/hy /root/hysteria1.sh
    sed -i '/systemctl restart hysteria1-server/d' /etc/crontab
    delPortHoppingNat

    green "Hysteria 1 has been completely uninstalled!  "
}

startHysteria(){
    systemctl start hysteria1-server
    systemctl enable hysteria1-server >/dev/null 2>&1
}

stopHysteria(){
    systemctl stop hysteria1-server
    systemctl disable hysteria1-server >/dev/null 2>&1
}

switchHysteria(){
    yellow "Please select the operation you need:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Start Hysteria 1"
    echo -e " ${GREEN}2.${PLAIN} Stop Hysteria 1"
    echo -e " ${GREEN}3.${PLAIN} Restart Hysteria 1"
    echo ""
    read -rp "Please enter options [0-3]: " switchInput
    case $switchInput in
        1 ) startHysteria ;;
        2 ) stopHysteria ;;
        3 ) stopHysteria && startHysteria ;;
        * ) exit 1 ;;
    esac
}

change_cert(){
    old_cert=$(cat /etc/hysteria/config.json | grep cert | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    old_key=$(cat /etc/hysteria/config.json | grep key | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    old_hy_host=$(cat /root/hy/hy-client.json | grep server\" | sed -n 1p | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g" | awk -F ":" '{print $1}')
    old_sni_host=$(cat /root/hy/hy-client.json | grep server_name | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    inst_cert
    if [[ $hy_host == $sni_host ]]; then
        WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
            wg-quick down wgcf >/dev/null 2>&1
            systemctl stop warp-go >/dev/null 2>&1
            realIp
            hy_host=$ip
            wg-quick up wgcf >/dev/null 2>&1
            systemctl start warp-go >/dev/null 2>&1
        else
            realIp
            hy_host=$ip
        fi
    fi
    sed -i "s|$old_cert|$cert_path|" /etc/hysteria/config.json
    sed -i "s|$old_key|$key_path|" /etc/hysteria/config.json

    sed -i "s|$old_hy_host|$hy_host|" /root/hy/hy-client.json
    sed -i "s|$old_hy_host|$hy_host|" /root/hy/clash-meta.yaml
    sed -i "s|$old_hy_host|$hy_host|" /root/hy/url.txt

    sed -i "s|$old_sni_host|$sni_host|" /root/hy/hy-client.json
    sed -i "s|$old_sni_host|$sni_host|" /root/hy/clash-meta.yaml
    sed -i "s|$old_sni_host|$sni_host|" /root/hy/url.txt

    stopHysteria && startHysteria

    green "The configuration is modified successfully, please re-import the client configuration file"
}

change_protocol(){
    old_pro=$(cat /etc/hysteria/config.json | grep protocol | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    inst_protocol
    sed -i "s/$old_pro/$protocol/" /etc/hysteria/config.json
    sed -i "s/$old_pro/$protocol/" /root/hy/hy-client.json
    sed -i "s/$old_pro/$protocol/" /root/hy/clash-meta.yaml
    sed -i "s/$old_pro/$protocol/" /root/hy/url.txt
    stopHysteria && startHysteria
    green "The configuration is modified successfully, please re-import the client configuration file"
}

change_port(){
    old_port=$(cat /etc/hysteria/config.json | grep listen | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g" | sed "s/://g")
    inst_port

    if [[ -n $firstport ]]; then
        last_port="$port,$firstport-$endport"
    else
        last_port=$port
    fi

    sed -i "s/$old_port/$port/" /etc/hysteria/config.json
    sed -i "s/$old_port/$last_port/" /root/hy/hy-client.json
    sed -i "s/$old_port/$last_port/" /root/hy/clash-meta.yaml
    sed -i "s/$old_port/$last_port/" /root/hy/url.txt

    stopHysteria && startHysteria
    green "The configuration is modified successfully, please re-import the client configuration file"
}

change_verification(){
    input_verification

    if [[ $encryptionType == 2 ]]; then
        change_pwd
    else
        change_obfs
    fi
}

change_obfs(){
    old_pwd=$(cat /etc/hysteria/config.json | grep password | sed -n 2p | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    inst_obfs
    sed -i "s/\"obfs\": \"\"/\"obfs\": \"$obfs_pwd\"/" /etc/hysteria/config.json
    sed -i "s/\"obfs\": \"\"/\"obfs\": \"$obfs_pwd\"/" /root/hy/hy-client.json
    sed -i "s/obfs: /obfs: $obfs_pwd/" /root/hy/clash-meta.yaml
    sed -i "s/obfsParam=/obfsParam=$obfs_pwd/" /root/hy/url.txt

    sed -i "s/\"obfs\": \"$old_pwd\"/\"obfs\": \"$obfs_pwd\"/" /etc/hysteria/config.json
    sed -i "s/\"obfs\": \"$old_pwd\"/\"obfs\": \"$obfs_pwd\"/" /root/hy/hy-client.json
    sed -i "s/obfs: $old_pwd/obfs: $obfs_pwd/" /root/hy/clash-meta.yaml
    sed -i "s/obfsParam=$old_pwd/obfsParam=$obfs_pwd/" /root/hy/url.txt

    sed -i "s/$old_pwd/$auth_pwd/" /etc/hysteria/config.json
    sed -i "s/$old_pwd/$auth_pwd/" /root/hy/hy-client.json
    sed -i "s/$old_pwd/$auth_pwd/" /root/hy/clash-meta.yaml
    sed -i "s/$old_pwd/$auth_pwd/" /root/hy/url.txt

    stopHysteria && startHysteria

    green "The configuration is modified successfully, please re-import the client configuration file"
}

change_pwd(){
    old_pwd=$(cat /etc/hysteria/config.json | grep password | sed -n 2p | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    inst_pwd
    sed -i "s/\"obfs\": \"$old_pwd\"/\"obfs\": \"\"/" /etc/hysteria/config.json
    sed -i "s/\"obfs\": \"$old_pwd\"/\"obfs\": \"\"/" /root/hy/hy-client.json
    sed -i "s/obfs: $old_pwd/obfs: /" /root/hy/clash-meta.yaml
    sed -i "s/obfsParam=$old_pwd/obfsParam=/" /root/hy/url.txt

    sed -i "s/$old_pwd/$auth_pwd/" /etc/hysteria/config.json
    sed -i "s/$old_pwd/$auth_pwd/" /root/hy/hy-client.json
    sed -i "s/$old_pwd/$auth_pwd/" /root/hy/clash-meta.yaml
    sed -i "s/$old_pwd/$auth_pwd/" /root/hy/url.txt

    stopHysteria && startHysteria

    green "The configuration is modified successfully, please re-import the client configuration file"
}

change_resolv(){
    old_resolv=$(cat /etc/hysteria/config.json | grep resolv | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    inst_resolv
    sed -i "s/$old_resolv/$resolv/" /etc/hysteria/config.json
    stopHysteria && startHysteria
    green "The configuration is modified successfully, please re-import the client configuration file"
}

changeConf(){
    green "The Hysteria configuration change options are as follows:"
    echo -e " ${GREEN}1.${PLAIN} Modify certificate type"
    echo -e " ${GREEN}2.${PLAIN} Modify the transport protocol"
    echo -e " ${GREEN}3.${PLAIN} Modify connection port"
    echo -e " ${GREEN}4.${PLAIN} Modify verification method (obfs password/auth password)"
    echo -e " ${GREEN}5.${PLAIN} Modify domain name resolution priority"
    echo ""
    read -p " Please select an action [1-5]：" confAnswer
    case $confAnswer in
        1 ) change_cert ;;
        2 ) change_protocol ;;
        3 ) change_port ;;
        4 ) change_verification ;;
        5 ) change_resolv ;;
        * ) exit 1 ;;
    esac
}

showConf(){
    #yellow "Hysteria client JSON configuration file hy-client.json is as follows and saved to /root/hy/hy-client.json"
    #cat /root/hy/hy-client.json
    green "$APP_IMPORT_GUIDE"
    #yellow "Clash Meta client configuration file saved to /root/hy/clash-meta.yaml"
    yellow "Hysteria config URI is as follows and saved to /root/hy/url.txt"
    red $(cat /root/hy/url.txt)
}

updateCore(){
    wget -N https://raw.githubusercontent.com/evozi/hysteria-install/main/hy1/install_server.sh
    bash install_server.sh
    rm -f install_server.sh
}

showLog(){
    echo -e "${GREEN}Hysteria log, Ctrl+C to exit:${PLAIN}"
    journalctl --no-pager -e -u hysteria1-server.service --output cat -f
}

menu() {
    clear
    echo "###############################################################################"
    echo -e "#         ⚡ ${YELLOW}Hysteria (ver 1) || one-click installation script || ${PLAIN}             #"
    echo -e "# ${RED}https://github.com/evozi/hysteria-install${PLAIN}                                   #"
    echo -e "# ${GREEN}Maintained By ${PLAIN}: Evozi                                                       #"
    echo -e "# ${GREEN}By ${PLAIN}: Author: Misaka-blog | Forked: Ptechgithub                              #"                                     #"
    echo -e "#                                                                             #"
    echo -e "# ${GREEN}Android ${PLAIN}: https://play.google.com/store/apps/details?id=com.evozi.injector  #"
    echo -e "# ${GREEN}iOS ${PLAIN}: https://apps.apple.com/us/app/http-injector/id1659992827              #"
    echo "###############################################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Install Hysteria 1"
    echo -e " ${GREEN}2.${PLAIN} ${RED}Uninstall Hysteria 1${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} Start/Stop/Restart"
    echo -e " ${GREEN}4.${PLAIN} Change configuration"
    echo -e " ${GREEN}5.${PLAIN} Show configuration file"
    echo " -------------"
    echo -e " ${GREEN}6.${PLAIN} Update Hysteria 1 core"
    echo -e " ${GREEN}7.${PLAIN} Show Hysteria 1 log"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} Exit script"
    echo ""
    read -rp "Please enter options [0-7]: " menuInput
    case $menuInput in
        1 ) installHysteria ;;
        2 ) uninstallHysteria ;;
        3 ) switchHysteria ;;
        4 ) changeConf ;;
        5 ) showConf ;;
        6 ) updateCore ;;
        7 ) showLog ;;
        * ) exit 1 ;;
    esac
}

menu