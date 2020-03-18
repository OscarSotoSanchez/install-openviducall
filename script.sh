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
sed -i "s/DAEMON_USER=\"kurento\"/DAEMON_USER=\"openvidu\"/g" /etc/default/kurento-media-server

# Install COTURN
apt-get -y install coturn

# Install Redis
apt-get -y install redis-server

# Modify WebRtcEndpoint.conf.ini file
sed -i "0,/;externalAddress=.*/s//externalAddress=${public_ip}/" /etc/kurento/modules/kurento/WebRtcEndpoint.conf.ini

# Modify turnserver.conf file
sed -i "0,/#external-ip=.*/s//external-ip=${public_ip}/" /etc/turnserver.conf
sed -i '0,/#listening-port=.*/s//listening-port=3478/' /etc/turnserver.conf
sed -i '0,/#fingerprint/s//fingerprint/' /etc/turnserver.conf
sed -i '0,/#lt-cred-mech/s//lt-cred-mech/' /etc/turnserver.conf
sed -i '0,/#max-port=.*/s//max-port=65535/' /etc/turnserver.conf
sed -i '0,/#min-port=.*/s//min-port=40000/' /etc/turnserver.conf
sed -i '0,/#pidfile=.*/s//pidfile="/var/run/turnserver.pid"/' /etc/turnserver.conf
sed -i '0,/#realm=.*/s//realm=openvidu/' /etc/turnserver.conf
sed -i '0,/#simple-log/s//simple-log/' /etc/turnserver.conf
sed -i '0,/#redis-userdb=.*/s//redis-userdb="ip=127.0.0.1 dbname=0 password=turn connect_timeout=30"/' /etc/turnserver.conf
sed -i '0,/#verbose/s//verbose/' /etc/turnserver.conf

# Modify coturn file
sed -i '0,/#TURNSERVER_ENABLED=.*/s//TURNSERVER_ENABLED=1/' /etc/default/coturn

# Restart services
service redis-server restart
service coturn restart
service kurento-media-server restar

# Install Java 8
apt-get install -y openjdk-8-jre

# Install Openvidu
mkdir /opt/openvidu
last_openvidu_release=$(wget -q https://github.com/OpenVidu/openvidu/releases/latest -O - | grep -E \/tag\/ | awk -F "[><]" '{print $3}' | sed ':a;N;$!ba;s/\n//g' | sed 's/v//')
wget -O /opt/openvidu/openvidu.jar "https://github.com/OpenVidu/openvidu/releases/download/v${last_openvidu_release}/openvidu-server-${last_openvidu_release}.jar"
chown -R openvidu:openvidu /opt/openvidu