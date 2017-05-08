#!/bin/bash
#
# Thanks to http://blog.gmeiners.net/2013/09/fritzbox-mit-nagios-uberwachen.html# for the basis of the original script
#

RC_OK=0
RC_WARN=1
RC_CRIT=2
RC_UNKNOWN=3

CURL=/usr/bin/curl

usage()
{
    echo "usage: check_fritz -d -h hostname -f <function> [-w <warn>] [-c crit] [-b rate]"
    echo "    -d: enable debug output"
    echo "    -w: warn limit, depends on function"
    echo "    -c: critical limit, depends on function"
    echo "    -b: rate to display. b, k, m. all in bits"
    echo "functions:"
    echo "    linkuptime = connection time in seconds."
    echo "    connection = connection status".
    echo "    upstream   = maximum upstream on current connection."
    echo "    downstream = maximum downstream on current connection."
    echo "    bandwidth = Current bandwidth usage"
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

div ()  # Arguments: dividend and divisor
{
        if [ $2 -eq 0 ]; then echo division by 0; exit; fi
        local p=12                            # precision
        local c=${c:-0}                       # precision counter
        local d=.                             # decimal separator
        local r=$(($1/$2)); echo -n $r        # result of division
        local m=$(($r*$2))
        [ $c -eq 0 ] && [ $m -ne $1 ] && echo -n $d
        [ $1 -eq $m ] || [ $c -eq $p ] && return
        local e=$(($1-$m))
        let c=c+1
        div $(($e*10)) $2
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

HOSTNAME=fritz.box
PORT=49000
CHECK=bandwidthdown
DEBUG=0
WARN=0
CRIT=0
RATE=1
PRE=bits

while getopts h:f:w:c:d:b: OPTNAME; do
    case "${OPTNAME}" in
    h)
        HOSTNAME="${OPTARG}"
        ;;
    f)
        CHECK="${OPTARG}"
        ;;
    d)
        DEBUG=1
        ;;
    w)
        WARN="${OPTARG}"
        ;;
    c)
        CRIT="${OPTARG}"
        ;;
    b)
        echo $OPTARG
        case "${OPTARG}" in
        b)
            RATE=1
            PRE=bits
            ;;
        k)
            RATE=1024
            PRE=kilobits
            ;;
        m)
            RATE=1024*1024
            PRE=megabits
            ;;
        *)
            echo "Wrong prefix"
            ;;
        esac
        ;;
    *)
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

    check_greater ${UPTIME} 1 0 "${RESULT}"
    ;;
upstream)
    UPSTREAM=$(find_xml_value "${STATUS}" NewLayer1UpstreamMaxBitRate)
    require_number "${UPSTREAM}" "Could not parse upstream"

    RESULT="Upstream ${UPSTREAM} bits per second"

    check_greater ${UPSTREAM} ${WARN} ${CRIT} "${RESULT}"
    ;;
downstream)
    DOWNSTREAM=$(find_xml_value "${STATUS}" NewLayer1DownstreamMaxBitRate)
    require_number "${DOWNSTREAM}" "Could not parse downstream"

    RESULT="Downstream ${DOWNSTREAM} bits per second"

    check_greater ${DOWNSTREAM} ${WARN} ${CRIT} "${RESULT}"
    ;;
bandwidthdown)
    BANDWIDTHDOWNBITS=$(find_xml_value "${STATUS}" NewByteReceiveRate)
    BANDWIDTHDOWN=$((BANDWIDTHDOWNBITS/RATE))
    RESULT="Current download ${BANDWIDTHDOWN} ${PRE} per second"
    printf "Current download %.3f %s per second" $BANDWIDTHDOWN $PRE
    check_greater ${BANDWIDTHDOWN} ${WARN} ${CRIT} "${RESULT}"
    ;;
bandwidthup)
    BANDWIDTHUPBITS=$(find_xml_value "${STATUS}" NewByteSendRate)
    BANDWIDTHUP=$((BANDWIDTHUPBITS/RATE))
    RESULT="Current upload ${BANDWIDTHUP} ${PRE} per second"
    check_greater ${BANDWIDTHUP} ${WARN} ${CRIT} "${RESULT}"
    ;;
totalbwdown)
    TOTALBWDOWNBITS=$(find_xml_value "${STATUS}" NewTotalBytesReceived)
    TOTALBWDOWN=$((TOTALBWDOWNBITS/RATE))
    RESULT="total download ${TOTALBWDOWN} ${PRE}"
    check_greater ${TOTALBWDOWN} ${WARN} ${CRIT} "${RESULT}"
    ;;
totalbwup)
    TOTALBWUPBITS=$(find_xml_value "${STATUS}" NewTotalBytesSent)
    TOTALBWUP=$((TOTALBWUPBITS/RATE))
    RESULT="total uploads ${TOTALBWUP} ${PRE}"
    check_greater ${TOTALBWUP} ${WARN} ${CRIT} "${RESULT}"
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