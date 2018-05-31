# fritzbox-api
Bash script to collect various information from your Fritzbox via its SOAP api

As I could not find much information on this in english, this is a combination of a few scripts I found online from some european blogs (not in my native language)
So lets give a thanks to
- http://www.gtkdb.de/index_36_2458.html
- http://blog.gmeiners.net/2013/09/fritzbox-mit-nagios-uberwachen.html#
and
- https://github.com/Harrdy/pimatic-fritzbox-upnp
- https://stackoverflow.com/questions/12524437/output-json-from-bash-script#12524510

Script can output:
- link uptime 
- connection status
- maximum upstream sync speed on current connection
- maximum downstream sync speed on current connection
- Current downstream bandwidth usage
- Current upstream bandwidth usage
- Total download usage on current connection
- Total upload usage on current connection

This can also output all of the above in  JSON format, useful for ingesting into another program and when running via cron (e.g I read this information into openHAB)

The purpose for this was so I could get the current bandwidth usage across the WAN link into openHAB, for monitoring and for making pretty graphs on usage during the day. And I could see the current bandwidth usage at a glance, incase I was having some issues and quick diagnosis. I have made this script a little more bare, without all the openHAB specific stuff in it

## Usage
```
usage: fritz -d -j -h hostname -f <function> [-b rate]
    -d: enable debug output
    -j: JSON output. Does not accept any functions. Will display all output in json format. Useful for running in cron and ingesting into another program
    -b: rate to display. b, k, m. all in  bytes
functions:
    linkuptime = connection time in seconds.
    connection = connection status.
    upstream   = maximum upstream on current connection (Upstream Sync).
    downstream = maximum downstream on current connection (Downstream Sync).
    bandwidthdown = Current bandwidth down
    bandwidthup = Current bandwidth up
    totalbwdown = total downloads
    totalbwup = total uploads
bandwidth down is the default if no added parameters
```

#### dependancies
- bc
- curl
