#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Completely uninstalls Pi-hole
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

source /usr/local/include/pihole/piholeInclude

if [[ $? != 0 ]]; then
	echo "::: Error including /usr/local/include/pihole/piholeInclude.  Unable to continue with uninstall."
	exit 1
fi

rerun_root "$0" "$@"

######### SCRIPT ###########
apt-get -y remove --purge dnsutils bc toilet
apt-get -y remove --purge dnsmasq
apt-get -y remove --purge php5-common php5-cgi php5



case $webServer in
	lighttpd)
		apt-get -y remove --purge lighttpd
		rm "${webRoot}/index.lighttpd.orig"
		rm -rf /etc/lighttpd/
		;;
	apache)
		:
		;;
	Manual)
		:
		;;
esac

# Only web directories/files that are created by pihole should be removed.
echo "Removing the Pi-hole Web server files..."
rm -rf "${webRoot}/admin"
rm -rf "${webRoot}/pihole"

# If the web directory is empty after removing these files, then the parent html folder can be removed.
webRootFiles=$(ls -A "${webRoot}")
if [[ ! "$webRootFiles" ]]; then
    rm -rf "${webRoot}"
fi

echo "Removing dnsmasq config files..."
rm /etc/dnsmasq.conf /etc/dnsmasq.conf.orig

# Attempt to preserve backwards compatibility with older versions
# to guarantee no additional changes were made to /etc/crontab after
# the installation of pihole, /etc/crontab.pihole should be permanently
# preserved.
if [[ -f /etc/crontab.orig ]]; then
  echo "Initial Pi-hole cron detected.  Restoring the default system cron..."
	mv /etc/crontab /etc/crontab.pihole
	mv /etc/crontab.orig /etc/crontab
	service cron restart
fi

# Attempt to preserve backwards compatibility with older versions
if [[ -f /etc/cron.d/pihole ]];then
  echo "Removing cron.d/pihole..."
	rm /etc/cron.d/pihole
fi

echo "Removing config files and scripts..."
rm /etc/dnsmasq.conf
rm /etc/sudoers.d/pihole
rm /var/log/pihole.log
rm /usr/local/bin/gravity.sh
rm /usr/local/bin/chronometer.sh
rm /usr/local/bin/whitelist.sh
rm /usr/local/bin/piholeReloadServices.sh
rm /usr/local/bin/piholeLogFlush.sh
rm /usr/local/bin/updateDashboard.sh
rm -rf "${piholeConfigDir}"
rm -rf "${piholeVarDir}"
rm -rf /usr/local/include/pihole
