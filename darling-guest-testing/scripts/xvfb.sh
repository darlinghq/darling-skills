#!/bin/bash
# xvfb.sh: make sure Xvfb :99 and the xfwm4 window manager are running for GUI
# tests (some window behaviour needs a real WM). Never use another display.
if ! ps -eo args= | grep -q '^[X]vfb :99'; then
	nohup Xvfb :99 -screen 0 1920x1080x24 +extension RANDR -nolisten tcp >/dev/null 2>&1 &
	sleep 2
fi
if ! ps -eo args= | grep -q '[x]fwm4'; then
	DISPLAY=:99 nohup xfwm4 --compositor=off --sm-client-disable >/dev/null 2>&1 &
	sleep 1
fi
ps -eo pid=,args= | grep -E '^ *[0-9]+ ([X]vfb :99|[x]fwm4)'
