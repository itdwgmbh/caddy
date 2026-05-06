#!/bin/sh
set -e
/usr/local/bin/cert-sanity
exec "$@"
