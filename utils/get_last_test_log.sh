#!/bin/sh
test=`echo $1 | sed s/://`
less `/bin/ls -dtr /tmp/mauve_test/* | tail -1`/$test\(ZTestCases\)/log000001
