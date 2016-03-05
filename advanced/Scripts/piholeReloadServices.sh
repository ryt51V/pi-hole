#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Restarts pihole services
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

source /usr/local/include/pihole/piholeInclude

rerun_root "$0" "$@"

dnsmasqPid=$(pidof dnsmasq)

if [[ $dnsmasqPid ]]; then
	# service already running - reload config
	$SUDO kill -HUP $dnsmasqPid & spinner $!
else
	# service not running, start it up
	$SUDO service dnsmasq start & spinner $!
fi
