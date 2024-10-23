#!/usr/bin/env bash

echo "CLEARING all previous IPTABLES RULES | In case you use custom IPTABLES rules"
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -F
sudo iptables -X

echo "CLEARING all previous IP6TABLES RULES | In case you use custom IP6TABLES rules"
sudo ip6tables -P INPUT ACCEPT
sudo ip6tables -P FORWARD ACCEPT
sudo ip6tables -P OUTPUT ACCEPT
sudo ip6tables -t nat -F
sudo ip6tables -t mangle -F
sudo ip6tables -F
sudo ip6tables -X