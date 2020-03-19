#!/usr/bin/env bash

# Install necesary tools
apt-get update \
apt-get install -y wget curl

public_ip=$(curl ifconfig.co)
read -p "Please enter yout machine public ip [default $public_ip]: " public_ip

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
sed -i "0,/;stunServerAddress=.*/s//stunServerAddress=${public_ip}/" /etc/kurento/modules/kurento/WebRtcEndpoint.conf.ini
sed -i "0,/;stunServerPort=.*/s//stunServerPort=3478/" /etc/kurento/modules/kurento/WebRtcEndpoint.conf.ini

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

# Install Java 8
apt-get install -y openjdk-8-jre

# Install Openvidu
mkdir /opt/openvidu
last_openvidu_release=$(wget -q https://github.com/OpenVidu/openvidu/releases/latest -O - | grep -E \/tag\/ | awk -F "[><]" '{print $3}' | sed ':a;N;$!ba;s/\n//g' | sed 's/v//')
wget -O /opt/openvidu/openvidu-server.jar "https://github.com/OpenVidu/openvidu/releases/download/v${last_openvidu_release}/openvidu-server-${last_openvidu_release}.jar"
chown -R openvidu:openvidu /opt/openvidu

cat > /opt/openvidu/openvidu-server.sh<<EOF
#!/bin/bash

# This script will launch OpenVidu Server on your machine

OPENVIDU_SECRET="prueba"

OPENVIDU_OPTIONS="-Dopenvidu.secret=$OPENVIDU_SECRET "
OPENVIDU_OPTIONS+="-Dserver.ssl.enabled=false "
OPENVIDU_OPTIONS+="-Dopenvidu.publicurl=https://$public_ip:4443 "
OPENVIDU_OPTIONS+="-Dserver.port=5443 "

exec java -jar ${OPENVIDU_OPTIONS} /opt/openvidu/openvidu-server.jar
EOF

chmod +x /opt/openvidu/openvidu-server.sh

cat > /etc/systemd/system/openvidu.service<<EOF
[Unit]
Description=Openvidu Service
After=network.target

[Service]
User=openvidu
Group=openvidu

ExecStart=/opt/openvidu/openvidu-server.sh

StandardOutput=append:/var/openvidu.log
StandardError=append:/var/openvidu-error.log

SuccessExitStatus=143
TimeoutStopSec=10
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable openvidu

# Install nginx
apt-get install -y nginx
rm /etc/nginx/sites-enabled/default
rm /etc/nginx/sites-available/default
# ln -s /etc/nginx/sites-available/openvidu-call.conf /etc/nginx/sites-enabled/openvidu-call.conf

# Install Openvidu Call
mkdir /var/www/openvidu-call
last_openvidu_call_release=$(wget -q https://github.com/OpenVidu/openvidu-call/releases/tag/v2.12.0 -O - | grep -E \/tag\/ | awk -F "[><]" '{print $3}' | sed ':a;N;$!ba;s/\n//g' | sed 's/v//')
-L -o /var/www/openvidu-call/openvidu-call.tar.gz "https://github.com/OpenVidu/openvidu-call/releases/download/v${last_openvidu_call_release}/openvidu-call-${last_openvidu_call_release}.tar.gz"
tar zxf /var/www/openvidu-call/openvidu-call.tar.gz -C /var/www/openvidu-call
rm /var/www/openvidu-call/openvidu-call.tar.gz

cat > /var/www/openvidu-call/ov-settings.json<<EOF
{
        "openviduSettings": {
                "chat": true,
                "autopublish": false,
                "toolbarButtons": {
                        "audio": true,
                        "video": true,
                        "screenShare": true,
                        "fullscreen": true,
                        "exit": true
                }
        },
        "openviduCredentials": {
                "openvidu_url": "http://192.168.1.40:4443",
                "openvidu_secret": "prueba"
        }
}
EOF

chown -R www-data.www-data /var/www/openvidu-call


# Restart services
service redis-server restart
service coturn restart
service kurento-media-server restar
service nginx restart
service openvidu restart

export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

update-rc.d kurento-media-server defaults