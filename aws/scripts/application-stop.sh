#!/bin/bash
set -x
cd /usr/local/codedeployresources
pm2 stop asg-node-app || true