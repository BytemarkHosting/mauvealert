#!/bin/sh
scp one-eyed-jack:/var/lib/mauveserver/alerts.db . && \
  sqlitebrowser alerts.db
