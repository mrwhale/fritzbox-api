#!/usr/bin/env/bash
RC_OK=0
RC_WARN=1
RC_CRIT=2
RC_UNKNOWN=3
HOSTNAME=127.0.0.1
CHECK=bandwidthdown
CURL=/usr/bin/curl
usage(){
    echo "usage: check_fritz -d -j -h hostname -f <function> [-b rate]"
    echo "    -d: enable debug output"
    echo "    -j: JSON output. Does not accept any functions. Will display all output in json format. Useful for running in cron and ingesting into another program"
    echo "    -b: rate to display. b, k, m. all in  bytes"
    echo "functions:"
    echo "    linkuptime = connection time in seconds."
    echo "    connection = connection status".
    echo "    upstream   = maximum upstream on current connection (Upstream Sync)."
    echo "    downstream = maximum downstream on current connection (Downstream Sync)."
    echo "    bandwidthdown = Current bandwidth down"
    echo "    bandwidthup = Current bandwidth up"
    echo "    totalbwdown = total downloads"
    echo "    totalbwup = total uploads"
    echo "bandwidth down is the default if no added parameters"
    exit ${RC_UNKNOWN}
}

require_number()
{
    VAR=$1
    MSG=$2

    if [[ ! "${VAR}" =~ ^[0-9]+$ ]] ; then
        echo "ERROR - ${MSG} (${VAR})"
        exit ${RC_UNKNOWN}
    fi
}

find_xml_value()
{
    XML=$1
    VAL=$2

    echo "${XML}" | grep "${VAL}" | sed "s/<${VAL}>\([^<]*\)<\/${VAL}>/\1/"
}

check_greater()
{
    VAL=$1
    WARN=$2
    CRIT=$3
    MSG=$4

    if [ ${VAL} -gt ${WARN} ] || [ ${WARN} -eq 0 ]; then
        echo "OK - ${MSG}"
        exit ${RC_OK}
    elif [ ${VAL} -gt ${CRIT} ] || [ ${CRIT} -eq 0 ]; then
        echo "WARNING - ${MSG}"
        exit ${RC_WARN}
    else
        echo "CRITICAL - ${MSG}"
        exit ${RC_CRIT}
    fi
}

print_json(){
    VERB1=GetStatusInfo
    URL1=WANIPConn1
    NS1=WANIPConnection

    VERB2=GetCommonLinkProperties
    URL2=WANCommonIFC1
    NS2=WANCommonInterfaceConfig

    VERB3=GetAddonInfos
    URL3=WANCommonIFC1
    NS3=WANCommonInterfaceConfig

    STATUS1=`curl "http://${HOSTNAME}:${PORT}/igdupnp/control/${URL1}" \
        -H "Content-Type: text/xml; charset="utf-8"" \
        -H "SoapAction:urn:schemas-upnp-org:service:${NS1}:1#${VERB1}" \
        -d "<?xml version='1.0' encoding='utf-8'?> <s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'> <s:Body> <u:${VERB1} xmlns:u="urn:schemas-upnp-org:service:${NS1}:1" /> </s:Body> </s:Envelope>" \
        -s`

    if [ "$?" -ne "0" ]; then
        printf '{"Connection":"ERROR - Could not retrieve status from FRITZ!Box"}'
        exit ${RC_CRIT}
    fi


    STATUS2=`curl "http://${HOSTNAME}:${PORT}/igdupnp/control/${URL2}" \
        -H "Content-Type: text/xml; charset="utf-8"" \
        -H "SoapAction:urn:schemas-upnp-org:service:${NS2}:1#${VERB2}" \
        -d "<?xml version='1.0' encoding='utf-8'?> <s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'> <s:Body> <u:${VERB2} xmlns:u="urn:schemas-upnp-org:service:${NS2}:1" /> </s:Body> </s:Envelope>" \
        -s`

    if [ "$?" -ne "0" ]; then
        printf '{"Connection":"ERROR - Could not retrieve status from FRITZ!Box"}'
        exit ${RC_CRIT}
    fi

    STATUS3=`curl "http://${HOSTNAME}:${PORT}/igdupnp/control/${URL3}" \
        -H "Content-Type: text/xml; charset="utf-8"" \
        -H "SoapAction:urn:schemas-upnp-org:service:${NS3}:1#${VERB3}" \
        -d "<?xml version='1.0' encoding='utf-8'?> <s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'> <s:Body> <u:${VERB3} xmlns:u="urn:schemas-upnp-org:service:${NS3}:1" /> </s:Body> </s:Envelope>" \
        -s`

    if [ "$?" -ne "0" ]; then
        printf '{"Connection":"ERROR - Could not retrieve status from FRITZ!Box"}'
        exit ${RC_CRIT}
    fi
    CONNECTIONSTATUS=$(find_xml_value "${STATUS1}" NewConnectionStatus)
    UPTIME=$(find_xml_value "${STATUS1}" NewUptime)
    DOWNSTREAM=$(find_xml_value "${STATUS2}" NewLayer1DownstreamMaxBitRate)
    UPSTREAM=$(find_xml_value "${STATUS2}" NewLayer1UpstreamMaxBitRate)
    BANDWIDTHDOWNBYTES=$(find_xml_value "${STATUS3}" NewByteReceiveRate)
    BANDWIDTHUPBYTES=$(find_xml_value "${STATUS3}" NewByteSendRate)
    TOTALBWDOWNBYTES=$(find_xml_value "${STATUS3}" NewTotalBytesReceived)
    TOTALBWUPBYTES=$(find_xml_value "${STATUS3}" NewTotalBytesSent)
    if [ ${DEBUG} -eq 1 ]; then
        echo "DEBUG - Status:"
        echo $CONNECTIONSTATUS
        echo $UPTIME
        echo $DOWNSTREAM
        echo $UPSTREAM
        echo $BANDWIDTHDOWNBYTES
        echo $BANDWIDTHUPBYTES
        echo $TOTALBWDOWNBYTES
        echo $TOTALBWUPBYTES
    fi
    printf '{"Connection":"%s","Uptime":%d,"UpstreamSync":%d,"DownstreamSync":%d,"UploadBW":%d,"DownloadBW":%d,"TotalUploads":%d,"TotalDownloads":%d}\n' "$CONNECTIONSTATUS" "$UPTIME" "$UPSTREAM" "$DOWNSTREAM" "$BANDWIDTHUPBYTES" $BANDWIDTHDOWNBYTES" "$TOTALBWUPBYTES" "$TOTALBWDOWNBYTES"
    exit #exit so we dont get unknown service check error
}

PORT=49000
DEBUG=0
WARN=0
CRIT=0
RATE=1
PRE=

while getopts h:jf:db: OPTNAME; do
    case "${OPTNAME}" in
    h)
        HOSTNAME="${OPTARG}"
        ;;
    j)
        CHECK=""
        print_json
        ;;
    f)
        CHECK="${OPTARG}"
        ;;
    d)
        DEBUG=1
        ;;
    b)
        case "${OPTARG}" in
        b)
            RATE=1
            PRE=
            ;;
        k)
            RATE=1000
            PRE=kilo
            ;;
        m)
            RATE=1000000
            PRE=mega
            ;;
        *)
            echo "Wrong prefix"
            ;;
        esac
        ;;
    *)
        echo $OPTNAME
        usage
        ;;
    esac
done

case ${CHECK} in
    linkuptime|connection)
        VERB=GetStatusInfo
        URL=WANIPConn1
        NS=WANIPConnection
        ;;
    downstream|upstream)
        VERB=GetCommonLinkProperties
        URL=WANCommonIFC1
        NS=WANCommonInterfaceConfig
        ;;
    bandwidthup|bandwidthdown|totalbwup|totalbwdown)
        VERB=GetAddonInfos
        URL=WANCommonIFC1
        NS=WANCommonInterfaceConfig
        ;;
    *)
        echo "ERROR - Unknown service check ${CHECK}"
        exit ${RC_UNKNOWN}
        ;;
esac

STATUS=`curl "http://${HOSTNAME}:${PORT}/igdupnp/control/${URL}" \
    -H "Content-Type: text/xml; charset="utf-8"" \
    -H "SoapAction:urn:schemas-upnp-org:service:${NS}:1#${VERB}" \
    -d "<?xml version='1.0' encoding='utf-8'?> <s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'> <s:Body> <u:${VERB} xmlns:u="urn:schemas-upnp-org:service:${NS}:1" /> </s:Body> </s:Envelope>" \
    -s`

if [ "$?" -ne "0" ]; then
    echo "ERROR - Could not retrieve status from FRITZ!Box"
    exit ${RC_CRIT}
fi

if [ ${DEBUG} -eq 1 ]; then
    echo "DEBUG - Status:"
    echo "${STATUS}"
fi

case ${CHECK} in
linkuptime)
    UPTIME=$(find_xml_value "${STATUS}" NewUptime)
    require_number "${UPTIME}" "Could not parse uptime"
    HOURS=$((${UPTIME}/3600))
    MINUTES=$(((${UPTIME}-(${HOURS}*3600))/60))
    SECONDS=$((${UPTIME}-(${HOURS}*3600)-(${MINUTES}*60)))
    RESULT="Link uptime ${UPTIME} seconds (${HOURS}h ${MINUTES}m ${SECONDS}s)"
    echo "${RESULT}"
    ;;
upstream)
    UPSTREAMBITS=$(find_xml_value "${STATUS}" NewLayer1UpstreamMaxBitRate)
    require_number "${UPSTREAMBITS}" "Could not parse upstream"
    UPSTREAM=$(echo "scale=3;$UPSTREAMBITS/$RATE" | bc)
    RESULT="Upstream ${UPSTREAM} ${PRE}bits per second"
    echo "${RESULT}"
    ;;
downstream)
    DOWNSTREAMBITS=$(find_xml_value "${STATUS}" NewLayer1DownstreamMaxBitRate)
    require_number "${DOWNSTREAMBITS}" "Could not parse downstream"
    DOWNSTREAM=$(echo "scale=3;$DOWNSTREAMBITS/$RATE" | bc)
    RESULT="Downstream ${DOWNSTREAM} ${PRE}bits per second"
    echo "${RESULT}"
    ;;
bandwidthdown)
    BANDWIDTHDOWNBYTES=$(find_xml_value "${STATUS}" NewByteReceiveRate)
    BANDWIDTHDOWN=$(echo "scale=3;$BANDWIDTHDOWNBYTES/$RATE" | bc)
    RESULT="Current download ${BANDWIDTHDOWN} ${PRE}bytes per second"
    echo "${RESULT}"
    ;;
bandwidthup)
    BANDWIDTHUPBYTES=$(find_xml_value "${STATUS}" NewByteSendRate)
    BANDWIDTHUP=$(echo "scale=3;$BANDWIDTHUPBYTES/$RATE" | bc)
    RESULT="Current upload ${BANDWIDTHUP} ${PRE}bytes per second"
    echo "${RESULT}"
    ;;
totalbwdown)
    TOTALBWDOWNBYTES=$(find_xml_value "${STATUS}" NewTotalBytesReceived)
    TOTALBWDOWN=$(echo "scale=3;$TOTALBWDOWNBYTES/$RATE" | bc)
    RESULT="total download ${TOTALBWDOWN} ${PRE}bytes"
    echo $RESULT
    ;;
totalbwup)
    TOTALBWUPBYTES=$(find_xml_value "${STATUS}" NewTotalBytesSent)
    TOTALBWUP=$(echo "scale=3;$TOTALBWUPBYTES/$RATE" | bc)
    RESULT="total uploads ${TOTALBWUP} ${PRE}bytes"
    echo $RESULT
    ;;
connection)
    STATE=$(find_xml_value "${STATUS}" NewConnectionStatus)
    case ${STATE} in
    Connected)
        echo "OK - Connected"
        exit ${RC_OK}
        ;;
    Connecting | Disconnected)
        echo "WARNING - Connection lost"
        exit ${RC_WARN}
        ;;
    *)
        echo "ERROR - Unknown connection state ${STATE}"
        exit ${RC_UNKNOWN}
        ;;
    esac
    ;;
*)
    echo "ERROR - Unknown service check ${CHECK}"
    exit ${RC_UNKNOWN}
esac
