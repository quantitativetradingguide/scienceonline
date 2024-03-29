#!/bin/bash
# Author
# original author:https://github.com/backendprogramming
# modified by:jack xu

#To set up the VPN client, first install the following packages:
COLOR_ERROR="\e[38;5;198m"
COLOR_NONE="\e[0m"
COLOR_SUCC="\e[92m"
install_ipsec_l2tp(){
    transfer_to_root
    apt-get update
    apt-get install strongswan xl2tpd net-tools
}

config_ipsec_l2tp() {
    #Create VPN variables (replace with actual values):
    #VPN_SERVER_IP='your_vpn_server_ip'
    #VPN_IPSEC_PSK='your_ipsec_pre_shared_key'
    #VPN_USER='your_vpn_username'
    #VPN_PASSWORD='your_vpn_password'
    read -p "Please input your server ip：" VPN_SERVER_IP
    read -p "Please input your ipsec psk：" VPN_IPSEC_PSK
    read -p "Please input your user：" VPN_USER
    read -p "Please input your password：" VPN_PASSWORD


    #Configure strongSwan
    cat > /etc/ipsec.conf <<EOF
    # ipsec.conf - strongSwan IPsec configuration file

    conn myvpn
      auto=add
      keyexchange=ikev1
      authby=secret
      type=transport
      left=%defaultroute
      leftprotoport=udp/l2tp
      rightprotoport=udp/l2tp
      right="$VPN_SERVER_IP"
      rightid=%any
      keyingtries=%forever
      ike=aes128-sha1-modp2048
      esp=aes128-sha1
EOF
    cat > /etc/ipsec.secrets <<EOF
    : PSK "$VPN_IPSEC_PSK"
EOF
    chmod 600 /etc/ipsec.secrets

    #Configure xl2tpd
    cat > /etc/xl2tpd/xl2tpd.conf <<EOF
    [lac myvpn]
    lns = "$VPN_SERVER_IP"
    ppp debug = yes
    pppoptfile = /etc/ppp/options.l2tpd.client
    length bit = yes
EOF

    cat > /etc/ppp/options.l2tpd.client <<EOF
    ipcp-accept-local
    ipcp-accept-remote
    refuse-eap
    require-chap
    noccp
    noauth
    mtu 1280
    mru 1280
    noipdefault
    defaultroute
    usepeerdns
    connect-delay 5000
    name "$VPN_USER"
    password "$VPN_PASSWORD"
EOF

    sudo chmod 600 /etc/ppp/options.l2tpd.client
}
start_ipsec_start_l2tp(){
    local_default_ip=$(/sbin/ip route | awk '/default/ { print $3 }')
    local_client_ip=$(wget -qO- http://ipv4.icanhazip.com; echo)
    #Create xl2tpd control file:
    sudo mkdir -p /var/run/xl2tpd
    sudo sudo touch /var/run/xl2tpd/l2tp-control

    #Restart services:
    sudo service strongswan-starter restart
    sudo service xl2tpd restart

    #Start the IPsec connection:
    sudo ipsec up myvpn

    #Start the L2TP connection:
    sudo echo "c myvpn" > /var/run/xl2tpd/l2tp-control

   read -p "Please input your proxy server ip：" VPN_SERVER_IP
    sudo route add default dev ppp0
    sudo route add "$VPN_SERVER_IP" gw "$local_default_ip"

    echo -e "if your VPN client is a remote server,\n"
    echo -e "you must also exclude your Local PC's public IP from the new default route,\n"
    echo -e "to prevent your SSH session from being disconnected ？[Y/n]："
    read  judge

    if  [ "$judge" = "Y" ]
    then
    sudo route add "$local_client_ip" gw "$local_default_ip"
    fi

    echo "now should display proxy ip:"
    sudo wget -qO- http://ipv4.icanhazip.com; echo
}

stop_ipsec_stop_l2tp(){
    route del default dev ppp0
    echo "d myvpn" > /var/run/xl2tpd/l2tp-control
    service strongswan-starter stop
    service xl2tpd stop
}

start_https_proxy(){
    read -p "Please use source ubuntu_client_terminal.sh？[Y/n]：" judge

    if  [ "$judge" = "Y" ]
    then
        read -p "Please input host url：" DOMAIN
        read -p "Please input user name：" USER
        read -s -p "Please input password：" PASS
        read -p "Please input host port：" PORT
        export all_proxy=https://"$USER":"$PASS"@"$DOMAIN":"$PORT"
        return
    fi
}

stop_https_proxy(){
    read -p "Please use source ubuntu_client_terminal.sh？[Y/n]：" judge

    if [ "$judge" = "Y" ]
    then
        echo "unset all_proxy"
        unset all_proxy
        return
    fi
}
transfer_to_root() {
    if [ "$USER" != "root" ]
    then
        echo -e "Please first transfer to root user ,input shell command:su - or sudo -i\n"
        echo -e "input shell command:cd $PWD\n"
        exit
    fi
}
init(){
    VERSION_CURR=$(uname -r | awk -F '-' '{print $1}')
    VERSION_MIN="4.9.0"

    OIFS=$IFS  # Save the current IFS (Internal Field Separator)
    IFS=','    # New IFS

    COLUMNS=50

    #su -
    while [ 1 == 1 ]
    do
        echo -e "\nMenu Options\n"
        PS3="Please select a option:"
        re='^[0-9]+$'
        select opt in "install ipsec and l2tp" \
                    "config ipsec and l2tp" \
                    "start ipsec,start l2tp,myvpn" \
                    "stop ipsec,stop l2tp" \
                    "start https proxy" \
                    "stop https proxy" \
                    "exit" ; do

            if ! [[ $REPLY =~ $re ]] ; then
                echo -e "${COLOR_ERROR}Invalid option. Please input a number.${COLOR_NONE}"
                break;
             elif (( REPLY == 1 )) ; then
                install_ipsec_l2tp
                break;
               elif (( REPLY == 2 )) ; then
                config_ipsec_l2tp
                break;
            elif (( REPLY == 3 )) ; then
                start_ipsec_start_l2tp
                break;
            elif (( REPLY == 4 )) ; then
                stop_ipsec_stop_l2tp
                break
             elif (( REPLY == 5 )) ; then
                start_https_proxy
                break
             elif (( REPLY == 6 )) ; then
                stop_https_proxy
                break
            elif (( REPLY == 7 )) ; then
                exit
            else
                echo -e "${COLOR_ERROR}Invalid option. Try another one.${COLOR_NONE}"
            fi
        done
    done

     IFS=$OIFS  # Restore the IFS
}

init
