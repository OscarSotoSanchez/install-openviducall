#!/usr/bin/env bash

# Install necesary tools
apt-get update \
apt-get install -y wget curl

# General Variables
public_ip=$(curl ifconfig.co)
openvidu_secrect=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

# Read user input
read -p "Please enter your machine public ip [default: ${public_ip}]: " input_public_ip
read -p "Please enter your openvidu secret [default: ${openvidu_secrect}]: " input_openvidu_secrect

[[ ! -z "${input_public_ip}" ]] && public_ip=$(echo ${input_public_ip} | sed 's/v//')
[[ ! -z "${input_openvidu_secrect}" ]] && openvidu_secrect=$(echo ${input_openvidu_secrect} | sed 's/v//')

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

# Install Java 8
apt-get install -y openjdk-8-jre

# Install Openvidu
mkdir /opt/openvidu
last_openvidu_release=$(wget -q https://github.com/OpenVidu/openvidu/releases/latest -O - | grep -E \/tag\/ | awk -F "[><]" '{print $3}' | sed ':a;N;$!ba;s/\n//g' | sed 's/v//')
wget -L -O /opt/openvidu/openvidu-server.jar "https://github.com/OpenVidu/openvidu/releases/download/v${last_openvidu_release}/openvidu-server-${last_openvidu_release}.jar"
chown -R openvidu:openvidu /opt/openvidu

cat > /opt/openvidu/openvidu-server.sh<<EOF
#!/bin/bash

# This script will launch OpenVidu Server on your machine

OPENVIDU_SECRET="${openvidu_secrect}"

OPENVIDU_OPTIONS="-Dopenvidu.secret=\${OPENVIDU_SECRET} "
OPENVIDU_OPTIONS+="-Dserver.ssl.enabled=false "
OPENVIDU_OPTIONS+="-Dopenvidu.publicurl=https://${public_ip}:4443 "
OPENVIDU_OPTIONS+="-Dserver.port=5443 "

exec java -jar \${OPENVIDU_OPTIONS} /opt/openvidu/openvidu-server.jar
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

# Install nginx and openssl
apt-get install -y nginx openssl
#rm /etc/nginx/sites-enabled/default
#rm /etc/nginx/sites-available/default

# Create certificate
mkdir -p /etc/ssl/openvidu | true
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=/ST=/L=/O=/CN=openvidu-call" \
    -keyout /etc/ssl/openvidu/openvidu-call.key -out /etc/ssl/openvidu/openvidu-call.cert

cat > /etc/nginx/sites-available/kms.conf<<EOF
server {
        listen 4443 ssl;
        # server_name example.name.es;

        ssl on;
        ssl_certificate         /etc/ssl/openvidu/openvidu-call.cert;
        ssl_certificate_key     /etc/ssl/openvidu/openvidu-call.key;
        ssl_trusted_certificate /etc/ssl/openvidu/openvidu-call.cert;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Proto https;
        proxy_headers_hash_bucket_size 512;
        proxy_redirect off;

        # Websockets
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        location / {
                proxy_pass http://localhost:5443;
        }
}
EOF
ln -s /etc/nginx/sites-available/kms.conf /etc/nginx/sites-enabled/kms.conf

cat > /etc/nginx/sites-available/openvidu-call.conf<<EOF
server {
        listen 443 ssl;
        # server_name example.name.es;

        ssl on;
        ssl_certificate         /etc/ssl/openvidu/openvidu-call.cert;
        ssl_certificate_key     /etc/ssl/openvidu/openvidu-call.key;
        ssl_trusted_certificate /etc/ssl/openvidu/openvidu-call.cert;

        ssl_session_cache shared:SSL:50m;
        ssl_session_timeout 5m;
        ssl_stapling on;
        ssl_stapling_verify on;

        ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
        ssl_ciphers "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DES-CBC3-SHA:HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4";

        ssl_prefer_server_ciphers on;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Proto https;
        proxy_headers_hash_bucket_size 512;
        proxy_redirect off;

        root /var/www/openvidu-call;
}
EOF
ln -s /etc/nginx/sites-available/openvidu-call.conf /etc/nginx/sites-enabled/openvidu-call.conf

# Install Openvidu Call
mkdir /var/www/openvidu-call
last_openvidu_call_release=$(wget -q https://github.com/OpenVidu/openvidu-call/releases/tag/v2.12.0 -O - | grep -E \/tag\/ | awk -F "[><]" '{print $3}' | sed ':a;N;$!ba;s/\n//g' | sed 's/v//')
wget -L -O /var/www/openvidu-call/openvidu-call.tar.gz "https://github.com/OpenVidu/openvidu-call/releases/download/v${last_openvidu_call_release}/openvidu-call-${last_openvidu_call_release}.tar.gz"
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
                "openvidu_url": "https://${public_ip}:4443",
                "openvidu_secret": "${openvidu_secrect}"
        }
}
EOF

chown -R www-data.www-data /var/www/openvidu-call

# Restart services
service redis-server restart
service coturn restart
service kurento-media-server restart
service nginx restart
service openvidu restart

export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

update-rc.d kurento-media-server defaults

# Display info
echo -e "====================================================="
echo -e "= Auto Install Openvidu CE and Openvidu Call Script ="
echo -e "====================================================="
echo -e "To connect to Openvidu CE: https://${public_ip}:4443"
echo -e "To connect to Openvidu Call: https://${public_ip}"