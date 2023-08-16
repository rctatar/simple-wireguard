## simpleguard -- a script to simplify wireguard deployment

Jason Donenfeld's beautiful kernel creation (<https://wireguard.com>) is elegant and efficient. Nevertheless,
some find it to be time-consuming to deploy as a VPN tool in their legacy environments. This project
(a bash script for a debian linux) is intended to simplify some of the work required for deployment by automating the creation of 
configuration files and installer scripts for devices in a wireguard VPN.

This tool assumes the following:

1. There is a simple, private *base network* behind a NAT firewall/router.
2. The *base network* has several devices or services for clients on the base network.
3. One or more external clients desire to connect to the *base network*.
4. A linux machine on the *base network* will run wireguard to provide a VPN service over a single interface.
5. The *base router* is configured to forward a chosen UDP port to the linux machine.
6. Client routers are configured to allow UDP traffic to the chosen UDP port of the *base router*.
7. The external clients should remain isolated from eachother.
8. The *base router* has a static, public IP address or a dynamic IP service is used, such as dyndns.org.
9. Several executables are installed on the server used to generate the files: zip, tar, curl, jq, wg (wireguard-tools)

```
Here is a schematic example of such a network with three clients and three workstations 
in the base network. The remote clients want to use a remote-desktop application on a
PC at home (behind home routers) to access their respective workstations:

                                __________
Client1 --- Client1 Router --- |          |
                               |          | --- Base Router ------- File Server
Client2 --- Client2 Router --- | Internet |                    |--- Printer
                               |          |                    |--- Camera
Client3 --- Client3 Router --- |          |                    |--- Workstation1
                               |__________|                    |--- Workstation2
                                                               |--- Workstation3
                                                                --- Linux VPN Server

```
To setup such a VPN, each client and the server require a wireguard configuration file.
There are several pieces of information that are needed and the information must be consistent.

1. Identify public IP address of base router and provide to client configuration files.
2. Choose UDP port and provide to all configuration files.
3. Choose VPN address for server and provide to all configuration files.
4. Choose VPN address for each client and provide to the client and server configuration files.
5. Identify base network LAN address and netmask and provide to the client configuration files.
6. Generate forwarding and firewall rules for server configuration file.
7. Generate server key-pair and provide server public key to client configuration files.
8. Generate client key-pairs and provide client public keys to server configuration file.

The script attempts to make sensible choices. If run on the target server in the target location,
it collects required information about the local network. 

All parameters can be overridden with command-line options. A list of command-line options is shown here:

```
  -n | --nclients; the number of client configurations to generate; no default value.
  --endpoint|--server ; remote server endpoint -- IP or DNS name (default is public IP of current server)
  --port ; wireguard UDP port (defaults to 51820)
  --network ; remote network base address (defaults to LAN network value)
  --netmask ; remote network netmask (defaults to LAN mask value; use CIDR notation, e.g. 24 instead of 255.255.255.0)
  --device ; LAN network device (defaults to default route device on LAN)
  --vpnb ; IPv4 VPN network base address (defaults to 10.10.1.0)
  --vpnm ; IPv4 VPN netmask (defaults to 24; use CIDR notation -- not really used as a mask since
           VPN connections are point-to-point.
  --vpns ; IPv4 VPN server address (defaults to VPN network base address + 1)
  --install ; Install the generated server configuration on this machine (needs sudo privileges.)
  --what ; Lists the sequence of tasks performed.
  -d | --development ; use during development to limit account lockout
  -v | --verbose ; used mostly for debugging
  -h | --help ; this output
```

View options at any time by running "./setup_wireguard.sh -h".


## Usage Examples

For a static public IP, the script can find the required information and make choices for you. 
In this case, the only required parameter is the number of client configuration files to create.

### To generate files for server and four clients

Run:

    ./setup_wireguard.sh -n 4

This will create a server archive and four client ZIP files.


### To generate files for four clients and install in one step

If you have sudo privileges, you can just run

    ./setup_wireguard.sh -n 4 --install


### To install the server 

On a debian-based system (i.e. with an apt package manager), extract the server archive and run the install script:

    tar xvzf wg_server.tgz
    sudo ./install_wg_server.sh


### To specify a Dynamic DNS name

If your router uses a dynamic DNS service, you can specify the name with the --endpoint option.

For example:

    ./setup_wireguard.sh -n 4 --endpoint myname.dyndns.org --install


### To select a specific interface on the server

If your server is multi-homed, you may need to use the --device option:

    ./setup_wireguard.sh -n 4 --endpoint myname.dyndns.org --device eth1


### To install clients

1. copy the client zip file to the client
2. unzip the archive
3. open a command shell as an administrator
4. navigate to the directory with the unpacked files
5. run the batch script (install_wg_client.bat)


```
2023-Aug-16 
Bob Tatar
```

TODO:
- create self-extracting scripts to eliminate need for zip and tar
