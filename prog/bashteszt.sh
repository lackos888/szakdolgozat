#!/bin/bash
IF_MAIN=eth0
IF_TUNNEL=tun0
#YOUR_OPENVPN_SUBNET=10.9.8.0/24
YOUR_OPENVPN_SUBNET=10.8.0.0/16 # if using server.conf from sample-server-config
iptables -A FORWARD -i $IF_MAIN -o $IF_TUNNEL -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -s $YOUR_OPENVPN_SUBNET -o $IF_MAIN -j ACCEPT
iptables -t nat -A POSTROUTING -s $YOUR_OPENVPN_SUBNET -o $IF_MAIN -j MASQUERADE
