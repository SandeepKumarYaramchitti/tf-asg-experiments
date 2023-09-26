#!/bin/bash
cd /usr/local/codedeployresources
pm2 describe asg-node-app > /dev/null
if [ $? -ne 0 ]; then
  exit 1
fi
