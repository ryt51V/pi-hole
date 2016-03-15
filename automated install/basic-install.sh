#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Installs Pi-hole
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# pi-hole.net/donate
#
# Install with this command (from your Pi):
#
# curl -L install.pi-hole.net | bash

######## ROOT #########
# Check if root, and if not then rerun with sudo.
echo ":::"
if [[ $EUID -eq 0 ]];then
	echo "::: You are root."
	# Older versions of Pi-hole set $SUDO="sudo" and prefixed commands with it,
	# rather than rerunning as sudo. Just in case it turns up by accident, 
	# explicitly set the $SUDO variable to an empty string.
	SUDO=""
else
	echo "::: sudo will be used."
	# Check if it is actually installed
	# If it isn't, exit because the install cannot complete
	if [[ $(dpkg-query -s sudo) ]];then
		echo "::: Running sudo $0 $@"
		sudo "$0" "$@"
		exit $?
	else
		echo "::: Please install sudo or run this script as root."
	exit 1
	fi
fi

######## VARIABLES #########

piholeConfigDir=/etc/pihole
piholeVarDir=/var/lib/pihole

tmpLog=/tmp/pihole-install.log
instalLogLoc="${piholeConfigDir}/install.log"

webInterfaceGitUrl="https://github.com/ryt51V/AdminLTE-alt"

piholeGitUrl="https://github.com/ryt51V/pi-hole-alt"
piholeFilesDir="/etc/.pihole"


# Find the rows and columns
rows=$(tput lines)
columns=$(tput cols)

# Set whiptail to autosize.  Doesn't always look as nice but means it will always fit.
r=0
c=0

piholeconffile="${piholeConfigDir}/pihole.conf"
# IPv6 file is now only used for the admin interface PHP to know if IPv6 is enabled
piholeIPv6file="${piholeConfigDir}/.useIPv6"

availableInterfaces=$(ip -o link | awk '{print $2}' | grep -v "lo" | cut -d':' -f1)
dhcpcdFile=/etc/dhcpcd.conf

######## FIRST CHECK ########

if [ -d "${piholeConfigDir}" ]; then
		# Likely an existing install
		upgrade=true
	else
		upgrade=false
fi

####### FUNCTIONS ##########
###All credit for the below function goes to http://fitnr.com/showing-a-bash-spinner.html
spinner() {
	local pid=$1

	spin='-\|/'
	i=0
	while kill -0 $pid 2>/dev/null
	do
		i=$(( (i+1) %4 ))
		printf "\b${spin:$i:1}"
		sleep .1
	done
	printf "\b"
}

mkpiholeDir() {
	# Create the pihole config directory with pihole as the group owner with rw permissions.
	mkdir -p "${piholeConfigDir}"
	chown --recursive root:pihole "${piholeConfigDir}"
	chmod --recursive ug=rwX,o=rX "${piholeConfigDir}"
	
	# Create the pihole var directory with pihole as the group owner with rw permissions.
	mkdir -p "${piholeVarDir}"
	chown --recursive root:pihole "${piholeVarDir}"
	chmod --recursive ug=rwX,o=rX "${piholeVarDir}"
}

generateConfig() {
cat << EOF
#### Repo #####
webInterfaceGitUrl=$webInterfaceGitUrl
piholeGitUrl=$piholeGitUrl
#### Network ####
piholeInterface=$piholeInterface
IPv4addr=${IPv4addr%/*}
# Note that the .useIPv6 file in this folder is used for the admin interface to detect whether IPv6 is enabled or not.
useIPv6=$useIPv6
#### Web Server ####
webServer=$webServer
webRootPihole=$webRootPihole
webRootAdmin=$webRootAdmin
EOF
}

writeConfig() {
	generateConfig > "$piholeconffile"
	
	# The admin interface still looks for the .useIPv6 file to know whether or not it's enabled.
	if [[ $useIPv6 ]]
	then
		touch /etc/pihole/.useIPv6
	else
		rm -f "${piholeIPv6file}"
	fi
}

backupLegacyPihole() {
	# This function detects and backups the pi-hole v1 files.  It will not do anything to the current version files.
	if [[ -f /etc/dnsmasq.d/adList.conf ]];then
		echo "::: Original Pi-hole detected.  Initiating sub space transport"
		mkdir -p ${piholeConfigDir}/original/
		mv /etc/dnsmasq.d/adList.conf "${piholeConfigDir}/original/adList.conf.$(date "+%Y-%m-%d")"
		mv /etc/dnsmasq.conf "${piholeConfigDir}/original/dnsmasq.conf.$(date "+%Y-%m-%d")"
		mv /etc/resolv.conf "${piholeConfigDir}/original/resolv.conf.$(date "+%Y-%m-%d")"
		mv /etc/lighttpd/lighttpd.conf "${piholeConfigDir}/original/lighttpd.conf.$(date "+%Y-%m-%d")"
		mv /var/www/pihole/index.html "${piholeConfigDir}/original/index.html.$(date "+%Y-%m-%d")"
		mv /usr/local/bin/gravity.sh "${piholeConfigDir}/original/gravity.sh.$(date "+%Y-%m-%d")"
	else
		:
	fi
}

welcomeDialogs() {
	# Display the welcome dialog
	whiptail --msgbox --backtitle "Welcome" --title "Pi-hole automated installer" "This installer will transform your Raspberry Pi into a network-wide ad blocker!" $r $c

	# Support for a part-time dev
	whiptail --msgbox --backtitle "Plea" --title "Free and open source" "The Pi-hole is free, but powered by your donations:  http://pi-hole.net/donate" $r $c

	# Explain the need for a static address
	whiptail --msgbox --backtitle "Initating network interface" --title "Static IP Needed" "The Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.\n\nIn the next section you can choose to use your current (DHCP) network settings as static settings, or to manually edit them. If you have already set a static IP address then you can also keep your settings as is.\n\nIf you wish to run another web site alongside Pi-hole, then you should also set a *SECOND* static IP address dedicated for the Pi-hole's web server.  You will need to set this up manually before running this installer." $r $c
}


verifyFreeDiskSpace() {
	# 25MB is the minimum space needed (20MB install + 5MB one day of logs.)
	requiredFreeBytes=51200

	existingFreeBytes=`df -lk / 2>&1 | awk '{print $4}' | head -2 | tail -1`
	if ! [[ "$existingFreeBytes" =~ ^([0-9])+$ ]]; then
		existingFreeBytes=`df -lk /dev 2>&1 | awk '{print $4}' | head -2 | tail -1`
	fi

	if [[ $existingFreeBytes -lt $requiredFreeBytes ]]; then
		whiptail --msgbox --backtitle "Insufficient Disk Space" --title "Insufficient Disk Space" "\nYour system appears to be low on disk space. pi-hole recomends a minimum of $requiredFreeBytes Bytes.\nYou only have $existingFreeBytes Free.\n\nIf this is a new install you may need to expand your disk.\n\nTry running:\n    'sudo raspi-config'\nChoose the 'expand file system option'\n\nAfter rebooting, run this installation again.\n\ncurl -L install.pi-hole.net | bash\n" $r $c
		echo "$existingFreeBytes is less than $requiredFreeBytes"
		echo "Insufficient free space, exiting..."
		exit 1
	fi
}


chooseInterface() {
	# Turn the available interfaces into an array so it can be used with a whiptail dialog
	interfacesArray=()
	firstloop=1

	while read -r line
	do
		mode="OFF"
		if [[ $firstloop -eq 1 ]]; then
			firstloop=0
			mode="ON"
		fi
		interfacesArray+=("$line" "available" "$mode")
	done <<< "$availableInterfaces"

	# Find out how many interfaces are available to choose from
	interfaceCount=$(echo "$availableInterfaces" | wc -l)
	chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose An Interface.\n\n(If you are unsure, choose 'eth0' for your main wired connection.)" $r $c $interfaceCount)
	chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty)
	if [[ $? = 0 ]];then
		for desiredInterface in $chooseInterfaceOptions
		do
		piholeInterface=$desiredInterface
		echo "::: Using interface: $piholeInterface"
		done
	else
		echo "::: Cancel selected, exiting...."
		exit 1
	fi

}

use4andor6() {
	# Let use select IPv4 and/or IPv6
	cmd=(whiptail --separate-output --checklist "Select Protocols\n\n(If you are unsure, leave these as the defaults.)" $r $c 2)
	options=(IPv4 "Block ads over IPv4" on
	IPv6 "Block ads over IPv6" off)
	choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
	if [[ $? = 0 ]];then
		for choice in $choices
		do
			case $choice in
			IPv4	)		useIPv4=true;;
			IPv6	)		useIPv6=true;;
			esac
		done

		if [ $useIPv4 ]; then
			
			# Get interface address information
			IPv4dev=$piholeInterface
			IPv4addresses=$(ip -o -f inet addr show dev $IPv4dev | awk '{print $4}')
			IPv4gw=$(ip route show dev "$IPv4dev" | awk '/default/ {print $3}')
			
			# Turn IPv4 addresses into an array so it can be used with a whiptail dialog
			IPv4Array=()
			firstloop=1

			while read -r line
			do
				mode="OFF"
				if [[ $firstloop -eq 1 ]]; then
					firstloop=0
					mode="ON"
				fi
				IPv4Array+=("$line" "available" "$mode")
			done <<< "$IPv4addresses"
			
			# Find out how many IP addresses are available to choose from
			IPv4Count=$(echo "$IPv4addresses" | wc -l)
			chooseIPv4Cmd=(whiptail --separate-output --radiolist "Choose an IPv4 address on this interface.\n\n(If you are unsure, leave it as the default.)" $r $c $IPv4Count)
			IPv4addr=$("${chooseIPv4Cmd[@]}" "${IPv4Array[@]}" 2>&1 >/dev/tty)
			
			if [[ ! ($? = 0) ]];then
				echo "::: Cancel selected, exiting...."
				exit 1
			fi
		
			if (whiptail --backtitle "IPv4" --title "Reconfigure IPv4" --yesno --defaultno "We have found the following details for the IPv4 address you have selected. Have you already configured this as a static IPv4 address as desired?\n\n(If you are unsure, choose No.)  \n\nCurrent settings:
										IPv4 address:    $IPv4addr
										Gateway:         $IPv4gw" $r $c)
			then
				echo "::: Leaving IPv4 settings as is."
			else
				getStaticIPv4Settings
				setStaticIPv4
			fi
			echo "::: Using IPv4 on $IPv4addr"
		else
			echo "::: IPv4 will NOT be used."
		fi
		
		if [ $useIPv6 ]; then
			useIPv6dialog
			echo "::: Using IPv6 on $piholeIPv6"
		else
			echo "::: IPv6 will NOT be used."
		fi
		
		if [ ! $useIPv4 ] && [ ! $useIPv6 ]; then
			echo "::: Cannot continue, neither IPv4 or IPv6 selected"
			echo "::: Exiting"
			exit 1
		fi
	
	else
		echo "::: Cancel selected. Exiting..."
		exit 1
	fi
}

useIPv6dialog() {
	# Show the IPv6 address used for blocking
	piholeIPv6=$(ip -6 route get 2001:4860:4860::8888 | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "src") print $(i+1) }')
	whiptail --msgbox --backtitle "IPv6..." --title "IPv6 Supported" "$piholeIPv6 will be used to block ads." $r $c
}

getStaticIPv4Settings() {
	# Ask if the user wants to use DHCP settings as their static IP
	if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Do you want to use your current network settings as a static address?
									IP address:    $IPv4addr
									Gateway:       $IPv4gw" $r $c) then
		# If they choose yes, let the user know that the IP address will not be available via DHCP and may cause a conflict.
		whiptail --msgbox --backtitle "IP information" --title "FYI: IP Conflict" "It is possible your router could still try to assign this IP to a device, which would cause a conflict.  But in most cases the router is smart enough to not do that.
		If you are worried, either manually set the address, or modify the DHCP reservation pool so it does not include the IP you want.
		It is also possible to use a DHCP reservation, but if you are going to do that, you might as well set a static address." $r $c
		# Nothing else to do since the variables are already set above
	else
		# Otherwise, we need to ask the user to input their desired settings.
		# Start by getting the IPv4 address (pre-filling it with info gathered from DHCP)
		# Start a loop to let the user enter their information with the chance to go back and edit it if necessary
		until [[ $ipSettingsCorrect = True ]]
		do
			# Ask for the IPv4 address
			IPv4addr=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address" $r $c $IPv4addr 3>&1 1>&2 2>&3)
			if [[ $? = 0 ]];then
				echo "::: Your static IPv4 address:    $IPv4addr"
				# Ask for the gateway
				IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" $r $c $IPv4gw 3>&1 1>&2 2>&3)
				if [[ $? = 0 ]];then
					echo "::: Your static IPv4 gateway:    $IPv4gw"
					# Give the user a chance to review their settings before moving on
					if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
							IP address:    $IPv4addr
							Gateway:       $IPv4gw" $r $c)then
							# If the settings are correct, then we need to set the piholeIP
							# After that's done, the loop ends and we move on
							ipSettingsCorrect=True
					else
						# If the settings are wrong, the loop continues
						ipSettingsCorrect=False
					fi
				else
					# Cancelling gateway settings window
					ipSettingsCorrect=False
					echo "::: Cancel selected. Exiting..."
					exit 1
				fi
			else
				# Cancelling IPv4 settings window
				ipSettingsCorrect=False
				echo "::: Cancel selected. Exiting..."
				exit 1
			fi
		done
	# End the if statement for DHCP vs. static
	fi
}

setDHCPCD() {
	# Append these lines to dhcpcd.conf to enable a static IP
	echo "::: interface $piholeInterface
	static ip_address=$IPv4addr
	static routers=$IPv4gw
	static domain_name_servers=$IPv4gw" | tee -a $dhcpcdFile >/dev/null
}

setStaticIPv4() {
	# Tries to set the IPv4 address
	if grep -q $IPv4addr $dhcpcdFile; then
		# address already set, noop
		:
	else
		setDHCPCD
		ip addr replace dev $piholeInterface $IPv4addr
		echo ":::"
		echo "::: Setting IP to $IPv4addr.  You may need to restart after the install is complete."
		echo ":::"
	fi
}

function chooseWebServer() {
	# Allow the user to choose the web server they wish to use.
	chooseWebServerCmd=(whiptail --separate-output --radiolist "Pi-hole can automatically configure the lighttpd web server for you.\n\nAlternatively, if you prefer, pi-hole can use a web server that you have previously manually configured yourself.\n\n(If you are unsure, choose lighttpd.)" $r $c 3)
	chooseWebServerOptions=(lighttpd "Please automatically install and configure lighttpd." on
							apache "I have already installed apache2. Please install the pi-hole vhost." off
							Manual "I have already installed a webserver. Please just install the webroot files." off)
	webServer=$("${chooseWebServerCmd[@]}" "${chooseWebServerOptions[@]}" 2>&1 >/dev/tty)
	if [[ ! ($? = 0) ]]; then
		echo "::: Cancel selected, exiting...."
		exit 1
	fi
	case $webServer in
		lighttpd)
			echo "::: Using lighttpd web server."
			webRootPihole="/var/www/html"
			webRootAdmin="/var/www/pihole-admin"
			;;
		apache)
			echo "::: Using apache web server."
			# Check we actually have apache installed.
			if [[ $(dpkg-query -s apache2) ]]; then
				:
			else
				whiptail --defaultno --backtitle "apache" --title "apache" --yesno "WARNING\n\napache2 does not appear to be installed.  You must have already installed it before using this option.  \n\nAre you sure you wish to continue?" $r $c
				if [[ $? != 0 ]]; then
					echo "::: Cancel selected, exiting...."
					exit 1
				fi
			fi
			
			webRootPihole=$(whiptail --backtitle "apache" --title "Web Root" --inputbox "Enter the desired webroot for the Pi-hole." $r $c "/var/www/pihole" 3>&1 1>&2 2>&3)
			
			webRootAdmin=$(whiptail --backtitle "apache" --title "Web Root" --inputbox "Enter the desired webroot for the Pi-hole Admin." $r $c "/var/www/pihole-admin" 3>&1 1>&2 2>&3)
			;;
		Manual)
			echo "::: Using manual web server configuration."
			webRoot=$(whiptail --backtitle "Web Root" --title "Web Root" --inputbox "Enter the root path of the website you have manually configured for Pi-hole." $r $c "/var/www/pihole" 3>&1 1>&2 2>&3)
			
			webRoot=$(whiptail --backtitle "Web Root" --title "Web Root" --inputbox "Enter the root path of the website you have manually configured for Pi-holeAdmin." $r $c "/var/www/pihole-admin" 3>&1 1>&2 2>&3)
			;;
	esac
	webInterfaceDir="${webRootAdmin}/admin"
}

function valid_ip()
{
	local  ip=$1
	local  stat=1

	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		OIFS=$IFS
		IFS='.'
		ip=($ip)
		IFS=$OIFS
		[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
		&& ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
		stat=$?
	fi
	return $stat
}

function valid_ip_and_port()
{
	# Validate IP and port matches dnsmasq conf syntax
	# For example '127.0.0.1#40'
	local  ip=$1
	local  stat=1
	
	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}#[0-9]{1,5}$ ]]; then
		OIFS=$IFS
		IFS='.#'
		ip=($ip)
		IFS=$OIFS
		[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
		&& ${ip[2]} -le 255 && ${ip[3]} -le 255 \
		&& ${ip[4]} -le 65535 ]]
		stat=$?
	fi
	return $stat
}

setDNS(){
	DNSChoseCmd=(whiptail --separate-output --radiolist "Select Upstream DNS Provider. To use your own, select Custom." $r $c 6)
	DNSChooseOptions=(Google "" on
					  OpenDNS "" off
					  Level3 "" off
					  Norton "" off
					  Comodo "" off
					  Custom "" off)
	DNSchoices=$("${DNSChoseCmd[@]}" "${DNSChooseOptions[@]}" 2>&1 >/dev/tty)
	if [[ $? = 0 ]];then
		case $DNSchoices in
			Google)
				echo "::: Using Google DNS servers."
				piholeDNS1="8.8.8.8"
				piholeDNS2="8.8.4.4"
				;;
			OpenDNS)
				echo "::: Using OpenDNS servers."
				piholeDNS1="208.67.222.222"
				piholeDNS2="208.67.220.220"
				;;
			Level3)
				echo "::: Using Level3 servers."
				piholeDNS1="4.2.2.1"
				piholeDNS2="4.2.2.2"
				;;
			Norton)
				echo "::: Using Norton ConnectSafe servers."
				piholeDNS1="199.85.126.10"
				piholeDNS2="199.85.127.10"
				;;
			Comodo)
				echo "::: Using Comodo Secure servers."
				piholeDNS1="8.26.56.26"
				piholeDNS2="8.20.247.20"
				;;
			Custom)
				until [[ $DNSSettingsCorrect = True ]]
				do

					strInvalid="Invalid"

					if [ ! $piholeDNS1 ]; then
						if [ ! $piholeDNS2 ]; then
							prePopulate=""
						else
							prePopulate=", $piholeDNS2"
						fi
					elif  [ $piholeDNS1 ] && [ ! $piholeDNS2 ]; then
						prePopulate="$piholeDNS1"
					elif [ $piholeDNS1 ] && [ $piholeDNS2 ]; then
						prePopulate="$piholeDNS1, $piholeDNS2"
					fi

					piholeDNS=$(whiptail --backtitle "Specify Upstream DNS Provider(s)"  --inputbox "Enter your desired upstream DNS provider(s), seperated by a comma.\n\nFor example '8.8.8.8, 8.8.4.4'\n\nIf the DNS server uses a custom port, append it following the hash symbol.\n\nFor example '127.0.0.1#40, 127.0.0.1#41'" $r $c "$prePopulate" 3>&1 1>&2 2>&3)
					if [[ $? = 0 ]];then
						piholeDNS1=$(echo $piholeDNS | sed 's/[, \t]\+/,/g' | awk -F, '{print$1}')
						piholeDNS2=$(echo $piholeDNS | sed 's/[, \t]\+/,/g' | awk -F, '{print$2}')

						if ! (valid_ip $piholeDNS1 || valid_ip_and_port $piholeDNS1) || [ ! $piholeDNS1 ]; then
							piholeDNS1=$strInvalid
						fi

						if ! (valid_ip $piholeDNS2 || valid_ip_and_port $piholeDNS2) && [ $piholeDNS2 ]; then
							piholeDNS2=$strInvalid
						fi

					else
						echo "::: Cancel selected, exiting...."
						exit 1
					fi

					if [[ $piholeDNS1 == $strInvalid ]] || [[ $piholeDNS2 == $strInvalid ]]; then
						whiptail --msgbox --backtitle "Invalid IP" --title "Invalid IP" "One or both entered IP addresses were invalid. Please try again.\n\n    DNS Server 1:   $piholeDNS1\n    DNS Server 2:   $piholeDNS2" $r $c

						if [[ $piholeDNS1 == $strInvalid ]]; then
							piholeDNS1=""
						fi

						if [[ $piholeDNS2 == $strInvalid ]]; then
							piholeDNS2=""
						fi

						DNSSettingsCorrect=False
					else
						if (whiptail --backtitle "Specify Upstream DNS Provider(s)" --title "Upstream DNS Provider(s)" --yesno "Are these settings correct?\n    DNS Server 1:   $piholeDNS1\n    DNS Server 2:   $piholeDNS2" $r $c) then
								DNSSettingsCorrect=True
						else
							# If the settings are wrong, the loop continues
							DNSSettingsCorrect=False
						fi
					fi
				done
				;;
		esac
	else
		echo "::: Cancel selected. Exiting..."
		exit 1
	fi
}

versionCheckDNSmasq(){
  # Check if /etc/dnsmasq.conf is from pihole.  If so replace with an original and install new in .d directory
  dnsFile1="/etc/dnsmasq.conf"
  dnsFile2="/etc/dnsmasq.conf.orig"
  dnsSearch="addn-hosts=${piholeVarDir}/gravity.list"

  defaultFile="/etc/.pihole/advanced/dnsmasq.conf.original"
  newFileToInstall="/etc/.pihole/advanced/01-pihole.conf"
  newFileFinalLocation="/etc/dnsmasq.d/01-pihole.conf"

  if [ -f $dnsFile1 ]; then
      echo -n ":::    Existing dnsmasq.conf found..."
      if grep -q $dnsSearch $dnsFile1; then
          echo " it is from a previous pi-hole install."
          echo -n ":::    Backing up dnsmasq.conf to dnsmasq.conf.orig..."
          mv -f $dnsFile1 $dnsFile2
          echo " done."
          echo -n ":::    Restoring default dnsmasq.conf..."
          cp $defaultFile $dnsFile1
          echo " done."
      else
        echo " it is not a pi-hole file, leaving alone!"
      fi
  else
      echo -n ":::    No dnsmasq.conf found.. restoring default dnsmasq.conf..."
      cp $defaultFile $dnsFile1
      echo " done."
  fi

  echo -n ":::    Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf..."
  cp $newFileToInstall $newFileFinalLocation
  echo " done."
  sed -i "s/@INT@/$piholeInterface/" $newFileFinalLocation
  if [[ "$piholeDNS1" != "" ]]; then
    sed -i "s/@DNS1@/$piholeDNS1/" $newFileFinalLocation
  else
    sed -i '/^server=@DNS1@/d' $newFileFinalLocation
  fi
  if [[ "$piholeDNS2" != "" ]]; then
    sed -i "s/@DNS2@/$piholeDNS2/" $newFileFinalLocation
  else
    sed -i '/^server=@DNS2@/d' $newFileFinalLocation
  fi
}

installScripts() {
	# Install the scripts from /etc/.pihole to their various locations
	echo ":::"
	echo -n "::: Installing scripts..."
	cp /etc/.pihole/gravity.sh /usr/local/bin/gravity.sh
	cp /etc/.pihole/advanced/Scripts/chronometer.sh /usr/local/bin/chronometer.sh
	cp /etc/.pihole/advanced/Scripts/whitelist.sh /usr/local/bin/whitelist.sh
	cp /etc/.pihole/advanced/Scripts/blacklist.sh /usr/local/bin/blacklist.sh
	cp /etc/.pihole/advanced/Scripts/piholeReloadServices.sh /usr/local/bin/piholeReloadServices.sh
	cp /etc/.pihole/advanced/Scripts/piholeLogFlush.sh /usr/local/bin/piholeLogFlush.sh
	cp /etc/.pihole/advanced/Scripts/updateDashboard.sh /usr/local/bin/updateDashboard.sh
	chmod 755 /usr/local/bin/{gravity,chronometer,whitelist,blacklist,piholeReloadServices,piholeLogFlush,updateDashboard}.sh
	
	mkdir -p /usr/local/include/pihole
	cp /etc/.pihole/advanced/Scripts/piholeInclude /usr/local/include/pihole/piholeInclude
	echo " done."
}

installConfigs() {
	# Install the configs from /etc/.pihole to their various locations
	echo ":::"
	echo "::: Installing configs..."
	versionCheckDNSmasq
	
	case $webServer in
		lighttpd)
			lighttpdconf='/etc/lighttpd/lighttpd.conf'
			mv "${lighttpdconf}" /etc/lighttpd/lighttpd.conf.orig
			cp /etc/.pihole/advanced/lighttpd.conf "${lighttpdconf}"
			# sed separated by a character least likely to appear in the strings
			sed -i "s#@IPv4addr@#${IPv4addr%/*}#" "${lighttpdconf}"
			sed -i "s#@htpasswd@#${htpasswdfile}#" "${lighttpdconf}"
			;;
		apache)
			piholevhost='/etc/apache2/sites-available/pihole.conf'
			cp /etc/.pihole/advanced/apache/pihole.conf "$piholevhost"
			# sed separated by a character least likely to appear in the strings
			sed -i "s#@IPv4addr@#${IPv4addr%/*}#" "$piholevhost"
			sed -i "s#@webRoot@#$webRootPihole#" "$piholevhost"
			
			adminvhost='/etc/apache2/sites-available/pihole-admin.conf'
			cp /etc/.pihole/advanced/apache/pihole-admin.conf "$adminvhost"
			# sed separated by a character least likely to appear in the strings
			sed -i "s#@IPv4addr@#${IPv4addr%/*}#" "$adminvhost"
			sed -i "s#@webRoot@#$webRootAdmin#" "$adminvhost"
			sed -i "s#@htpasswd@#${htpasswdfile}#" "$adminvhost"
			;;
		Manual)
			:
			;;
	esac
	
}

stopServices() {
	# Stop dnsmasq and lighttpd
	echo ":::"
	echo -n "::: Stopping services..."
	#service dnsmasq stop & spinner $! || true
	if [[ "$webServer" = "lighttpd" ]]
	then
		service lighttpd stop & spinner $! || true
		echo " done."
	fi
}

checkForDependencies() {
	#Running apt-get update/upgrade with minimal output can cause some issues with
	#requiring user input (e.g password for phpmyadmin see #218)
	#We'll change the logic up here, to check to see if there are any updates availible and
	# if so, advise the user to run apt-get update/upgrade at their own discretion

	#Check to see if apt-get update has already been run today
	# it needs to have been run at least once on new installs!

	timestamp=$(stat -c %Y /var/cache/apt/)
	timestampAsDate=$(date -d @$timestamp "+%b %e")
	today=$(date "+%b %e")

	if [ ! "$today" == "$timestampAsDate" ]; then
	    #update package lists
	    echo ":::"
	    echo -n "::: apt-get update has not been run today. Running now..."
	    apt-get -qq update & spinner $!
	    echo " done!"
	  fi
		echo ":::"
		echo -n "::: Checking apt-get for upgraded packages...."
		updatesToInstall=$(apt-get -s -o Debug::NoLocking=true upgrade | grep -c ^Inst)
		echo " done!"
		echo ":::"
		if [[ $updatesToInstall -eq "0" ]]; then
			echo "::: Your pi is up to date! Continuing with pi-hole installation..."
		else
			echo "::: There are $updatesToInstall updates availible for your pi!"
			echo "::: We recommend you run 'sudo apt-get upgrade' after installing Pi-Hole! "
			echo ":::"
		fi
    echo ":::"
    echo "::: Checking dependencies:"

	dependencies=( dnsutils bc toilet figlet dnsmasq php5-common php5-cgi php5 git curl unzip wget )
	
	# Add web server specific dependencies
	case $webServer in
		lighttpd)
			dependencies=( "${dependencies[@]}" "lighttpd" )
			;;
		apache)
			dependencies=( "${dependencies[@]}" "libapache2-mod-php5" )
			;;
		Manual)
			:
			;;
	esac
	
	for i in "${dependencies[@]}"
	do
	:
		echo -n ":::    Checking for $i..."
		if [ $(dpkg-query -W -f='${Status}' $i 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
			echo -n " Not found! Installing...."
			apt-get -y -qq install $i > /dev/null & spinner $!
			echo " done!"
		else
			echo " already installed!"
		fi
	done
}

getGitFiles() {
	# Setup git repos for base files and web admin
	echo ":::"
	echo "::: Checking for existing base files..."
	if is_repo $piholeFilesDir; then
		make_repo $piholeFilesDir $piholeGitUrl
	else
		update_repo $piholeFilesDir
	fi

	echo ":::"
	echo "::: Checking for existing web interface..."
	if is_repo $webInterfaceDir; then
		make_repo $webInterfaceDir $webInterfaceGitUrl
	else
		update_repo $webInterfaceDir
	fi
}

is_repo() {
	# If the directory does not have a .git folder it is not a repo
	echo -n ":::    Checking $1 is a repo..."
    if [ -d "$1/.git" ]; then
    		echo " OK!"
        return 1
    fi
    echo " not found!!"
    return 0
}

make_repo() {
    # Remove the non-repod interface and clone the interface
    echo -n ":::    Cloning $2 into $1..."
    rm -rf $1
    git clone -q "$2" "$1" > /dev/null & spinner $!
    echo " done!"
}

update_repo() {
    # Pull the latest commits
    echo -n ":::     Updating repo in $1..."
    cd "$1"
    git pull -q > /dev/null & spinner $!
    echo " done!"
}


CreateLogFile() {
	# Create logfiles if necessary
	echo ":::"
	echo -n "::: Creating log file and changing owner to dnsmasq..."
	if [ ! -f /var/log/pihole.log ]; then
		touch /var/log/pihole.log
		chmod 644 /var/log/pihole.log
		chown dnsmasq:root /var/log/pihole.log
		echo " done!"
	else
		echo " already exists!"
	fi
}

installPiholeWeb() {
	# Install the web interface
	echo ":::"
	echo -n "::: Installing pihole custom index page..."
	if [ -d "${webRootPihole}/pihole" ]; then
		echo " Existing page detected, not overwriting"
	else
		mkdir "${webRootPihole}/pihole"
		case $webServer in
			lighttpd)
				mv "${webRootPihole}/index.lighttpd.html" "${webRootPihole}/index.lighttpd.orig"
				;;
			apache)
				:
				;;
			Manual)
				:
				;;
		esac
		cp /etc/.pihole/advanced/index.html "${webRootPihole}/pihole/index.html"
		echo " done!"
	fi
	
	case $webServer in
		lighttpd)
			:
			;;
		apache)
			echo "::: Enabling apache site"
			a2enmod headers rewrite
			a2ensite pihole
			a2ensite pihole-admin
			;;
		Manual)
			:
			;;
	esac
	
}

installCron() {
	# Install the cron job
	echo ":::"
	echo -n "::: Installing latest Cron script..."
	cp /etc/.pihole/advanced/pihole.cron /etc/cron.d/pihole
	echo " done!"
}

runGravity() {
	# Rub gravity.sh to build blacklists
	echo ":::"
	echo "::: Preparing to run gravity.sh to refresh hosts..."
	if ls "${piholeVarDir}"/list* 1> /dev/null 2>&1; then
		echo "::: Cleaning up previous install (preserving whitelist/blacklist)"		
		rm "${piholeVarDir}"/list.*
	fi
	#Don't run as SUDO, this was causing issues
	echo "::: Running gravity.sh"
	echo ":::"

	/usr/local/bin/gravity.sh
}

setUser(){
	# Check if user pihole exists and create if not
	echo "::: Checking if user 'pihole' exists..."
	if id -u pihole > /dev/null 2>&1; then
		echo "::: User 'pihole' already exists"
	else
        echo "::: User 'pihole' doesn't exist.  Creating..."
		useradd -r -s /usr/sbin/nologin pihole
	fi
}

installSudoersFile() {
	# Install the file in /etc/sudoers.d that defines what commands
	# and scripts the pihole user can elevate to root with sudo.
	sudoersFile='/etc/sudoers.d/pihole'
	sudoersContent="pihole	ALL=(ALL:ALL) NOPASSWD: /usr/local/bin/piholeReloadServices.sh"
	echo "$sudoersContent" > "$sudoersFile"
	# chmod as per /etc/sudoers.d/README
	chmod 0440 "$sudoersFile"
}

setPassword() {
	# Password needed to authorize changes to lists from admin page
	
	if [[ $webServer = "Manual" ]]
	then
		whiptail --msgbox "The Pi-hole admin interface needs to be protected from unauthorised access.  You have chosen for Pi-Hole to install to a manually configured web server, so please make sure to configure authenticaiton, for example with a username and password." $r $c
	else
		
		pass=$(whiptail --passwordbox "When accessing the Pi-hole admin interface, you will need to log on with the username 'pi-hole' and a password of your choosing.  \n\nPlease enter a password to secure your Pi-hole web interface." $r $c 3>&1 1>&2 2>&3)

		if [ $? = 0 ]; then
			# Entered password
			htpasswdfile="${piholeConfigDir}/htpasswd"
			htpasswd -cb "$htpasswdfile" pi-hole "$pass"
		else
			echo "::: Cancel selected, exiting...."
			exit 1
		fi
		
	fi
}

installPihole() {
	# Install base files and web interface
	checkForDependencies # done
	stopServices
	setUser
	if [[ ! ( -d "$webRootPihole") ]]
	then
		mkdir -p "${webRootPihole}/pihole"
	fi
	chown www-data:www-data "${webRootPihole}"
	chmod 775 "${webRootPihole}"
	usermod -a -G www-data pihole
	if [[ "$webServer" = "lighttpd" ]]
	then
		lighty-enable-mod fastcgi fastcgi-php > /dev/null
	fi

	getGitFiles
	installScripts
	installSudoersFile
	installConfigs
	CreateLogFile
	installPiholeWeb
	installCron
	runGravity
}

displayFinalMessage() {
	# Final completion message to user
	whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!" "Configure your devices to use the Pi-hole as their DNS server using:

$IPv4addr
$piholeIPv6

If you set a new IP address, you should restart the Pi.

The install log is in ${piholeConfigDir}." $r $c
}

######## SCRIPT ############
# Start the installer
welcomeDialogs

# Verify there is enough disk space for the install
verifyFreeDiskSpace

# Find interfaces and let the user choose one
chooseInterface
# Let the user decide if they want to block ads over IPv4 and/or IPv6
use4andor6

# Let the user decide if they want to use lighttpd or manually configure their web server.
chooseWebServer

# Decide what upstream DNS Servers to use
setDNS

# Above this line, no permanent changes should have been made.
# Below this line, permanent changes will be made.

# Make pihole directories
mkpiholeDir

# Back up the original Pi-hole.
backupLegacyPihole

# Set the admin page password
setPassword

# Save the configuration to a file
writeConfig

# Install and log everything to a file
installPihole | tee $tmpLog

# Move the log file into ${piholeConfigDir} for storage
mv $tmpLog $instalLogLoc

displayFinalMessage

echo -n "::: Restarting services..."
# Start services
service dnsmasq restart

case $webServer in
	lighttpd)
		service lighttpd start
		;;
	apache)
		service apache2 restart
		;;
	Manual)
		:
		;;
esac

echo " done."

echo ":::"
echo "::: Installation Complete! Configure your devices to use the Pi-hole as their DNS server using:"
echo ":::     $IPv4addr"
echo ":::     $piholeIPv6"
echo ":::"
echo "::: If you set a new IP address, you should restart the Pi."
echo "::: "
echo "::: The install log is located at: ${piholeConfigDir}/install.log"

