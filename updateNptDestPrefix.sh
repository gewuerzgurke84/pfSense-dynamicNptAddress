#!/usr/local/bin/bash

######################################
## Required:
## - fauxapi
## - bash
## - jq
## - head
## - awk
######################################

#
# 0 - Setup
# 

# Connection to fauxapi (update to your needs/environment)
fauxapi_script="/root/bin/pfsense_fauxapi_client_bash/sources/pfsense-fauxapi.sh"
fauxapi_host="127.0.0.1"
fauxapi_apikey="yourFauxApiKey"
fauxapi_apisecret="yourFauxApiSecret"
fauxapi_scheme="http"

# Configuration
npt_iface="wan"
npt_sysiface="igb1"

# Include Bash Client Lib
source $fauxapi_script

# Build Auth
export fauxapi_auth=$(fauxapi_auth ${fauxapi_apikey} ${fauxapi_apisecret})

cleanup() {
	rm /tmp/$$.*
}

#
# 1 - Obtain configured NTP Destination Address
#
echo "[1] Obtaining configured NPT destination address of $npt_iface"

# Get config
curl -L -X GET --silent --insecure --header "fauxapi-auth: ${fauxapi_auth}" "${fauxapi_scheme}://${fauxapi_host}/fauxapi/v1/?action=config_get" > /tmp/$$.config_get
# Get config npt dest
cat /tmp/$$.config_get | jq ".data.config.nat.npt[] | select(.interface==\"${npt_iface}\")" > /tmp/$$.config_npt_dest
# Get current npt dest addr
npt_dstAddr=$(cat /tmp/$$.config_npt_dest | jq -r .destination.address)
echo "[1] ... Current NPT Destination Address: $npt_dstAddr"
# Check
if [ -z "$npt_dstAddr" ]; then
	echo "[1] ... Cannot get configured address, giving up"
	cleanup
	exit -1
fi


#
# 2 - Obtain current IPv6 GUA Address
#
echo "[2] Obtaining IPv6 address of $npt_sysiface"

# Get interface addr
addresses=$(ifconfig $npt_sysiface | grep inet6 | grep 2001 |awk '{print $2}')
# Check if only one address found
checkaddresses=$(echo $addresses | wc -l)
if [ $checkaddresses != "1" ]; then
	echo "[2] ... Unexpected number of GUA addresses (must be 1): $addresses"
	cleanup
	exit -2
fi
echo "[2] ... Current GUA Address: $addresses"

#
# 3 - Compare Prefix and update if required
#
echo "[3] Check if sys interface and npt interface are configured correctly"

ntp_prefix=$(echo $npt_dstAddr |head -c 19)
sys_prefix=$(echo $addresses |head -c 19)
if [ "$ntp_prefix" != "$sys_prefix" ]; then
	echo "[3] ... NPT and interface prefix, differ, let's update"
	npt_patch=$(cat /tmp/$$.config_npt_dest)
	new_npt_dest="${sys_prefix}::/64"
	echo "[3] ... Patching NPT dest address from $npt_dstAddr to $new_npt_dest"
	# Build patch json
	echo '{ "nat": { "npt": [' > /tmp/$$.config_patch
	echo "${npt_patch/$npt_dstAddr/$new_npt_dest}" >> /tmp/$$.config_patch
	echo '] } }' >> /tmp/$$.config_patch
	curl -L -X POST --silent --insecure --header "fauxapi-auth: ${fauxapi_auth}" --header "Content-Type: application/json" --data @/tmp/$$.config_patch "${fauxapi_scheme}://${fauxapi_host}/fauxapi/v1/?action=config_patch"
	patchResponse=$?
	if [ "$patchResponse" != "0" ]; then
		echo "[3] ... Patching NTP dest address failed ($patchResponse)"
		cleanup
	else
		echo "[3] ... Patching NTP dest address succesfully"
	fi
else
	echo "[3] ... NPT prefix matchs interface prefix, everything is fine (NTP: $ntp_prefix , Sys: $sys_prefix)"
fi

#
# 4 - Cleanup
#
cleanup
