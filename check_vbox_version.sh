#!/bin/sh

if [ $(vboxmanage --version | cut -d "." -f 1) -lt 5 ]; then
	echo "=========================================="
	echo "ERROR: Virtual Box version should be >=5.0"
	echo "=========================================="
	exit 1
fi
