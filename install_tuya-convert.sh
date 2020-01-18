#!/usr/bin/env bash

# Setup script
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
trap '{ exit $?; }' ERR

# Default variables
WLAN=$1
LOCALE=${2:-en_US.UTF-8}

# Prepare container OS
echo -e "tuya\ntuya" | passwd
sed -i "s/\(# \)\($LOCALE.*\)/\2/" /etc/locale.gen
export LANGUAGE=$LOCALE LANG=$LOCALE LC_ALL=$LOCALE
locale-gen
cd /root

# Detect DHCP address
while [ "$(hostname -I)" = "" ]; do
  COUNT=$((${COUNT-} + 1))
  echo "   *-> Failed to grab an IP address, waiting...$COUNT"
  if [ $COUNT -eq 10 ]; then
    echo "ERROR: Unable to verify assigned IP address."
    exit 1
  fi
  sleep 1
done

# Update container OS
apt update
apt upgrade -y

# Install prerequisites
echo "samba-common samba-common/dhcp boolean false" | debconf-set-selections
apt install -y git curl network-manager net-tools samba

# Clone tuya-convert
git clone https://github.com/ct-Open-Source/tuya-convert
find tuya-convert -name \*.sh -exec sed -i -e "s/sudo \(-\S\+ \)*//" {} \;

# Install tuya-convert
cd tuya-convert
./install_prereq.sh
systemctl disable dnsmasq
systemctl disable mosquitto
echo "Setting $WLAN interface for tuya-convert ..."
sed -i "s/^\(WLAN=\)\(.*\)/\1$WLAN/" config.txt

# Customize OS
cat <<EOL >> /etc/samba/smb.conf
[tuya-convert]
  path = /root/tuya-convert
  browseable = yes
  writable = yes
  public = yes
  force user = root
EOL
cat <<EOL >> /etc/issue
  ******************************
    The tuya-convert files are
    shared using samba at
    \4{eth0}
  ******************************

  Login using the following credentials
    username: root
    password: tuya

EOL
sed -i "s/^\(root\)\(.*\)\(\/bin\/bash\)$/\1\2\/root\/login.sh/" /etc/passwd

# Cleanup
rm -rf /root/install_tuya-convert.sh /var/{cache,log}/* /var/lib/apt/lists/*
