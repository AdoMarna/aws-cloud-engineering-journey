#!/bin/bash

set -euo pipefail

sudo dnf update -y
sudo dnf install -y nginx

download_link=https://amazoncloudwatch-agent.s3.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 600"`
MY_HOSTNAME=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-hostname`
MY_INSTANCE_ID=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id`
MY_AZ=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/meta-data/placement/availability-zone`
REGION=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | grep -oP '"region"\s*:\s*"\K[^"]+'`

# Récupération des paramètres applicatifs depuis SSM Parameter Store.
APP_ENV=$(aws ssm get-parameter --name "/config/app/env" --region "$REGION" --query "Parameter.Value" --output text)
DB_PASSWORD=$(aws ssm get-parameter --name "/config/app/db_password" --with-decryption --region "$REGION" --query "Parameter.Value" --output text)
DB_PASSWORD_MASKED="****${DB_PASSWORD: -4}"

cat > /usr/share/nginx/html/index.html << EOF

<!DOCTYPE html>
<html>
<head></head>
<body>
<h1>$MY_HOSTNAME</h1>
<p>$MY_INSTANCE_ID</p>
<p>$MY_AZ</p>
<p>Environment: $APP_ENV</p>
<p>DB Password: $DB_PASSWORD_MASKED</p>
</body>
</html>

EOF

cat > /etc/nginx/conf.d/my-homepage.conf << EOF
server {

    listen 80;

    root /usr/share/nginx/html;

    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}

EOF

wget "$download_link"
sudo dnf install -y ./amazon-cloudwatch-agent.rpm

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -c default -s

sudo systemctl enable amazon-cloudwatch-agent.service

sudo systemctl start nginx.service
sudo systemctl enable nginx.service