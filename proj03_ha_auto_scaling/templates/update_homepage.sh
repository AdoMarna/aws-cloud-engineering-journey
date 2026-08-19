#!/bin/bash

set -euo pipefail

sudo dnf update -y
sudo dnf install -y nginx
sudo dnf install -y stress-ng

TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 600"`
MY_INSTANCE_ID=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id`
MY_AZ=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/meta-data/placement/availability-zone`

cat > /usr/share/nginx/html/index.html << EOF

<!DOCTYPE html>
<html>
<head></head>
<body>
<h1>The new homepage</h1>
<h2>Here, some infos about me</h2>
<p>This is my instance id:$MY_INSTANCE_ID</p>
<p>This is the availability zone:$MY_AZ</p>
</body>
</html>

EOF

cat > /etc/nginx/conf.d/proj03-new-homepage.conf << EOF
server {

    listen 80;

    root /usr/share/nginx/html;

    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}

EOF

sudo systemctl start nginx.service
sudo systemctl enable nginx.service