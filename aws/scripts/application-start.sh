#!/bin/bash
set -xe
cd /usr/local/codedeployresources
pm2 start app.js --name asg-node-app