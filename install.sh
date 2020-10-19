#!/bin/bash
clear
echo "
 _____                 ______
 |_   _|               |  ____|
   | |  _ __ ___  _ __ | |__ _____  __
   | | | '__/ _ \| '_ \|  __/ _ \ \/ /
  _| |_| | | (_) | | | | | | (_) >  <
 |_____|_|  \___/|_| |_|_|  \___/_/\_\

 By: Innovera Technology
     https://innovera.ir
 CodeName:
     The Desert Fox (0.0.9)
 "

#define variables
SERVER_IP="0.0.0.0"
IRON_FOX_ROOT=$PWD
NGINX_PATH=$IRON_FOX_ROOT/nginx-1.19.2
MODULES_PATH=$IRON_FOX_ROOT/modules
SETUP_DEPENDENCY_SREGEX_PATH=$IRON_FOX_ROOT/dependency/sregex
SETUP_PATH=/home/ironfox/iron
BIN_PATH=/home/ironfox/iron/sbin


MODE_DEBUG='--with-debug'
HAVE_DEBUG="no"

for arg in $*; do
  if [ $arg = $MODE_DEBUG ]; then
    NGX_ARGS=$MODE_DEBUG
    HAVE_DEBUG="yes"
    break
  else
    HAVE_DEBUG="no"
    unset NGX_ARGS
  fi
done
if [ $HAVE_DEBUG = "yes" ]; then
  echo "Start setup, debug enabled..."
else
  echo "Start setup..."
fi
if [[ $(id -u) -ne 0 ]]; then
  clear
  echo "
[IronFox Setup]
Version 0.0.5
CodeName: The Desert Fox

  setup params:
  --with-debug        Setup with debug enabled mode.

_____________________________________________________________
Note: installer MUST be run with root privilege
  "
  exit 1
fi
echo "shutdown service and clean up path..."
sudo rm -R $SETUP_PATH
sudo rm -R nginx-1.19.2
tar xfv nginx-1.19.2.tar.gz
sudo systemctl stop innovera
sudo kill 9 $(ps -aux | grep nginx | awk '{print $2}')

#build embedded file
echo "#!/bin/bash
sudo java -jar $SETUP_PATH/sbin/panel.jar  --spring.config.location=$SETUP_PATH/sbin/application.properties
" >manager/runservice.sh

echo "[Unit]
Description=IronFox panel service
[Service]
User=root
# The configuration file application.properties should be here:
#change this to your workspace
WorkingDirectory=$BIN_PATH
#path to executable.
#executable is a bash script which calls jar file
ExecStart=$BIN_PATH/runservice.sh
SuccessExitStatus=143
TimeoutStopSec=10
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
" >manager/innovera.service

echo "check and setup dependencies..."
sudo apt install build-essential
sudo apt install redis
sudo apt install libpcre3-dev
sudo apt install libhiredis-dev
sudo apt install libssl-dev
sudo apt install zlib1g-dev
sudo apt install openjdk-8-jdk

#echo "installing PostgreSql..."
#sudo apt update
#sudo apt install vim bash-completion wget
#wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
#echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" |sudo tee  /etc/apt/sources.list.d/pgdg.list
#sudo apt update
#sudo apt install postgresql-12 postgresql-client-12
#todo add postgresql account and db with all-in-one sql file

cd $SETUP_DEPENDENCY_SREGEX_PATH
make
sudo make install
cd $IRON_FOX_ROOT



echo "apply iptables settings..."
sudo iptables -P INPUT ACCEPT
sudo iptables -P OUTPUT ACCEPT
# flush iptables
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X
sudo iptables -t mangle -F
sudo iptables -t mangle -X
#allow loopback
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
#icmp
sudo iptables -A OUTPUT -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT  -p icmp -m state --state ESTABLISHED,RELATED     -j ACCEPT
#dns
sudo iptables -A OUTPUT -p udp  --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT  -p udp  --sport 53 -m state --state ESTABLISHED     -j ACCEPT
sudo iptables -A OUTPUT -p tcp  --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT  -p tcp  --sport 53 -m state --state ESTABLISHED     -j ACCEPT
#https
sudo iptables -A OUTPUT -p tcp  --dport 443 -m state --state NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT  -p tcp  --sport 443 -m state --state ESTABLISHED     -j ACCEPT
#dashboard
sudo iptables -A OUTPUT -p tcp  --dport 8080 -m state --state NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT  -p tcp  --sport 8080 -m state --state ESTABLISHED     -j ACCEPT
#http
sudo iptables -A OUTPUT -p tcp  --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT  -p tcp  --sport 80 -m state --state ESTABLISHED     -j ACCEPT
#ssh
sudo iptables -A OUTPUT -p tcp  --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT  -p tcp  --sport 22 -m state --state ESTABLISHED     -j ACCEPT
# policy
sudo iptables -P INPUT DROP
sudo iptables -P OUTPUT DROP

echo "compiling source..."
sudo mkdir $SETUP_PATH
sudo mkdir $SETUP_PATH/sbin/
sudo mkdir $SETUP_PATH/cert/
sudo mkdir $SETUP_PATH/html/

echo "apply nginx patch..."
patch -p0 <$IRON_FOX_ROOT/nginx.patch

cd $NGINX_PATH
./configure $NGX_ARGS --prefix=$SETUP_PATH --with-ld-opt='-Wl,-rpath,/usr/local/lib' \
  --sbin-path=$SETUP_PATH/sbin/ \
  --with-http_sub_module \
  --with-http_ssl_module \
  --with-compat \
  --add-dynamic-module=${MODULES_PATH}/ngx_http_bot_protection_module \
  --add-dynamic-module=${MODULES_PATH}/replace-filter-nginx-module
  #--add-dynamic-module=${MODULES_PATH}/ngx_http_header_inspect \

make
make install

cd $IRON_FOX_ROOT
echo "copy files..."
cp -vv html/production/* $SETUP_PATH/html/
cp -vv manager/panel.jar $BIN_PATH
cp -vv manager/application.properties $BIN_PATH

cp -vv cert/* $SETUP_PATH/cert/
sudo chmod +x -R $SETUP_PATH/html/*

echo "service configuration..."
sudo cp -vv manager/innovera.service /etc/systemd/system/innovera.service
sudo cp -vv manager/runservice.sh $BIN_PATH
sudo chmod u+x $BIN_PATH/runservice.sh
# figure and start service
sudo systemctl daemon-reload
sudo systemctl enable innovera.service
sudo systemctl start innovera

echo "setup done."
