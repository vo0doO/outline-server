#!/usr/bin/env bash

docker build -t vo0doo/shadowbox /home/vo0/WebstormProjects/outline-server/ -f docker/Dockerfile  \
&& bash /home/vo0/WebstormProjects/outline-server/src/server_manager/install_scripts/install_server.sh  \
&& sudo ufw allow 8091/tcp  \
&& sudo ufw allow 2548/tcp  \
&& sudo ufw allow 2548/udp
# RESULTS
# {"apiUrl":"https://213.158.1.82:8091/3EQeCgWSm7xR1HIdUkM4QQ","certSha256":"E39013D1764D09054AC4A443F6911AE58029BDC19AEEB00EF83E1A85DBD49F6C"}
