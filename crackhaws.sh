#!/bin/bash

# by TheTechromancer

logfile='/var/log/nvidia_driver_install.log'

# enable command aliasing
shopt -s expand_aliases

# skip prompts in apt-upgrade, etc.
export DEBIAN_FRONTEND=noninteractive
alias apt-get='apt-get -o Dpkg::Options::="--force-confdef" -y'


check_root()
{

    if [ $EUID -ne 0 ]; then
        printf '\n[!] Please sudo me!\n\n'
        exit 1
    fi

}


get_latest_driver_version()
{

    printf "\n[+] Getting latest driver version from Nvidia's website\n"

    # gnarly curl command
    # queries Nvidia's download page and carves version number from HTML table
    # Tesla, Linux x86_64
    latest_driver_version=$(curl -b 'ProductSeriesType_WHQL=7; ProductSeries_WHQL=105; ProductType_WHQL=857; OperatingSystem_WHQL=12; Language_WHQL=1; WHQL_WHQL=' 'https://www.nvidia.com/Download/driverResults.aspx/136954/en-us' 2>/dev/null |
    egrep -ow '3[0-9]{2}\.[0-9]{2}' | sort -u -n -r | head -n 1)


    printf "\n[+] Latest driver version is $latest_driver_version\n"

}


package_install()
{

    printf '\n[+] Updating system\n'
    printf '    - apt-get update\n'
    apt-get update 2>&1 | tee -a "$logfile"
    printf '    - apt-get upgrade\n'
    apt-get upgrade 2>&1 | tee -a "$logfile"

    printf '\n[+] Installing dependencies\n'
    printf "    - apt-get install build-essential linux-headers-$(uname -r) p7zip-full\n"
    apt-get install build-essential linux-headers-$(uname -r) p7zip-full 2>&1 | tee -a "$logfile"

    # dependencies for hcxtools and hcxdumptool
    # printf "    - apt-get install libssl-dev zlib1g-dev libcurl4-openssl-dev\n"
    # apt-get install libssl-dev zlib1g-dev libcurl4-openssl-dev >>"$logfile" 2>&1

}


hashcat_install()
{

    # get download URL
    hashcat_download_link=$(curl 'https://hashcat.net/hashcat/' 2>>"$logfile" | egrep -o '<a href="/files/hashcat-.*.7z">Download</a>' | cut -d'"' -f2 | cut -d'"' -f1 | head -n 1)

    printf "\n[+] Downloading latest hashcat version from https://hashcat.net$hashcat_download_link\n\n"

    # download archive
    cd /opt
    wget "https://hashcat.net$hashcat_download_link" || printf '\n[!] Failed to download hashcat\n\n'

    # extract and delete archive
    7z x 'hashcat-*.7z' 2>&1 | tee -a "$logfile"
    rm hashcat-*.7z
    #rm -r hashcat >/dev/null 2>&1
    mv hashcat* hashcat

    printf '\n[+] Successfully installed hashcat to /opt/hashcat\n'

    # create symlink so it's in $PATH
    ln -s /opt/hashcat/hashcat.bin /usr/bin/hashcat 2>>"$logfile" && printf '\n[+] Successfully added hashcat to $PATH\n'

}


driver_download()
{

    driver_url="http://us.download.nvidia.com/tesla/$latest_driver_version/NVIDIA-Linux-x86_64-$latest_driver_version.run"

    printf "\n[+] Downloading driver from $driver_url\n"
    cd /root
    wget $driver_url || (printf '\n[!] Failed to download driver\n'; exit 1)

}


prepare_driver_install()
{

    service_file='/etc/systemd/system/nvidia_driver_install.service'
    startup_script='/etc/systemd/system/nvidia_driver_install.sh'

    # blacklist noveau (open-source driver)
    cat <<EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF

    modprobe_entry='options nouveau modeset=0'
    if ! grep -xq "$modprobe_entry" /etc/modprobe.d/nouveau-kms.conf;
    then
        echo "$modprobe_entry" >> /etc/modprobe.d/nouveau-kms.conf
    fi
    update-initramfs -u

    # create startup script
    cat <<EOF > $startup_script
#!/bin/bash

cd /root

chmod +x "NVIDIA-Linux-x86_64-$latest_driver_version.run"
"./NVIDIA-Linux-x86_64-$latest_driver_version.run" -q -a -n -s 2>&1 | tee -a $driver_log_file

# so this script only runs once
systemctl disable nvidia_driver_install.service

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

}


nvidia_runtime_install()
{

    printf '\n[+] Installing Nvidia Docker runtime\n'

    curl -s -L https://nvidia.github.io/nvidia-container-runtime/gpgkey | apt-key add -
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-container-runtime/$distribution/nvidia-container-runtime.list | tee /etc/apt/sources.list.d/nvidia-container-runtime.list
    apt-get update
    apt-get install nvidia-container-runtime docker.io

    mkdir /etc/docker 2>/dev/null
    tee /etc/docker/daemon.json <<EOF
{
    "runtimes": {
        "nvidia": {
            "path": "/usr/bin/nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF

    systemctl restart docker

}


main()
{

    check_root

    # make sure we're running debian
    command -v apt-get >>"$logfile" || (printf '\n[!] This script needs the APT package manager\n\n'; exit 1)

    get_latest_driver_version

    if [ -z "$latest_driver_version" ]; then
        printf '\n[!] Failed to detect driver version\n\n'
        exit 1
    fi

    package_install

    hashcat_install

    driver_download

    prepare_driver_install

    nvidia_runtime_install

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


# dew it
main