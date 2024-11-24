#!/bin/bash

cd /tmp && wget -c https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
gunzip gost-linux-amd64-2.11.5.gz
chmod +x gost-linux-amd64-2.11.5
mv gost-linux-amd64-2.11.5 /usr/bin/gost
gost -V
