#!/bin/bash

#
# Author:		gudgip, DipSwitch, trixter
# Function:		make connection using non password, WEP, WPA, WPA2
# 
# CopyLeft this script may be used and altered freely
#

# Configuration defaults
DEFAULT_LOGFILE="/var/log/wicon.log";
DEFAULT_TYPE="";
DEFAULT_KEYTYPE="ASCII";
DEFAULT_PASSWORD="";
DEFAULT_INTERFACE="";
DEFAULT_DRIVER="";
DEFAULT_SAFE_CONFIG=1;
DEFAULT_CONFIG_DIR="${HOME}/.config/wicon/";
DEFAULT_MAIN_CONFIG="${HOME}/.config/wicon/config.wcs";
DEFAULT_TEMP_FILE="`mktemp -u /tmp/wicon.XXXX`";

# ------------------- You don't have to read below this line, you can but I know you don't want to =)

# cleanup routine on interrupt
function cleanup() {
    [ -f "$DEFAULT_TEMP_FILE" ] && rm "$DEFAULT_TEMP_FILE";
	
    # TODO keep this file?
    [ -f "$DEFAULT_LOGFILE" ] && rm "$DEFAULT_LOGFILE";
	
    PROPERCALL=$1;
	
    if [ -z $PROPERCALL ]; then
	echo "" 1>&2;
	PROPERCALL=1;
	stderr "Interrupted!! Cleaned up files!";
    fi;
	
    safe_config;

    trap - INT TERM HUP
	
    exit $PROPERCALL;
}

trap cleanup INT TERM HUP

# function that prints the usage
function usage()
{
    cat << EOF
usage: $0 options

New mode: Pr0 m0d3, now if run the application without any arguments, it will first search for any known AP to connect to
                    if we found a matching config we'll auto connect. If none is found we print the scan output.

This script can be used to quickly setup an connection to an wireless network.
The settings are stored in ${DEFAULT_MAIN_CONFIG} so the last settings will always be saved.
This allows you to restore the last known working connection by calling the application without arguments.
OPTIONS:
-e  ESSID
-b  Hidden SSID network
-p  Password for the ESSID
-t  Password type (WPA, WPA2, WEP) (DEPRECATED)
-k  Key type (used for WEP [hex|ascii]) default: ascii
-i  Interface
-l  Log File
-r  Reload driver using the default given driver in this file
-R  Reload driver using the given driver
-g  Only generate config file
-q  Quiet mode
-c  Config file
-P  Print the configurations
-s  Scan for networks
-h  Show this message
-v  Version

USAGE:
Pr0 m0d3: $0
Open Network: $0 -e ESSID
Auto Detection: $0 -e ESSID -p PASSWORD

AUTHOR(S):
gudgip
DipSwitch
trixter
EOF
}

# function that prints the version
function version()
{
    cat << EOF
$0 v1.0 by gudgip, DipSwitch, trixter

Report bugs to https://github.com/DipSwitch/wicon/issues/
Home page: https://github.com/DipSwitch/wicon/
EOF
}

# function for testing the interface
function iswifi()
{
    if [[ -z $1 ]]; then
	stderr "No interface given please use '-i' flag";
	return 3;
    fi;

    iwconfig $1 > /dev/null 2>&1;

    case $? in
	161)
	    stderr "$1 is not an wireless extension";
	    return 1;
	    ;;
	237)
	    stderr "$1 does not exists";
	    return 2;
	    ;;
    esac;

    # apparently we have a wifi device called $1 let's bring it up just to be sure
    ifconfig $1 up;

    RETVAL=$?;
    if [ $RETVAL -ne 0 ]; then
	stderr "$1 could not be brought up with ifconfig";
    fi;

    return $RETVAL;
}

# function to safe the AP config
function safe_ap_config()
{
    TRUE_FILE="${CONFIG_DIR}/${ESSID}.wc";
    cat > "${TRUE_FILE}" << EOF
ESSID="$ESSID";
RELOAD=$RELOAD;
BROADCAST=$BROADCAST;
TYPE="$TYPE";
KEYTYPE="$KEYTYPE";
MAC="$MAC";
EOF

    if [ "${TYPE}" == "WEP" ]; then
	echo "PASSWORD=\"${PASSWORD}\"" >> "${TRUE_FILE}";
    elif [ "${TYPE}" == "wpaa" ]; then
	echo "PSK=`echo $PSK | grep -o '[A-Fa-f0-9]*'`;" >> "${TRUE_FILE}";
    fi;

    #return cat exit level
    ret=$?;
	
    if [[ $ret -eq 0 ]]; then
	stdout "Settings successfully saved.";
    else
	stderr "Error saving the configuration file '${TRUE_FILE}'";
    fi

    unset TRUE_FILE;

    return $ret;
}

# function to safe the config to the given config
function safe_config()
{
    cat > "${DEFAULT_MAIN_CONFIG}" <<EOF
INTERFACE="$INTERFACE";
LOGFILE="$LOGFILE";
DRIVER="$DRIVER";
QUIET=$QUIET;
CONFIG_DIR="${CONFIG_DIR}"
EOF

    #return cat exit level
    ret=$?;
	
    if [[ $ret -ne 0 ]]; then
	stderr "Error saving the configuration file '${DEFAULT_MAIN_CONFIG}'";
    fi

    unset TRUE_FILE;

    return $ret;
}

# function to write to the standard out stream
function stdout()
{
    if [[ $QUIET -eq 0 ]]; then
	echo "[+] $1";
    fi
}

# function to write to the standard error stream
function stderr()
{
    if [[ "$1" = "-n" ]]; then
	echo -n "[-] $2" 1>&2;
    else
	echo "[-] $1" 1>&2;
    fi
}

# tests if an application can be found using the current $PATH setting
function function_exists()
{
    if [[ -z $1 ]]; then
	return 0;
    fi

    which $1 &> /dev/null;

    return $?
}

# iwlist wrapper function also used to get the settings of wpa1/2
function iwlist_wrapper()
{
# check if an essid is given, if so use the function only to set the GROUP, PAIRWISE and PROTO var (so less printing)
    if [[ ! -z "$1" ]]; then
	NESSID="$1";
    fi;
	
    FOUND_AWK=0;
    COMMAND="iwlist $INTERFACE scan";
	
    if [[ ! -z $NESSID ]]; then
	COMMAND="$COMMAND essid \"$NESSID\"";
    fi
	
    COMMAND="$COMMAND 2> /dev/null";

    if function_exists awk; then
	FOUND_AWK=1;
	COMMAND="$COMMAND | awk ";

	if [[ ! -z $NESSID ]]; then
	    COMMAND="$COMMAND -v \"nessid=$NESSID\" ";
	fi;
		
        # TODO: Needs loats of optimizing I guezz, quick and dirty this is... ;)
	COMMAND="$COMMAND 'function printall () {
# add wep if no wpa found
if (ENCRYPTION == \"on\" && WPA == \"\") {
 WPA=\"[WEP]\"
 if ( nessid == ESSID ) {
  print \"TYPE=\\\"wep\\\"\"
 }
} else if (ENCRYPTION == \"off\") {
 WPA=\"[OPEN]\"
 FRONT=\"* \"
}

if ( nessid && inwpa > 0 ) {
 if ( inwpa == 1 ) {
  proto = \"WPA\"
 } else if ( inwpa == 2) {
  proto = \"RSN\"
 }
		
 print \"TYPE=\\\"wpaa\\\"\" # create work around to always set this even though 
 print \"WPA_PROTO=\\\"\" proto \"\\\"\"
 print \"WPA_PAIRWISE=\\\"\" pairwise \"\\\"\"
 print \"WPA_GROUP=\\\"\" pairwise \"\\\"\"
 print \"MAC=\\\"\" BSSID \"\\\"\"
 found_type = 1
} else if ( ! nessid ) {
 print cnt \" \" FRONT \"[\"BSSID\"] > \" ESSID \" [\" MODE \"] \" QUALITY \" \" WPA
}
	
WPA=\"\"
QUALITY=\"\"
MODE=\"\"
ESSID=\"\"
FRONT=\"\"
inwpa=0
}

BEGIN {
 OFS=\"\"
}
{
 if (\$1 == \"\") {
  printall()
 } else if (\$1 == \"Cell\") {
  if (cnt != \"\") {
   printall()
  }
  cnt = \$2
  BSSID = \$5
 } else {
  # remove leading whitespace, it was messing with me
  split(\$0, gah)
  split(gah[1], a, \":\")
  if (a[1] == \"ESSID\") {
   split(\$0,e,\"\\\"\")
   ESSID=e[2]
 } else if (a[1] == \"Mode\") {
  MODE=a[2]
 } else if (a[1] == \"Encryption\") {
  split(gah[2], crypt, \":\")
  ENCRYPTION = crypt[2]
 } else if (a[1] == \"IE\") {
  x=2
  if (gah[2] != \"Unknown:\") {
   if ( nessid == ESSID && gah[2] == \"IEEE\" ) {
    inwpa = 2
   } else if ( nessid == ESSID && gah[2] == \"WPA\" && inwpa <= 1 ) {
    inwpa = 1
   }

   W=gah[2]
   for (i = 3; i <= NF; i++) {
    W =  W \" \" gah[i]
   }
   WPA = WPA \"[\" W \"] \"
  }
 } else if (inwpa > 0 ) {
  if ( a[1] != \"Extra\" ) {
   if ( a[1] == \"Group\" ) {
    group = gah[4]
   } else if ( a[1] == \"Pairwise\" ) {
    pairwise = gah[5] \" \" gah[6]
   } else if ( a[1] == \"Authentication\" ) {
    auth = gah[5] \" \" gah[6]
   }
  }
 } else {
  split(gah[1],a,\"=\")
  if (a[1] == \"Quality\") {
   QUALITY = a[2]
  }
 }
}
}'"
    fi;

    if [[ ! -z "$NESSID" ]]; then
	COMMAND="$COMMAND > \"$DEFAULT_TEMP_FILE\"";
    fi;

    COMMAND="$COMMAND; iwlist wlan1 scan > /dev/null 2> /dev/null;";

    # kind of bruteforce, but it's the only way I can think of, maybe only call iwscan once and cache output?
    # one retry is enough, we choose three to be save.
    RETRIES=3;
    while ! eval "$COMMAND" && [ $RETRIES -ne 0 ] && [ ! -z "$NESSID" ]; do
        # set interface up with ifconfig, sometimes the interface goes down
	ifconfig $INTERFACE up;
	(( RETRIES-- ));
    done;

    if [[ $FOUND_AWK -eq 0 ]]; then
	stderr "Please install awk to get a shorter fancy list.";
	return 1;
    fi;
	
    return 0;
}

# RUNTIME VARIABLES, DO NOT CHANGE! Check above ;)
ESSID="";
PASSWORD="$DEFAULT_PASSWORD";
DRIVER="$DEFAULT_DRIVER";
INTERFACE="$DEFAULT_INTERFACE";
RELOAD=0;
QUIET=0;
BROADCAST=0;
LOGFILE="$DEFAULT_LOGFILE";
PSK=;
TYPE="$DEFAULT_TYPE";
KEYTYPE="$DEFAULT_KEYTYPE"; 
GENERATE_CONF_ONLY=0;
CONFIG_DIR="$DEFAULT_CONFIG_DIR";
CONFIG="$DEFAULT_MAIN_CONFIG";
SCAN=0;
ARGESSID="";
PRINT_CONFIG=0;
# EOV

# make the config dir if it doens't exist
[ ! -d "${DEFAULT_CONFIG_DIR}" ] && mkdir -p "${DEFAULT_CONFIG_DIR}";

# We need to load the config file first because we might want to change excisting variables
FOUND_CONFIG=0;
for i in $*; do
    if [[ "$i" = "-c" ]]; then
        #found config flag change config file on next iteration
	FOUND_CONFIG=1;
    elif [[ $FOUND_CONFIG -eq 1 ]]; then
	CONFIG="$i";
	stdout "Config file changed to: $CONFIG";
	FOUND_CONFIG=0;
    fi
done;
unset FOUND_CONFIG;

# these are our settings from the last script run
if [[ -a "$CONFIG" ]]; then
    . "$CONFIG";
fi

# checking if commands are installed
APPS="ifconfig
iwconfig
wpa_passphrase
wpa_supplicant
killall
dhclient
iwlist";

for ap in $APPS; do
    if ! function_exists $ap; then
	stderr "Make sure $ap is installed and that it's can be found using the \$PATH variable.";
	exit 1;
    fi;
done;

# require root access (or unless the sticky bit is set on iwconfig and owned by root)
# BUG: Logging won't work properly with sticky bit set, need to make work around
if [[ $(/usr/bin/id -u) -ne 0 && $(ls -l `type iwconfig | awk '{print $3}'` | awk '{print substr($1,4,1) $3}') != "sroot" ]]; then
    stderr "Not running as root!";
    stderr "Use \"sudo $0\" to run this program correctly.";
    exit 1;
fi

while getopts "bi:t:k:l:e:p:c:rR:qvhgsP" opt; do
    case $opt in
	e) if [[ "$ESSID" != "$OPTARG" ]]; then
	    LOGFILE="$DEFAULT_LOGFILE";
            TYPE="$DEFAULT_TYPE";
	    PASSWORD="$DEFAULT_PASSWORD";
	   fi;
	    
	   ESSID=$OPTARG
	   ARGESSID=$OPTARG ;; # TODO: Remove since it's not needed, just for debugging

        b) BROADCAST=1 ;;
	p) PASSWORD=$OPTARG ;;
	l) LOGFILE=$OPTARG ;;
#	t) if [[ "$OPTARG" == "wep" || "$OPTARG" == "wpa" || "$OPTARG" == "wpa2" || "$OPTARG" == "" ]]; then
#	       TYPE=$OPTARG;
#	   else
#	       stderr "only 'wep', 'wpa' and 'wpa2' are valid values for password type!";
#	       exit 1;
#	   fi;
#	   ;;
	k) if [[ "$OPTARG" = "ascii" || "$OPTARG" = "hex" ]]; then
	       KEYTYPE=$OPTARG;
	   else
	       stderr "only 'ascii' and 'hex' ar valid values for key type!";
	       exit 1;
	   fi;
	   ;;
	r) RELOAD=1 ;;
	i) if iswifi "$OPTARG"; then
	       INTERFACE=$OPTARG;
	   else
	       exit 1;
	   fi
	   ;;
	R) DRIVER=$OPTARG; RELOAD=1 ;;
	g) GENERATE_CONF_ONLY=1 ;;
	q) QUIET=1 ;;
	s) SCAN=1 ;;
	P) PRINTCONFIG=1; ;;
	v) version; exit 0; ;;
	h) usage; exit 0; ;;
	\?) usage; exit 1; ;;
	:) usage; exit 1; ;;
    esac
done

stdout "Starting $0 script";

if ! iswifi $INTERFACE; then
    exit 1;
fi

# TODO when no argument is given, scan all AP's and see if we find one in our config dir
if [[ -z $ESSID && $SCAN -eq 0 && $GENERATE_CONF_ONLY -eq 0 ]]; then
    # check if we find an ESSID in our config dir
    IFS_B="$IFS";
    IFS=$'\n';
    FOUND_AP=0;

    for essid in `iwlist ${INTERFACE} scan | grep ESSID`; do
	essid="`echo $essid | sed -Es 's/^[ ]*ESSID:"([a-zA-Z0-9 !_-]+)"$/\1/g'`"
	if [ -f "${DEFAULT_CONFIG_DIR}/${essid}.wc" ]; then
	    # found config for this AP, source config and continue
	    . "${DEFAULT_CONFIG_DIR}/${essid}.wc";
	    stdout "Loaded config for AP: $essid";

	    FOUND_AP=1;

	    break;
	fi;
    done

    IFS="$IFS_B";

    # if non found set SCAN to 1
    [ $FOUND_AP -eq 0 ] && SCAN=1;
fi

if [[ $PRINTCONFIG -eq 1 ]]; then
    cat $CONFIG;
    exit 0;
fi

if ! iswifi $INTERFACE; then
    exit 1;
fi

if [[ $SCAN -eq 1 ]]; then
    iwlist_wrapper "$ARGESSID";

    safe_config;

    exit 0;
fi

if [[ $GENERATE_CONF_ONLY -eq 1 ]]; then
    safe_config;
    exit 0;
fi

killall wpa_supplicant &> $LOGFILE
killall dhclient &> $LOGFILE
touch $LOGFILE
if [[ $RELOAD -eq 1 ]]; then
    # Load our driver first if needed
    # rt61pci/rt2x00 is bugged, so we copy this file we downlaoded to /lib/firmware/
    # cp rt2561.bin /lib/firmware/
    stdout "Reloading driver $DRIVER"
    rmmod $DRIVER &> $LOGFILE
    modprobe $DRIVER
fi

WPA_PROTO="";
WPA_PAIRWISE="";
WPA_GROUP="";
WPA_KEY_MGMT="WPA-PSK"; # TODO: Add MGMT parsing

# SHOULD ALWAYS BE TRUE WHEN PASS IS GIVEN NOW..
if [[ -z "$TYPE" || "$TYPE" == "wpaa" && "$PASSWORD" != "" || "$PSK" != "" ]]; then
    if function_exists awk && [[ "$TYPE" == "" || "$TYPE" == "wpaa" ]]; then
	iwlist_wrapper "$ESSID";
	
	if [[ $(wc "$DEFAULT_TEMP_FILE" | awk '{print $3}') == "0" ]]; then
	    stderr "The network couldn't be found or a parsing error occured.";
	    exit 1;
	fi;
    else
	stderr "AWK Not found and no encryption type given, work your magic or use the -t flag.";
	exit 1;
    fi
elif [[ "${PASSWORD}" != "" && "$PSK" != "" ]]; then
    stderr "Shouldn't get here, fill me a bug report!";
    exit 1;
fi

if [[ -f "$DEFAULT_TEMP_FILE" ]]; then
    MAC_STORED="${MAC}";

    . "$DEFAULT_TEMP_FILE";

    if [[ ! -z "${MAC_STORED}" && "${MAC}" != "${MAC_STORED}" ]]; then
	stderr "The MAC address doesn't match the one stored in the config file, I guess somebody is trying to make a funny.";
	stderr "Stored MAC: ${MAC_STORED} Current Active: ${MAC}";
	exit 1;
    fi;
fi

if [[ ! -z $PASSWORD || ! -z $PSK && $TYPE == "wpaa" ]]; then
    stdout "Generating new wpa_supplicant file"
    
    if [ ! -z $PASSWORD ]; then
	PSK=$(wpa_passphrase "$ESSID" "$PASSWORD" | grep 'psk' | tail -1)
    else
        # it must be an PSK we are having, nothing to be done
	PSK="psk=${PSK}";
    fi;
	
    SCAN_SSID="#	scan_ssid=1";
    
    if [[ -z $WPA_PROTO || -z $WPA_PAIRWISE || -z $WPA_GROUP ]]; then
        # all abort the fail boot!
        stderr "Autoparsing didn't understand shit iwlist was telling it... send the output of iwlist $INTERFACE scan and the distro info to debug address...";
	exit 1;
    fi;

    if [[ $BROADCAST -eq 1 ]]; then
	SCAN_SSID=${SCAN_SSID//#/};
    fi

    cat > /etc/wpa_supplicant.conf << EOF
network={
    ssid="$ESSID"
    proto=$WPA_PROTO
$SCAN_SSID
    key_mgmt=$WPA_KEY_MGMT
    pairwise=$WPA_PAIRWISE
    group=$WPA_GROUP
    $PSK
}
EOF
fi

# start making the connection itself
stdout "Start making our connection to '$ESSID' on '$INTERFACE'"

iwconfig $INTERFACE essid "$ESSID" &> $LOGFILE

if [[ ! -z $PASSWORD && $TYPE == "wpaa" || $PSK != "" ]]; then
    stdout "Starting wpa_supplicant on $INTERFACE";
    iwconfig $INTERFACE key off;
    wpa_supplicant -B -Dwext -i $INTERFACE -c /etc/wpa_supplicant.conf &> $LOGFILE
elif [[ ! -z $PASSWORD && $TYPE == "wep" ]]; then
    stdout "Setting the WEP key using key type: $KEYTYPE";
	
    COMMAND="iwconfig $INTERFACE key";
	
    if [[ $KEYTYPE == "ascii" ]]; then
	COMMAND="$COMMAND s:$PASSWORD";
    else # must be hex since only 2 values possible
	COMMAND="$COMMAND $PASSWORD";
    fi
	
    eval "$COMMAND"
elif [[ -z $PASSWORD ]]; then
    iwconfig $INTERFACE key off;
fi;

stdout "Starting dhclient on $INTERFACE";
dhclient $INTERFACE &> $LOGFILE
if ping -q -c 1 www.google.com &> /dev/null; then
    stdout "Script executed successfully!";
	
    if [[ $DEFAULT_SAFE_CONFIG -eq 1 || "$CONFIG" != "$DEFAULT_CONFIG" ]]; then
	safe_ap_config;
    fi;
else
    stderr "Script failed! (Or ping blocked by firewall or you broke the interwebz!!)";
    stderr "'ifconfig $INTERFACE' dump:";
    ifconfig $INTERFACE 1>&2;
    SAFE=0;
    while [[ $SAFE -eq 0 && $QUIET -eq 0 ]]; do
	stderr -n "Do you still want to safe the configuration? [y/n] ";
	read ans
	if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
	    safe_ap_config;
	    SAFE=1;
	elif [[ "$ans" == "n" || "$ans" == "N" ]]; then
	    SAFE=1;
	fi
    done
fi

cleanup 0;
