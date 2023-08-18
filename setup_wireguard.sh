#!/bin/bash
# Script to setup wireguard server
# 2023-Aug-18 RCT V1.2

# Specs for setup_wireguard.sh
# 1. Self-contained bash script to generate server and client install packages.
# 2. Run as unprivileged user to generate install packages.
# 3. Run as privileged user to install packages.
# 4. Multiple options to manage network configurations with convenient defaults.
# 5. Create client install packages for both linux and windows systems.
# 6. Expect target server to run on linux.
# 7. Generate default values based on currently running system (useful to install on running system).
# 8. Warn if there is no firewall in target system.
# 9. Abort if any required parameter is missing.

## 0. Assign defaults
VPN_BASE=10.10.0.0
VPN_MASK=24
WG_PORT=51820
NETMASK=24
INSTALL=false
DEVELOPMENT=false
QUIET="-q"

## 1. Parse options
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--nclients)
      NCLIENTS="$2"
      shift; shift # remove option & value
      ;;
    --endpoint|--server)
      ENDPOINT="$2"
      shift; shift # remove option & value
      ;;
    --network)
      REMOTE_NETWORK="$2"
      shift; shift # remove option & value
      ;;
    --netmask)
      REMOTE_NETMASK="$2"
      shift; shift # remove option & value
      ;;
    --port)
      WG_PORT="$2"
      shift; shift # remove option & value
      ;;
    --device)
      DEVICE="$2"
      shift; shift # remove option & value
      ;;
    --vpnb)
      VPN_BASE="$2"
      shift; shift # remove option & value
      ;;
    --vpnm)
      VPN_MASK="$2"
      shift; shift # remove option & value
      ;;
    --vpns)
      VPN_SERVER="$2"
      shift; shift # remove option & value
      ;;
    --install)
      INSTALL=true
      shift # remove option
      ;;
    --what)
      echo "Sequence of tasks performed by $0:"
      grep "^## " $0
      exit 0
      ;;
    -d|--development)
      DEVELOPMENT="true"
      shift # remove option
      ;;
    -v|--verbose)
      VERBOSE="-v"
      QUIET=""
      shift # remove option
      ;;
    -h|--help)
      cat >&1 << _EOF_

 $0 generates wireguard server and client install packages for windows and linux clients.
 Since this obtains default parameters from the current network, it is safest and most
 convenient to run this script on the target server.
 This script requires zip, tar, curl, jq, and wg. (wg is in the wireguard-tools package.)

# Required parameter
  -n | --nclients; the number of client configurations to generate; no default value.

# Optional parameters
  --endpoint|--server ; remote server endpoint -- IP or DNS name (default is public IP of current server)
  --port ; wireguard UDP port (defaults to 51820)
  --network ; remote network base address (defaults to LAN network value)
  --netmask ; remote network netmask (defaults to LAN mask value; use CIDR notation, e.g. 24 instead of 255.255.255.0)
  --device ; LAN network device (defaults to default route device on LAN)
  --vpnb ; IPv4 VPN network base address (defaults to 10.10.0.0)
  --vpnm ; IPv4 VPN netmask (defaults to 24; use CIDR notation -- not really used as a mask since
           VPN connections are point-to-point.
  --vpns ; IPv4 VPN server address (defaults to VPN network base address + 1)
  --install ; Install the generated server configuration on this machine (needs sudo privileges.)
  --what ; Lists the sequence of tasks performed.
  -d | --development ; use during development to limit account lockout
  -v | --verbose ; used mostly for debugging
  -h | --help ; this output

Examples:
   # Create server and 5 client packages using all defaults; assume we are installing on this machine.
   $0 -n 5

   # Create server and 4 client packages using all defaults for specific server elsewhere.
   $0 -n 5 --endpoint mynetwork.dyndns.org --port 53000 --network 192.168.1.0 --netmask 24

NOTES:
  This tool assumes one or more external clients connecting to a simple "base" network behind a NAT firewall/router.
  Once connected, the clients can access any device on the base network LAN. The generated ZIP packages files are
  intended to simplify deployment
  The wireguard server is expected to be a linux server that runs as a LAN "client" on the base network. It must have
  the UDP port forwarded from the router's public IP to the LAN IP of the server.
  Currently setup for IPv4 only.

_EOF_
      exit 0
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # remove argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

## 2. Create utility functions

Num_To_IP() {
  NUM=$(echo $1 | tr -d \" )
  A=$(($NUM >> 24))
  B=$(( ($NUM & 0x00ffffff) >> 16))
  C=$(( ($NUM & 0x0000ffff) >> 8))
  D=$(( $NUM & 0x000000ff))
  echo $A.$B.$C.$D
}

IP_To_Num() {
  IP=$(echo $1 | tr -d \" )
  A=$(echo $IP | cut -d '.' -f1)
  B=$(echo $IP | cut -d '.' -f2)
  C=$(echo $IP | cut -d '.' -f3)
  D=$(echo $IP | cut -d '.' -f4)
  NUM=$(( (A << 24) + (B << 16) + (C << 8) + D ))
  echo $NUM
}

NM_To_Num() {
 NUM=$1
 NETMASK=$((( 0xffffffff << (32 - $NUM) ) & 0xffffffff))
 echo $NETMASK
}


checkIP() {
  _TEST=$(IP_To_Num $1)
  _DIFF=$(( $(NM_To_Num 32) - $(NM_To_Num $VPN_MASK) ))
  VPN_MAXIP=$(Num_To_IP $(( $(IP_To_Num $VPN_BASE) + $_DIFF - 1 )) )
  if [ $(IP_To_Num $VPN_BASE) -ge $_TEST ] || [ $(IP_To_Num $VPN_MAXIP) -lt $_TEST ]; then
	return 1
  fi
}

IncrementIP() {
  LAST_NUM=$(IP_To_Num $LAST_IP)
  NEXT_NUM=$((LAST_NUM + 1))
  NEXT_IP=$(Num_To_IP $NEXT_NUM)
  echo $NEXT_IP
}

CompareIP() {
  if [ $(IP_To_Num $1) -ne $(IP_To_Num $2) ]; then
    return 1
  fi
}

echoVar() {
  _TMP=$1
  echo "$_TMP=${!_TMP}"
}

advise() {
  echo -e "       Run this script with -h option.\n"
}

errorMsg() {
  _ECODE=$1
  _MSG=$2
  echo -e "\n    ERROR: $_MSG\n"
  if [ "$3" = "a" ]; then
    advise
  fi
  exit $_ECODE
}

verboseMsg() {
  local _MSG=$1
  if [ "$VERBOSE" = "-v" ]; then
    echo "$_MSG"
  fi
}

warnMsg() {
  _MSG=$1
  echo -e "\n    WARNING: $_MSG\n"
}

echoVar() {
 local vname=$1
 echo "$vname=${!vname}"
}

verboseVar() {
  verboseMsg "$(echoVar $1)"
}

ip6_prefix() {
  # Create machine-unique IPv6 prefix
  NUM_ALL=$(printf $(date +%s%N)$(cat /var/lib/dbus/machine-id) | sha1sum | cut -d ' ' -f1 | cut -c 31- )
  NUM1=$(echo $NUM_ALL | cut -c 1-2)
  NUM2=$(echo $NUM_ALL | cut -c 3-6)
  NUM3=$(echo $NUM_ALL | cut -c 7-10)
  echo fd$NUM1:$NUM2:$NUM3
}

## 3. Check for prerequisites
REQUIRED="wg zip tar curl"
MISSING=""
for PKG in $REQUIRED; do
  if ! which $PKG > /dev/null; then
    MISSING+=" $PKG"
  fi
done

if ! [ "$MISSING" = "" ]; then
  errorMsg 2 "Please install these utilities: $MISSING"
fi

## 4. Check for NCLIENTS
verboseVar NCLIENTS
if [ -z $NCLIENTS ]; then
  errorMsg 2 "Missing number of clients. Provide with the -n option." a
fi

## 5. Check that NCLIENTS < MAX_CLIENTS
MAX_CLIENTS=$(( $(NM_To_Num 32) - $(NM_To_Num $VPN_MASK) - 1))
if [ $NCLIENTS -gt $MAX_CLIENTS ]; then
  errorMsg 4 "Too many clients for VPN subnet: $VPN_BASE/$VPN_MASK."
fi

## 6. Check for interface device
if [ -z $DEVICE ]; then
# Get public interface
  DEVICE=$(ip route show | grep default | awk '{print $5}')
  if ! [ "$?" = "0" ] ; then
    errorMsg 5 "Unable to obtain public interface. Provide with --device option."
  fi
  verboseVar DEVICE
fi

## 7. Get local network/netmask for default values from DEVICE
MY_ADDRESS=$(ip -j addr | jq -c --arg D $DEVICE '.[] | select(.ifname == $D)' | jq -r --arg D $DEVICE '.addr_info | .[] | select (.label == $D) | .local')
MY_NETWORKMASK=$(ip -j route | jq -r --arg D $DEVICE --arg A $MY_ADDRESS '.[] | select(.dev == $D ) | select(.dst != "default") | select(.prefsrc == $A ) | .dst')
verboseVar MY_NETWORKMASK

## 8. Check for endpoint address
if [ -z $ENDPOINT ]; then
  ENDPOINT=$(curl icanhazip.com 2>/dev/null)
  if ! [ "$?" = "0" ] ; then
    errorMsg 4 "Unable to obtain public IP. Provide with --endpoint option." a
  fi
fi
verboseVar ENDPOINT

## 9. Check for endpoint port
verboseVar WG_PORT
if [ -z $WG_PORT ]; then
  errorMsg 5 "Missing wireguard port. Provide with --port option." a
fi

## 10. Check for remote network base; use mine as default
if [ -z $REMOTE_NETWORK ]; then
  REMOTE_NETWORK=$(echo $MY_NETWORKMASK | cut -d'/' -f1)
  if [ -z $REMOTE_NETWORK ]; then
    errorMsg 5 "Missing remote network address; unable to identify local network. Provide with --network option." a
  fi
fi
verboseVar REMOTE_NETWORK

## 11. Check for remote network netmask; use mine as default
if [ -z $REMOTE_NETMASK ]; then
  REMOTE_NETMASK=$(echo $MY_NETWORKMASK | cut -d'/' -f2)
  if [ -z "$REMOTE_NETMASK" ]; then
    errorMsg 5 "Missing remote netmask; unable to identify local netmask. Provide with --netmask option." a
  fi
fi
verboseVar REMOTE_NETMASK

## 12. Check for VPN base network
if [ -z $VPN_BASE ]; then
  errorMsg 8 "Missing VPN base network setting. Provide with --vpnb option." a
fi
verboseVar VPN_BASE

## 13. Check for VPN netmask
if [ -z $VPN_MASK ]; then
  errorMsg 9 "Missing VPN network mask setting. Provide with --vpnm option." a
fi
verboseVar VPN_MASK

## 14. Check for VPN server address
if [ -z $VPN_SERVER ]; then
  VPN_SERVER=$(Num_To_IP $(( $(IP_To_Num $VPN_BASE) + 1)) )
  if ! [ "$?" = "0" ]; then
    errorMsg 10 "Unable to set VPN Server address. Provide with --vpns option." a
  fi
fi
verboseVar VPN_SERVER

## 15. Check that VPN Server is within VPN Subnet
if ! checkIP $VPN_SERVER ; then
  errorMsg 12 "$VPN_SERVER not in subnet $VPN_BASE/$VPN_MASK. Fix server or network address."
fi

## 16. Create wireguard private key
SERVER_PRIVATE_KEY=$(wg genkey)

## 17. Extract wireguard public key
SERVER_PUBLIC_KEY=$(echo $SERVER_PRIVATE_KEY | wg pubkey)

## 18. Create server config file
SERVER_CONFIG_FILE=wg0_server.conf
cat > $SERVER_CONFIG_FILE << _EOF_
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $VPN_SERVER/32
SaveConfig = true
ListenPort = $WG_PORT

# Enable IP forwarding
PostUp = sysctl -w net.ipv4.ip_forward=1
PostDown = sysctl -w net.ipv4.ip_forward=0

# Allow forwarded packets to/from VPN device
PostUp = iptables -A FORWARD -i %i -j ACCEPT
PostUp = iptables -A FORWARD -o %i -j ACCEPT
PostDown = iptables -D FORWARD -i %i -j ACCEPT
PostDown = iptables -D FORWARD -o %i -j ACCEPT

# Configure firewall for wireguard
PostUp = iptables -A INPUT -p udp -m udp --dport $WG_PORT -m state --state NEW -j ACCEPT
PostDown = iptables -D INPUT -p udp -m udp --dport $WG_PORT -m state --state NEW -j ACCEPT

# Allow through NAT router
PostUp = iptables -t nat -A POSTROUTING -o $DEVICE -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o $DEVICE -j MASQUERADE

# For clients
#[Peer]
#PublicKey = $SERVER_PUBLIC_KEY
#AllowedIPs = $VPN_SERVER/32, $REMOTE_NETWORK/$REMOTE_NETMASK
#Endpoint = $ENDPOINT:$WG_PORT
_EOF_

#NOTE: Setup wireguard on linux or windows client with client config file and route script

## 19. Create Linux client install script
CONFIG_FILE=install_wg_client.sh
cat > $CONFIG_FILE << _EOF_
#!/bin/bash
# Run as root

# Install wireguard
apt update
apt install wireguard -y

# Move client config file
CLIENT_CONFIG=\$(ls wg0_client*.conf | tail -1)
mv \$CLIENT_CONFIG /etc/wireguard/wg0.conf
chmod go= /etc/wireguard/wg0.conf

# Enable wireguard on startup
systemctl enable wg-quick@wg0.service

# Start wireguard service
systemctl start wg-quick@wg0.service

_EOF_
chmod +x $CONFIG_FILE

## 20. Create windows client install script
CONFIG_FILE=install_wg_client.bat
cat > $CONFIG_FILE << _EOF_
@ECHO OFF
REM wireguard client install script
REM Run as administrator
SET CONFIG_DIR="C:\Program Files\WireGuard\Data\Configurations"
mkdir %CONFIG_DIR%
copy wg0_client*.conf %CONFIG_DIR%
curl -s -o wg-installer.exe https://download.wireguard.com/windows-client/wireguard-installer.exe
wg-installer
_EOF_

## 21. Create Linux server install script
SERVER_INSTALL_FILE=./install_wg_server.sh
cat > $SERVER_INSTALL_FILE << _EOF_
#!/bin/bash
# Run as root

# Install wireguard
apt update
apt install wireguard -y

# Move server config file
SERVER_CONFIG=\$(ls $SERVER_CONFIG_FILE | tail -1)
mv \$SERVER_CONFIG /etc/wireguard/wg0.conf
chmod go= /etc/wireguard/wg0.conf

# Enable wireguard on startup
systemctl enable wg-quick@wg0.service

# Start wireguard service
systemctl start wg-quick@wg0.service

_EOF_
chmod +x $CONFIG_FILE

## 22. Create client configurations
LAST_IP=$VPN_BASE
for (( CLIENT=1; CLIENT<=$NCLIENTS; CLIENT++ )); do

# Create client address
  LAST_IP=$(IncrementIP)
  if CompareIP $VPN_SERVER $LAST_IP ; then
    LAST_IP=$(IncrementIP)
  fi
  VPN_CLIENT_ADDRESS=$LAST_IP
  verboseVar VPN_CLIENT_ADDRESS

# Create wireguard client keys
  CLIENT_PRIVATE_KEY=$(wg genkey)
  CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)

# Create client config file
  CONFIG_FILE=wg0_client${CLIENT}.conf
  cat > $CONFIG_FILE << _EOF_
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $VPN_CLIENT_ADDRESS/$VPN_MASK

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
AllowedIPs = $VPN_SERVER/32, $REMOTE_NETWORK/$REMOTE_NETMASK
Endpoint = ${ENDPOINT}:$WG_PORT
_EOF_

# Create Linux install package
  ARCHIVE_FILES="install_wg_client.sh install_wg_client.bat"
  zip $QUIET wg_client${CLIENT}.zip $ARCHIVE_FILES $CONFIG_FILE
  if ! [ "$DEVELOPMENT" = "true" ]; then
    rm $CONFIG_FILE
  fi

## 23. Append client to server config
  cat >> $SERVER_CONFIG_FILE << _EOF_

[Peer]
# Client # $CLIENT
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $VPN_CLIENT_ADDRESS/32
_EOF_

done
chmod +x $SERVER_INSTALL_FILE

# End Create Client configurations

## 24. Install or package server files
SERVER_ARCHIVE_FILES="$SERVER_INSTALL_FILE $SERVER_CONFIG_FILE"
if [ "$INSTALL" = "true" ]; then
  sudo $SERVER_INSTALL_FILE
  if ! [ "$?" = "0" ]; then
    errorMsg 21 "Unable to install server package."
  fi

  if [ "$DEVELOPMENT" = "true" ]; then
    rm $SERVER_INSTALL_FILE
  fi
else
  tar ${VERBOSE}czf wg_server.tgz $SERVER_ARCHIVE_FILES
fi

## 25. Cleanup
if ! [ "$DEVELOPMENT" = "true" ]; then
  rm $ARCHIVE_FILES
  rm $SERVER_ARCHIVE_FILES
fi
