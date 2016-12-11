#!/bin/bash
set -x

# Feedback to tomerr@tomerr.com
# DNS HA Configuration file, use the below syntax:
# Hostname 1st_Priority_IP 2nd_Priority_IP 3rd_Priority_IP...
# In case of using the LS (Load Balanced) version of the script priorities does not have meaning.
# If you delete entire record from here, you will need to restart named and remove the record from the zone file.
#hostname6        2001:abc::1::1a     2001:abc::1::1b
HA_LIST_FILE="/opt/dns-ha/ha-addresses.cfg"
KEY_FILE="/var/named/dynamic/Kexample6.com.+157+59242.key"
ZONE=example6.com
ORIG_ZONE=example.com
URL_TIMEOUT=10
SERVER=localhost
NOTIFICATION_EMAIL=( "email1@example.com" "email2@example.com" )
SEND_EMAILS=false

function sendMail() {
	if [ "$SEND_EMAILS" == "true" ]; then
		SUBJECT=$1
		MSG=$2
		FROM="dnsservice-ny@example6.com"
        
		for email_addr in ${NOTIFICATION_EMAIL[@]} 
      	  	do
				echo "$MSG" | mail -r "$FROM" -s "$SUBJECT" $email_addr
        	done
	fi
}
function testURL() { # $1=Host name, $2=IPv6 Address. Returns 0 if URL is accessible.
        TMPOUTFILE="/var/tmp/url-test.tmp"
        URL="$1"
        IP6="$2"
        curl -s -S -m $URL_TIMEOUT -k -H "Host: $URL.$ORIG_ZONE" -6 "https://\[$IP6\]" > $TMPOUTFILE 2>&1
        if [ "$?" == "0" ]; then
                echo 0
        else
                echo 1
        fi
}
function ddns-add() { #$1 Host to update, $2 IP to update. Return 0 if dynamic DNS update was successful.
        HOST=$1
        IP6_TO_ADD=$2
        nsupdate -k $KEY_FILE -v <<- _EOF_
        server $SERVER
        zone $ZONE
        update add $HOST.$ZONE     0 AAAA $IP6_TO_ADD
        send 
_EOF_

        if [ "$?" == "0" ]; then
                echo 0
        else
                echo 1
        fi
}
function ddns-del() { #$1 Host to update, $2 IP to update. Return 0 if dynamic DNS update was successful.
        HOST=$1
        IP6_TO_DEL=$2
        nsupdate -k $KEY_FILE -v <<- _EOF_
        server $SERVER
        zone $ZONE
        update delete $HOST.$ZONE AAAA $IP6_TO_DEL
        send 
_EOF_

        if [ "$?" == "0" ]; then
                echo 0
        else
                echo 1
        fi
}
function checkDnsPairPub() { #Check if host IP is currently published in DNS.
        HOST=$1
        IP6=`echo $2 | xargs ipv6calc --addr_to_fulluncompressed`
        FOUND=1
        IFS=' ' read -a RESOLVED_IP6 <<< `host -6 -t AAAA $HOST.$ZONE | awk '{print $NF}' | xargs -n1 ipv6calc --addr_to_fulluncompressed | sed ':a;N;$!ba;s/\n/ /g'`
        for ip in "${RESOLVED_IP6[@]}"
        do
                if [ "${ip}" == "$IP6" ]; then
                        FOUND=0
                        break
                fi
        done
        echo $FOUND
}
function currentDnsCount() {
        HOST=$1
        IP6_COUNT=`host -6 -t AAAA $HOST.$ZONE | awk '{print $NF}' | xargs -n1 ipv6calc --addr_to_fulluncompressed | wc -l`
        echo $IP6_COUNT
}
function removeNonPubIPs() {
        HOST=$1
#Remove IP's that deleted from the configuration file and are still published.
        IFS=' ' read -a CONF_IP6 <<< `grep $HOST $HA_LIST_FILE | awk '{$1=""; print $0}' | xargs -n1 ipv6calc --addr_to_fulluncompressed | sed ':a;N;$!ba;s/\n/ /g'`
        IFS=' ' read -a PUB_IP6 <<< `host -6 -t AAAA $HOST.$ZONE | awk '{print $NF}' | xargs -n1 ipv6calc --addr_to_fulluncompressed | sed ':a;N;$!ba;s/\n/ /g'`

        for i in "${!PUB_IP6[@]}"
        do
                FOUND=1
                for j in "${!CONF_IP6[@]}"
                do
                        if [  ${PUB_IP6[i]} == ${CONF_IP6[j]} ];then
                                FOUND=0
                        fi
                done
                if [ $FOUND != 0 ]; then
                        UPDATE_SUCCESS=`ddns-del $HOST ${PUB_IP6[i]}`
                        if [ $UPDATE_SUCCESS == 0 ]; then
                                echo "removeNonPubIPs(): $HOST.$ZONE IP: ${PUB_IP6[i]} Removed Successfully as it was removed from the configuration file."
								sendMail "$HOST.$ZONE change: ${PUB_IP6[i]} Removed from zone." "Currently Online: `host -6 -t AAAA $HOST.$ZONE`"
                        else
                                echo "removeNonPubIPs() Update failed."
                        fi
                fi
        done
}
function main() {
        declare -a CONFIG_IDX
        cat $HA_LIST_FILE | while read LINE ; do
                        #Skip comments and blank lines
                        case "$LINE" in \#*) continue ;; esac
                        if [ "$LINE" != "" ]; then #Parse config file and get Hostname and IP addresses.
                                LINE_NOTABS=`echo $LINE | sed 's/\t/ /g'`
                                IFS=' ' read -a CONFIG_IDX <<< $LINE_NOTABS
                                HOST="${CONFIG_IDX[0]}"
                                removeNonPubIPs $HOST
                                for index in "${!CONFIG_IDX[@]}"
                                do
                                        if [ $index != 0 ]; then
                                                isAvail=`testURL $HOST ${CONFIG_IDX[index]}`
                                                if [ $isAvail == 0 ]; then # If IP is available
                                                        #echo "IP ${CONFIG_IDX[index]} is available."
                                                        if [ `checkDnsPairPub "$HOST" ${CONFIG_IDX[index]}` != 0 ]; then #If machine is up and not published.
                                                                echo "Host $HOST.$ZONE with IP ${CONFIG_IDX[index]} is available but not published, Adding."
                                                                UPDATE_SUCCESS=`ddns-add $HOST ${CONFIG_IDX[index]}`
                                                                if [ $UPDATE_SUCCESS == 0 ]; then
                                                                        echo "$HOST.$ZONE ${CONFIG_IDX[index]} Added Successfully."
																		sendMail "$HOST.$ZONE change: ${CONFIG_IDX[index]} is now available." "Currently Online: `host -6 -t AAAA $HOST.$ZONE`"
                                else
                                    echo "Update failed."
                                fi
                                                        else #Machine is up and published.
                                                                echo "Host $HOST.$ZONE with IP ${CONFIG_IDX[index]} is available and already published, no need to add."
                                                        fi
                                                else #IP is not available.
                                                        echo "IP ${CONFIG_IDX[index]} is NOT available."
                                                        if [ `checkDnsPairPub $HOST ${CONFIG_IDX[index]}` == 0 ]; then #If host if unavailable and published
                                                                if [ `currentDnsCount $HOST` -le 1 ]; then #If all machines are down, we leave 1 IP published.
                                                                        echo "Only one record exist in DNS, Skipping removal of $HOST.$ZONE IP: ${CONFIG_IDX[index]}"
																		sendMail "$HOST.$ZONE change: ${CONFIG_IDX[index]} is not available but only one record exist in DNS." "Currently Published: `host -6 -t AAAA $HOST.$ZONE`"
                                                                else
                                                                        echo "Host $HOST with IP ${CONFIG_IDX[index]} is NOT available but is published, Deleting."
                                                                        UPDATE_SUCCESS=`ddns-del $HOST ${CONFIG_IDX[index]}`
                                                                        if [ $UPDATE_SUCCESS == 0 ]; then
                                                                                echo "$HOST.$ZONE ${CONFIG_IDX[index]} Removed Successfully."
																				sleep 1
																				sendMail "$HOST.$ZONE change: ${CONFIG_IDX[index]} is NOT available." "Currently Online: `host -6 -t AAAA $HOST.$ZONE`"
                                                                        else
                                                                                echo "Update failed."
                                                                        fi
                                                                fi
                                                        else
                                                                echo "Host $HOST with IP ${CONFIG_IDX[index]} is NOT available and is already not published, no need to delete."
                                                        fi
                                                fi
                                        fi
                                done
                                echo Currently Published:
                                host -6 -t AAAA $HOST.$ZONE
                        fi
        done
}
main
