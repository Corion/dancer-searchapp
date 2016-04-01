#!/bin/bash
set -e

if [ "$1" = 'dancer-searchapp' ]; then
    shift
    echo "$@"
    exec plackup -s Twiggy --port 8080 -a bin/app.pl "$@"
fi

exec "$@"