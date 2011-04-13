#!/bin/sh

NO_ARGS=0 
OPTERROR=65
if [ $# -eq "$NO_ARGS" ]  # Script invoked with no command-line args?
then
  echo "Usage: `basename $0` File.log"
  exit $OPTERROR          # Exit and explain usage, if no argument(s) given.
fi  
logFile=$1

egrep 'Packet processed in [\.0-9]* seconds' $logFile |\
  awk 'BEGIN {print "  date sz"} {print s++ " " $1 "::" $2 " " $11}' > data

R --vanilla --no-save --slave <<RSCRIPT
lst <- read.table("data")
attach(lst)
summary(sz)
png(filename="packets.png", width=1024)
dates <- strptime(as.character(date), "%Y-%m-%d::%H:%M:%S") 
plot(dates, sz, type='l', 
     main="Mauve server: maximum processing time of a packet per second.", 
     xlab="Time", 
     ylab="Maximum processing time of one packet")
abline(h=1.05, col="red")
abline(h=mean(sz), col="blue")
RSCRIPT
img=`which qiv`
if [ $? != 0 ] 
then echo "Cannot display image here"
else $img packets.png
fi
