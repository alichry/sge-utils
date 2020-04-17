#!/bin/sh

install="${1:-/usr/local/bin}"

if [ ! -d "${install}" ]; then
    echo "error: passed install location is not a directory"
    exit 1
fi

mkdir -p /etc/sge-utils/templates
cp conf/jobsub.conf /etc/sge-utils
cp templates/* /etc/sge-utils/templates

for script in src/*.sh
do
    dest="${install}/`basename "${script}" .sh`"
    cp "${script}" "${dest}"
    chmod 755 "${dest}"
done
