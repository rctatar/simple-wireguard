# simpleguard
Simple Wireguard Setup
2023-Aug-18 
Bob Tatar

Jason Donenfeld's beautiful creation (wireguard.com) is elegant and efficient. Nevertheless, some 
people find it to be time-consuming to deploy as a VPN tool in their legacy environments. This project
is intended to simplify some of the work required for deployment by automating the creation of 
configuration files and installer scripts for devices in a wireguard VPN.

This tool assumes the following:

1. There is a simple, private "base" network behind a NAT firewall/router.
2. The base network has several devices or services for clients on the base network.
3. One or more external clients desire to connect to the base network.
4. A linux machine on the base network will run wireguard to provide a VPN service over a single interface.
5. The base router is configured to forward a chosen UDP port to the linux machine.
6. Client routers are configured to allow UDP traffic to the chosen UDP port of the base router.
7. The external clients should remain isolated from eachother.
8. The base-router has a static, public IP address or a dynamic IP service is used, such as dyndns.org.

                                __________
CLIENT1 --- Client1_Router --- |          |
                               |          | --- Base_Router ------- File Server
CLIENT2 --- Client2_Router --- | Internet |                    |--- Printer
                               |          |                    |--- Camera
CLIENT3 --- Client3_Router --- |          |                    |--- Workstation1
                               |__________|                    |--- Workstation2
                                                               |--- Workstation3
                                                                --- Linux VPN Server

To setup such a VPN, each client and the server require a wireguard configuration file.
There are several piecs of information that are needed and the information must be consistent.

1. Identify public IP address of base router and provide to client configuration files.
2. Choose UDP port and provide to all configuration files.
3. Choose VPN address for server and provide to all configuration files.
4. Choose VPN address for each client and provide to the client and server configuration files.
5. Identify base network LAN address and netmask and provide to the client configuration files.
6. Generate forwarding and firewall rules for server configuration file.
7. Generate server key-pair and provide server public key to client configuration files.
8. Generate client key-pairs and provide client public keys to server configuration file.

The script attempts to make sensible choices. If run on the target server, it collects required 
information about the local network. All parameters can be overwritten with command-line
options.  View the options by running "./setup_wireguard.sh -h".



EXAMPLE USAGE

For a static public IP, the script can find the required information and make choices for you.
In this case, the only required parameter is the number of client configuration files to create.

For example, for four clients, just run:

./setup_wireguard.sh -n 4

This will create a server archive and four client ZIP files.

If your router uses a dynamic DNS service, you can specify the name with the --endpoint option.

For example:

./setup_wireguard.sh -n 4 --endpoint myname.dyndns.org
