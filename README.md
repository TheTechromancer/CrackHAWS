# CrackHAWS
### A road warrior AWS hashcat setup script

## NOTE: NOWADAYS, THE BEST WAY TO GET WORKING DRIVERS IS JUST TO USE THE AMAZON LINUX GPU AMI

### Features:
* No arguments or user interaction required
* Installs latest version of hashcat (from hashcat.net)
* Installs latest Nvidia driver (from nvidia.com)
* Installs latest Nvidia Docker runtime (from nvidia.com)

### Please be aware:
* Tested on Ubuntu only
* The latest official hashcat and nvidia binaries are used - not your distro's packages.

### Usage:
~~~
$ sudo ./crackhaws.sh
~~~

### Download wordlists:
~~~
$ git clone https://github.com/berzerk0/Probable-Wordlists.git
$ cd Probable-Wordlists/Real-Passwords
$ apt install deluged deluge-console
$ deluged
$ deluge-console
>>> add ProbWL-v2-Real-Passwords-7z.torrent
~~~