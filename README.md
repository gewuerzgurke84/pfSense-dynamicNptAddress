# pfSense-dynamicNptAddress

# Purpose
I would like to provide IPv6 ULA addresses for several services to internal clients (e.g. IPv6 DNS Server). Unfortunetely my ISP changes my IPv6 prefix on a regular basis, thus I cannot use public GUA addresses to hand out to the clients. I decided to use [pfSense NPT](https://docs.netgate.com/pfsense/en/latest/nat/npt.html) feature to allow mapping between ULA and GUA addresses.
There is already a feature request open but I don't know in which version pfSense NPT can handle dynamic prefixes (and accept the reality in Germany at least):
- https://redmine.pfsense.org/issues/4881

# Implementation
The script uses a 3rd party pfSense API to obtain current configured NPT destination prefix (using the interface name npt_iface). It compares this prefix with the prefix of a system's interface IPv6 address. In case they differ it updates the NPT destination prefix.

# Limitations
I've tested this with:
* pfSense 2.5.0
* fauxAPI 1.4
* 1 NPT mapping
* 1 system "Tracking" interface
* /64 Prefix Size

# Installation
## Requirements
Please make sure to have following packages installed: 
* git (at least for the setup)
* jq
* bash
* awk / head / cut
* cron to let the script run regularly

## Setup FauxAPI
* I dediced to use FauxAPI to have easy access to pfSense configuration. I've installed it using this instructions: https://github.com/ndejong/pfsense_fauxapi/blob/master/README.md
* Install the bash client library into a convienent place (I've used /root/bin): 
`mkdir -p /root/bin && cd /root/bin && git clone https://github.com/ndejong/pfsense_fauxapi_client_bash.git`

## Install update script
* `mkdir -p /root/bin && cd /root/bin && curl https://raw.githubusercontent.com/gewuerzgurke84/pfSense-dynamicNptAddress/main/updateNptDestPrefix.sh > updateNptDestPrefix.sh && chmod +x updateNptDestPrefix.sh`

## Adjust the parameter section of the script to your needs
* Set fauxapi apiKey+apiSecret+path to fauxapi client script
* Set NPT interfaces and System interfaces that should stay in sync
   *  npt_iface is the NPT interface to perform ULA<->GUA Mapping
   * npt_sysiface is the Systems interface with dynamic prefix

## Add a cron
* Setup a cron to regulary check if NPT and system interface prefix matches

