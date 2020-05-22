#!/bin/sh

set -e

force=0
dir="$(cd -P "$(dirname "$0")" && pwd)"

install_dir="/usr/local/bin"
conf_dir="/etc/sge-utils"

printusage () {
    echo "Usage: `basename "$0"` [-h] [-f] [-i INSTALL_DIR] [-c CONF_DIR]
Options:
    -h, --help          print this
    -f, --force         force overwriting files, this is not default behavior
    -i INSTALL_DIR, --install_dir INSTALL_DIR
                        use INSTALL_DIR as installation directory, defaults
                        to ${install_dir}
    -c CONF_DIR, --config_dir CONF_DIR
                        use CONF_DIR as configuration directory, defaults
                        to ${conf_dir}"
}

safecp () {
    # $1 - srcfile
    # $2 - dstfile
    # $3 - force
    local srcfile
    local dstfile
    local force
    local cpargs
    local ret
    force="${1}"
    srcfile="${2}"
    dstfile="${3}"
    cpargs="-n"
    if [ -z "${force}" ]; then
        echo "error: safecp - force is empty or not defined" 1>&2
        return 1
    fi
    if [ "${force}" != "0" -a "${force}" != "1" ]; then
        echo "error: safecp - invalid force value '${force}'" 1>&2
        return 1
    fi
    if [ -z "${srcfile}" ]; then
        echo "error: safecp - srcfile is empty or not defined" 1>&2
        return 1
    fi
    if [ -z "${dstfile}" ]; then
        echo "error: safecp - dstfile is empty or not defined" 1>&2
        return 1
    fi
    if [ ! -f "${srcfile}" ]; then
        echo "error: safecp - srcfile '${srcfile}' is not a file" 1>&2
        return 1
    fi
    if [ -d "${dstfile}" ]; then
        # in case dstfile was a directory
        # Additional / wont hurt
        dstfile="${dstfile}/`basename "${srcfile}"`"
    fi
    if [ "${force}" -ne 1 -a -f "${dstfile}" ]; then
        echo "error: safecp - destination file '${dstfile}' exists, \
not overwriting" 1>&2
        return 1
    fi
    if [ "${force}" -eq 1 ]; then
        cpargs="-f"
    fi
    if ! cp ${cpargs} "${srcfile}" "${dstfile}"; then
        ret=$?
        echo "error: safecp - cp failure" 1>&2
        return "${ret}"
    fi
    return 0
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
        -f|--force)
            force=1
            shift 1
            ;;
        -i|--install_dir)
            install_dir="$2"
            shift `maxshift 2 "$#"`
            ;;
        -c|--config_dir)
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
safecp "${force}" "${dir}/conf/jobsub.conf" "${conf_dir}"

for template in "${dir}/templates/"*
do
    safecp "${force}" "${template}" "${conf_dir}/templates"
done

for script in "${dir}/src/"*.sh
do
    dest="${install_dir}/`basename "${script}" .sh`"
    safecp "${force}" "${script}" "${dest}"
    chmod 755 "${dest}"
done
