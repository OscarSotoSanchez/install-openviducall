#!/usr/bin/env bash

while [ -z $public_ip ]; do
        read -p "Please enter yout machine public ip: " public_ip
done

# Create Openvidu user
useradd openvidu

# Install KMS
echo "deb [arch=amd64] http://ubuntu.openvidu.io/6.13.0 xenial kms6" | sudo tee /etc/apt/sources.list.d/kurento.list
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 5AFA7A83
apt-get update
apt-get -y install kurento-media-server

# Modify kurento-media-server
sudo sed -i "s/DAEMON_USER=\"kurento\"/DAEMON_USER=\"openvidu\"/g" /etc/default/kurento-media-server

# Install COTURN
apt-get -y install coturn

# Install Redis
apt-get -y install redis-server

# Modify WebRtcEndpoint.conf.ini file
sed -r 's/;externalAddress=.*/externalAddress=192.168.1.3/' /etc/kurento/modules/kurento/WebRtcEndpoint.conf.ini

# Modify turnserver.conf file
sed -r 's/#external-ip=.*/external-ip=192.168.1.3/' /etc/turnserver.conf
sed -r 's/#listening-port=.*/listening-port=3478/' /etc/turnserver.conf
sed -r 's/#fingerprint/fingerprint/' /etc/turnserver.conf
sed -r 's/#lt-cred-mech/lt-cred-mech/' /etc/turnserver.conf
sed -r 's/#max-port=.*/max-port=65535/' /etc/turnserver.conf
sed -r 's/#min-port=.*/min-port=40000/' /etc/turnserver.conf
sed -r 's/#pidfile=.*/pidfile="/var/run/turnserver.pid"/' /etc/turnserver.conf
sed -r 's/#realm=.*/realm=openvidu/' /etc/turnserver.conf
sed -r 's/#simple-log/simple-log/' /etc/turnserver.conf
sed -r 's/#redis-userdb=.*/redis-userdb="ip=127.0.0.1 dbname=0 password=turn connect_timeout=30"/' /etc/turnserver.conf
sed -r 's/#verbose/verbose/' /etc/turnserver.conf

# Modify coturn file
sed 's/#TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn

# Restart services
service redis-server restart
service coturn restart
service kurento-media-server restar

# Install Java 8
apt-get install -y openjdk-8-jre

# Install Openvidu
last_openvidu_release=$(wget -q https://github.com/OpenVidu/openvidu/releases/latest -O - | grep -E \/tag\/ | awk -F "[><]" '{print $3}' | sed ':a;N;$!ba;s/\n//g' | sed 's/v//')
wget "https://github.com/OpenVidu/openvidu/releases/download/v${last_openvidu_release}/openvidu-server-${last_openvidu_release}.jar"