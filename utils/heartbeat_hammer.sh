#!/bin/bash

PRE="ruby -I lib bin/mauvesend [::1]"
F=60
S=10
n=$*

_host () { 
  hostname="imaginary-$i.example.com"
  down="n"

  while( true ) ; do

      if [ "$down" == "n" ] ; then
        $PRE -o $hostname -i heartbeat -r +$F -c now -s "heartbeat failed" --detail="<p>The heartbeat wasn't sent for this host</p><p>This indicates that the host might be down</p>"
        sleep $((F - $RANDOM*$S/32768 - $S))
      else
        sleep $((RANDOM*$S/32768 + $F + $S))
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

echo -e "This command will go beserk.  To kill run\n  pkill -t `tty`\n\nGiving you 5 seconds to quit!"

sleep 5

for i in `seq 1 100` ; do
  _host $i &
  sleep 0.2
done

