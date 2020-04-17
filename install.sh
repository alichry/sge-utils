#!/bin/sh
set -e
DIR="$(cd -P "$(dirname "$0")" && pwd)"

if [ "$1" = "-h" -o "$1" = "--help"  ]; then
    echo "Usage: `basename "$0"` <install_path>
Default install path is /usr/local/bin"
    exit 0
fi

install="${1:-/usr/local/bin}"

if [ ! -d "${install}" ]; then
    echo "error: passed install location is not a directory"
    exit 1
fi

echo "Installing to ${install}"

mkdir -p /etc/sge-utils/templates
cp "${DIR}/conf/jobsub.conf" /etc/sge-utils
cp "${DIR}/templates/"* /etc/sge-utils/templates

for script in "${DIR}/src/"*.sh
do
    dest="${install}/`basename "${script}" .sh`"
    cp "${script}" "${dest}"
    chmod 755 "${dest}"
done
