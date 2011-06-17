#!/bin/bash

PRE="ruby -I lib ./bin/mauveclient localhost"

_host () { 
  hostname="imaginary-$i.bytemark.co.uk"
  while( true ) ; do
      sleep $((RANDOM/60))
      echo $hostname
      $PRE -o $hostname -i heartbeat -r +2m -c now -s "heartbeat failed" --detail="<p>The heartbeat wasn't sent for this host</p><p>This indicates that the host might be down</p>"
  done
}


for i in `seq 1 50` ; do
  _host $i &
done

