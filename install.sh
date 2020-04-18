#!/bin/sh
set -ex
DIR="$(cd -P "$(dirname "$0")" && pwd)"

install_dir="/usr/local/bin"
conf_dir="/etc/sge-utils"

printusage () {
    echo "Usage: `basename "$0"` [-h] [-i INSTALL_DIR] [-c CONF_DIR]
Defaults are: -i ${install_dir} -c ${conf_dir}"
}

maxshift () {
    # $1 desired shift
    # $2 $2 of the caller
    if [ "$1" -le "$2" ]; then
        echo "$1"
    else
        echo "$2"
    fi
}

while [ "$#" -gt 0 ];
do
    case "$1" in
        -h|--help)
            printusage
            shift 1
            exit 0
            ;;
        -i)
            install_dir="$2"
            shift `maxshift 2 "$#"`
            ;;
        -c)
            conf_dir="$2"
            shift `maxshift 2 "$#"`
            ;;
        *)
            echo "error: invalid argument '$1'" 1>&2
            exit 1
            ;;
    esac
done

echo "Installing to ${install_dir} and ${conf_dir}"
mkdir -p "${install_dir}"
mkdir -p "${conf_dir}/templates"
cp "${DIR}/conf/jobsub.conf" "${conf_dir}"
cp "${DIR}/templates/"* "${conf_dir}/templates"

for script in "${DIR}/src/"*.sh
do
    dest="${install_dir}/`basename "${script}" .sh`"
    cp "${script}" "${dest}"
    chmod 755 "${dest}"
done
