#!/bin/bash

PRE="ruby -I lib bin/mauveclient localhost"
F=60
n=$*

_host () { 
  hostname="imaginary-$i.example.com"
  down="n"

  while( true ) ; do

      if [ "$down" == "n" ] ; then
        $PRE -o $hostname -i heartbeat -r +$F -c now -s "heartbeat failed" --detail="<p>The heartbeat wasn't sent for this host</p><p>This indicates that the host might be down</p>"
        sleep $((F - $RANDOM*5/32768 - 5))
      else
        sleep $((RANDOM*5/32768 + $F + 5))
      fi

      if [ $RANDOM -gt 30000 ] ; then
        [ "$down" == "n" ] && echo "Host $hostname down"
        down="y"
      else
        [ "$down" == "y" ] && echo "Host $hostname up"
        down="n"
      fi
  done
}

for i in `seq 1 500` ; do
  _host $i &
  sleep 0.2
done

