#!/bin/sh

PRE="ruby -I lib ./bin/mauveclient 127.0.0.1 "

$PRE -o supportbot -i 173123 \
 -s "My server is not responding" \
 -d "<strong>From:</strong> John Smith &lt;john@smith.name><br/>
<strong>To:</strong> support@support.bytemark.co.uk</br/>
<br/>
<pre>It has been several hours now since I have been able to contact my server
foo.bar.bytemark.co.uk.  I am very upset that blah blah blah blah
and furthermore by business is under threat because &pound;15.00 per month
is far too much blah blah blah</pre>
<script>alert('arse')</script>
<h1>Brokent<p></h1></p>html.
"

$PRE -o networkmonitor -i 1 -u cr01.man.bytemark.co.uk \
  -s "cr01.man.bytemark.co.uk did not respond to pings"

$PRE -o networkmonitor -i 2 -u cr01.thn.bytemark.co.uk \
  -s "cr02.man.bytemark.co.uk refused SSH connection" \
  -d "<pre>ssh: connect to host localhost port 1212: Connection refused</pre>"

$PRE -o ventham.bytemark.co.uk -i heartbeat -r now -s "<b>heartbeat</b> <script>alert('arse')</script> failed for ventham.bytemark.co.uk" --detail="<p>The heartbeat wasn't sent for the host ventham.bytemark.co.uk</p><p>This indicates that the host might be down</p>" >/dev/null

$PRE -o networkmonitor -i ping-ventham -u ventham.bytemark.co.uk -r +10m -s "ping failed for ventham.bytemark.co.uk"

$PRE -o vmhs -i 12345 -u partridge.bytemark.co.uk \
  -s "partridge.bytemark.co.uk heartbeat not received" -r +10m -c now

$PRE -o vmhs -i 12347 -u eider.bytemark.co.uk \
  -s "eider.bytemark.co.uk heartbeat not received" -r +2

$PRE -o thresholds -i 1 -u bl1-1.bytemark.co.uk \
  -s "bl1-1 exceeded 10Mb/s on bond0" \
  -d "<h1>Hello there</h1><p>Here is a paragraph</p><p>And another one</p>"

$PRE -o thresholds -i 2 -u bl1-11.bytemark.co.uk \
  -s "bl1-11 has less than 1GB free memory"

$PRE -o thresholds -i 3 -u rom.sh.bytemark.co.uk \
  -s "rom.sh.bytemark.co.uk has 1/2 discs available in /dev/md0" \
  -d "<pre>Personalities : 
unused devices: <none>
</pre>
"

