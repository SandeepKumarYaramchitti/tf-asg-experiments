#!/bin/bash
yum update -y
yum install -y nodejs ruby
yum install -y wget
cd /usr/local
npm install pm2 -g
echo "Node.js version:"
node -v
echo "PM2 version:"
pm2 -v
echo "WGET version:"
wget --version

# Install CodeDeploy Agent for us-east-1 region
wget https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install
chmod +x ./install
./install auto
service codedeploy-agent start