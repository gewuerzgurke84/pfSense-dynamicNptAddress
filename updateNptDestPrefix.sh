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

# Logger
loggertag=updateNtpTables.sh

# Include Bash Client Lib
source $fauxapi_script

# Build Auth
export fauxapi_auth=$(fauxapi_auth ${fauxapi_apikey} ${fauxapi_apisecret})

cleanup() {
        rm /tmp/$$.*
}

#
# 1 - Get current NPTv6 configuration
#
echo "1 - Get current NPTv6 configuration"
logger -t $loggertag "1 - Get current NPTv6 configuration"
# Get config
curl -L -X GET --silent --insecure --header "fauxapi-auth: ${fauxapi_auth}" "${fauxapi_scheme}://${fauxapi_host}/fauxapi/v1/?action=config_get" > /tmp/$$.config_get

# Get NPTv6 config part
cat /tmp/$$.config_get |jq ".data.config.nat.npt" > /tmp/$$.config_nptv6

#
# 2 - Iterate over NPTv6 settings and check iface GUA addresses
#
nptsettinglen=$(cat /tmp/$$.config_nptv6 | jq length)
patchreq=
if [ "$nptsettinglen" -gt 0 ]; then
	nptsettingcnt="$((nptsettinglen-1))"
	patchjson=$(cat /tmp/$$.config_nptv6 |jq .)		
	
	for nptIdx in $(seq 0 $nptsettingcnt); do		
		sysifacemapping=$(cat /tmp/$$.config_nptv6 | jq -r .[$nptIdx].descr)
		configprefix=$(cat /tmp/$$.config_nptv6 | jq -r .[$nptIdx].destination.address)
		echo "2 - Validation for iface=$sysifacemapping and prefix=$configprefix"
		logger -t $loggertag "2 - Validation for iface=$sysifacemapping and prefix=$configprefix"
		# No descr in NPTv6 setting
		if [ -z "$sysifacemapping" ]; then
			echo "2 - NPTv6 description is empty, please specify system iface name"
			logger -t $loggertag "2 - NPTv6 description is empty, please specify system iface name"
			continue
		fi						
		# Try to obtain current iface address
		addresses=$(ifconfig $sysifacemapping | grep inet6 | grep 2001 |awk '{print $2}')
		checkaddresses=$(echo $addresses | wc -l)
		if [ $checkaddresses != 1 ]; then
			echo "2 - More than one public address for iface=$sysifacemapping (addresses=$addresses), skipping..."
			logger -t $loggertag "2 - More than one public address for iface=$sysifacemapping (addresses=$addresses), skipping..."
			continue
		fi
		# Compare
		sysifaceaddress=$addresses
		sysprefix=$(echo $addresses |head -c 19)::/64
		echo "2 - GUA address of iface=$sysifacemapping seems to be $sysifaceaddress / $sysprefix"
		if [ "$configprefix" != "$sysprefix" ]; then
			echo "2 - Prepare reconfig of NTPv6 destination prefix for $sysifacemapping to $sysprefix"
			logger -t $loggertag "2 - Prepare reconfig of NTPv6 destination prefix for $sysifacemapping to $sysprefix"
			jqStatement=".[$nptIdx].destination.address = \"$sysprefix\""
			patchjson=$(echo $patchjson | jq "${jqStatement}")
			patchreq="yes"			
		else
			echo "2 - Destination Prefixes match, no todo"
			logger -t $loggertag "2 - Destination Prefixes match, no todo"
		fi
	done
fi

#
# 3 - Apply Patch
#
if [ -z "$patchreq" ]; then
	echo "3 - No Patch required"
	logger -t $loggertag "3 - No Patch required"
else
	echo "3 - Apply patch"
	logger -t $loggertag "3 - Apply patch"
	echo '{ "nat": { "npt": ' > /tmp/$$.config_nptv6_patch
	echo $patchjson >> /tmp/$$.config_nptv6_patch
	echo ' } }' >> /tmp/$$.config_nptv6_patch
	curl -L -X GET --silent --insecure --header "fauxapi-auth: ${fauxapi_auth}" "${fauxapi_scheme}://${fauxapi_host}/fauxapi/v1/?action=config_reload"
	curl -L -X POST --silent --insecure --header "fauxapi-auth: ${fauxapi_auth}" --header "Content-Type: application/json" --data @/tmp/$$.config_nptv6_patch "${fauxapi_scheme}://${fauxapi_host}/fauxapi/v1/?action=config_patch"
	if [ "$?" -eq 0 ]; then
		echo "3 - Patch succesfully applied"
		logger -t $loggertag "3 - Patch succesfully applied"
		exit 0
	else
		echo "3 - Patch not succesfully applied"
		logger -t $loggertag "3 - Patch not succesfully applied"
		exit 1
	fi
fi

cleanup
