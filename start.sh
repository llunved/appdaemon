#!/bin/bash

cd /appdaemon
source /appdaemon/bin/activate
exec /appdaemon/bin/appdaemon -c /etc/appdaemon

