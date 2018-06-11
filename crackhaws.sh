#!/bin/bash

# by TheTechromancer


check_root() {

	if [ $EUID -ne 0 ]; then
		printf '\n[!] Please sudo me!\n\n'
		exit 1
	fi

}


get_latest_driver_version() {

	printf "\n[+] Getting latest driver version from Nvidia's website\n"

	# gnarly curl command
	# queries Nvidia's download page and carves version number from HTML table
	# Tesla, Linux x86_64
	latest_driver_version=$(curl -b 'ProductSeriesType_WHQL=7; ProductSeries_WHQL=105; ProductType_WHQL=857; OperatingSystem_WHQL=12; Language_WHQL=1; WHQL_WHQL=' 'http://www.nvidia.com/Download/processFind.aspx?psid=105&pfid=857&osid=12&lid=1&whql=&lang=en-us&ctk=19' 2>/dev/null |
egrep -o '<td class="gridItem">[0-9]{3}\.[0-9]{2}</td>' | head -n 1 |
cut -d'>' -f2 | cut -d'<' -f1)

	printf "\n[+] Latest driver version is $latest_driver_version\n"

}


package_install() {

	printf '\n[+] Updating system\n'
	printf '    - apt-get update\n'
	apt-get -y update >/dev/null 2>&1
	printf '    - apt-get upgrade\n'
	apt-get -y upgrade >/dev/null 2>&1

	printf '\n[+] Installing dependencies\n'
	printf "    - apt-get install build-essential linux-headers-$(uname -r) p7zip-full\n"
	apt-get -y install build-essential linux-headers-$(uname -r) p7zip-full >/dev/null 2>&1
	# install other dependencies
	# apt-get -y install linux-source linux-image-extra-virtual

}


hashcat_install() {

	# get download URL
	hashcat_download_link=$(curl 'https://hashcat.net/hashcat/' 2>/dev/null | egrep -o '<a href="/files/hashcat-.*.7z">Download</a>' | cut -d'"' -f2 | cut -d'"' -f1)

	printf "\n[+] Downloading latest hashcat version from https://hashcat.net$hashcat_download_link\n\n"

	# download archive
	cd /opt
	wget "https://hashcat.net$hashcat_download_link" || printf '\n[!] Failed to download hashcat\n\n'

	# extract and delete archive
	7z x 'hashcat-*.7z' >/dev/null 2>&1
	rm hashcat-*.7z
	rm -r hashcat >/dev/null 2>&1
	mv hashcat* hashcat

	printf '\n[+] Successfully installed hashcat to /opt/hashcat\n'

	# create symlink so it's in $PATH
	ln -s /opt/hashcat/hashcat64.bin /usr/bin/hashcat 2>/dev/null && printf '\n[+] Successfully added hashcat to $PATH\n'

}


driver_download() {

	driver_url="http://us.download.nvidia.com/tesla/$latest_driver_version/NVIDIA-Linux-x86_64-$latest_driver_version.run"

	printf "\n[+] Downloading driver from $driver_url\n"
	cd /root
	wget $driver_url || (printf '\n[!] Failed to download driver\n'; exit 1)

}


prepare_driver_install() {

	service_file='/etc/systemd/system/nvidia_driver_install.service'
	startup_script='/etc/systemd/system/nvidia_driver_install.sh'
	driver_log_file='/var/log/nvidia_driver_install.log'

	# blacklist noveau (open-source driver)
	cat <<EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF

	echo options nouveau modeset=0 >> /etc/modprobe.d/nouveau-kms.conf
	update-initramfs -u

	# create startup script
	cat <<EOF > $startup_script
#!/bin/bash

cd /root

# so this script only runs once
systemctl disable nvidia_driver_install.service

chmod +x "NVIDIA-Linux-x86_64-$latest_driver_version.run"
"./NVIDIA-Linux-x86_64-$latest_driver_version.run" -q -a -n -s 2>&1 | tee -a $driver_log_file

# clean up
rm $service_file
rm $startup_script
rm "NVIDIA-Linux-x86_64-$latest_driver_version.run"
EOF

	chmod +x $startup_script

	# create systemd service for automatic startup
	cat <<EOF > $service_file
[Unit]
Description=Nvidia Driver Install

[Service]
ExecStart=/etc/systemd/system/nvidia_driver_install.sh
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

	systemctl enable nvidia_driver_install.service

	printf '\n[+] Preparation finished.\n\n'

	read -p "[?] Reboot? (Y/N)" -r
	
	printf '\n[+] After reboot, feel free to check if driver is working:\n\n     $ lsmod | grep nvidia$\n'
	printf "\n[+] Installation log is at $driver_log_file\n\n"

	sleep 4

	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		reboot
	else
		printf '[!] Please reboot "whenever"\n\n'
		exit 2
	fi

}


main() {

	check_root

	# make sure we're running debian
	command -v apt-get >/dev/null || (printf '\n[!] This script needs the APT package manager\n\n'; exit 1)

	get_latest_driver_version

	if [ -z "$latest_driver_version" ]; then
		printf '\n[!] Failed to detect driver version\n\n'
		exit 1
	fi

	package_install

	hashcat_install

	driver_download

	prepare_driver_install

}


# dew it
main