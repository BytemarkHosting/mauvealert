#!/bin/sh
### BEGIN INIT INFO
# Provides:          mauveserver
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start the mauve alerting daemon at boot time
# Description:       Start the mauve alerting daemon at boot time
### END INIT INFO

PATH=/bin:/sbin:/usr/bin:/usr/local/bin
DAEMON=/usr/bin/jmauveserver
DAEMON_OPTS=/etc/mauvealert/mauveserver.conf
DESC="mauvealert server"
PIDFILE=/var/run/jmauveserver.pid
LOG=/var/log/mauve

test -x $DAEMON || exit 0

. /lib/lsb/init-functions

case "$1" in
  start)
    log_begin_msg "Starting $DESC:" "$NAME"
    if [ ! -d $LOG ]; then mkdir $LOG; fi
    chown mauveserver $LOG /var/lib/mauveserver
    $DAEMON $DAEMON_OPTS &
    echo $! > $PIDFILE
    for i in `seq 0 1 11`;do sleep 1; echo -n '.'; done
    kill -0 $(cat $PIDFILE)
    if [ $? != 0 ] ; then echo -n "failed"; else echo -n "success"; fi

    # Email on start.
    address="yann@bytemark.co.uk"
    lastLog=`/bin/ls -tr $LOG/*.log | tail -1`
    logLastLines=`tail -101 $lastLog`
    echo $logLastLines | mail -s "Mauve was started at `date`" $address

    log_end_msg $?
    ;;
  stop)
    log_begin_msg "Stopping $DESC:" "$NAME"
    if [ -f $PIDFILE ] ; then
      kill `cat $PIDFILE`
      rm $PIDFILE

      # Email on stop.
      address="yann@bytemark.co.uk"
      lastLog=`/bin/ls -tr $LOG/*.log | tail -1`
      logLastLines=`tail -101 $lastLog`
      echo $logLastLines | mail -s "Mauve was stopped at `date`" $address

    else
      echo Not running to stop
      exit 1
    fi
    log_end_msg $?
    ;;
  reload)
    if [ -f $PIDFILE ] ; then
      echo Sending restart signal to mauveserver
      kill -HUP `cat $PIDFILE`
    else
      echo Not running to reload
    fi
    ;;
  restart|reload|force-reload)
    $0 stop
    sleep 1
    $0 start
    ;;
  *)
    N=/etc/init.d/$NAME
    echo "Usage: $N {start|stop|restart}" >&2
    exit 1
    ;;
esac

exit 0
