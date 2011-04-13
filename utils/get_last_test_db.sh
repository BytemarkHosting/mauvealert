#!/bin/sh
test=`echo $1 | sed s/://`
sqlitebrowser `/bin/ls -dtr /tmp/mauve_test/* | tail -1`/$test\(ZTestCases\)/mauve_test.db
