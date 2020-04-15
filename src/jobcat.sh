#!/bin/sh
# Author: Ali Cherry <ali@alicherry.net>

set -e

config_file="/etc/sge-utils/jobsub.conf"
jobs_byjid_dir="/home/$USER/.jobs/by-jid"

usage="Usage:   `basename "${0}"` [OPTIONS] jobid [jobid2 [jobidn]]
OPTIONS:
    [-c, --config <conf>]       use <conf> as the config file
    [-o, --out]                 prints the stdout output of the job (conflicts with -e|-j)
    [-e, --err]                 prints the stderr output of the job (conflicts with -o|-j)
    [-j, --job]                 prints the corresponding jobsub file (conflicts with -o|-e)"

printusage () {
    echo "${usage}"
}

readrlvconf () {
    # $1 - configfile
    # @out jobs_byjid_dir
    local configfile
    local jobsbjdir
    local regex3
    local regex4
    local regex5
    local regex6
    local tmpfile
    regex3='^([A-Za-z_]+)[ \t]*=[ \t]*"?(.*)"?$'
    regex4='\1=\2'
    regex5='^(.*)(\\")?"$'
    regex6='\1\2'
    if [ "$#" -lt 1 ]; then
        echo "Error: readrlvconf - expecting 1 argument, received $#" 1>&2
        return 1
    fi
    configfile="${1}"
    if [ -z "${configfile}" ]; then
        echo "Error: readrlvconf - configfile is not defined or empty" 1>&2
        return 1
    fi
    if [ ! -f "${configfile}" ]; then
        echo "Error: readrlvconf - configfile '${configfile}' does \
            not exists" 1>&2
        return 1
    fi
    if [ ! -r "${configfile}" ]; then
        echo "Error: readrlvconf - configfile '${configfile}' is not \
            readable" 1>&2
        return 1
    fi
    tmpfile=`mktemp`
    grep -E '^(\[\w+\]|jobs_byjid_dir)' "${configfile}" \
        | tail -n 1 \
        | sed -E "s/\\\$user/${USER}/g;
                  s/\\\$cdm/${cdm}/g;
                  s/${regex3}/${regex4}/g;
                  s/${regex5}/${regex6}/g" > "${tmpfile}"

    jobsbjdir=`sed -n 's/^jobs_byjid_dir=//p' "${tmpfile}"`
    [ -n "${jobsbjdir}" ] && jobs_byjid_dir="${jobsbjdir}"
    rm "${tmpfile}"
}

valcl () {
    # $@ -> the cl
    # @out config_file
    # @out option_dest
    # @out jobs
    local option_out
    local option_err
    local option_job
    if [ "$#" -lt 1 ]; then
        echo "Error! Few arguments passed" 1>&2
        printusage
        return 1
    fi

    while [ "$#" -gt 1 ]
    do
        case "$1" in
            -h|--help)
                printusage
                exit 0
                ;;
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -o|--out)
                option_dest="${option_dest}o"
                option_out=1
                shift 1
                ;;
            -e|--err)
                option_dest="${option_dest}e"
                option_err=1
                shift 1
                ;;
            -j|--job)
                option_dest="${option_dest}j"
                option_job=1
                shift 1
                ;;
            *)
                break
                ;;
        esac
    done

    case "${option_out}${option_err}${option_job}" in
        *1*1*)
            echo "Error: conflicting output paramters." 1>&2
            return 1
            ;;
        *)
            ;;
    esac
    jobs="$@"
    if [ -z "${jobs}" ]; then
        echo "Error, jobid passed is not defined or empty" 1>&2
        printusage
        return 1
    fi
    return 0
}

getjobfile () {
    # $1 jobsbjdir
    # $2 jobid
    # @echo jobfile path
    local jobsbjdir
    local jobid
    local jobpath
    if [ "$#" -lt 2 ]; then
        echo "Error: jobfile - expecting 2 arguments, received $#" 1>&2
        return 1
    fi
    jobsbjdir="${1}"
    jobid="${2}"
    jobpath="${jobsbjdir}/${jobid}.job"
    if [ -z "${jobsbjdir}" ]; then
        echo "Error: jobfile - jobs_by_jid is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${jobid}" ]; then
        echo "Error: jobfile - jobid is not defined or empty" 1>&2
        return 1
    fi
    if ! echo "${jobid}" | grep -Eq '^[0-9]+$'; then
        echo "Error: jobfile - jobid '${jobid}' is not numerical" 1>&2
        return 1
    fi
    if [ ! -f "${jobpath}" ]; then
        echo "Warning: jobfile - jobid '${jobid}' might be invalid" 1>&2
        echo "Error: Jobfile - corresponding job file '${jobpath}' \
does not exists, did you delete it ?" 1>&2
        return 1
    fi
    if [ ! -r "${jobpath}" ]; then
        echo "Error: jobfile - job file '${jobpath}' is not readable" 1>&2
        return 1
    fi
    echo "${jobpath}"
    return 0
}

getdestfile () {
    # $1 dest o|e|j
    # $2 jobfile
    # @echo destfile
    local dest
    local jobfile
    local out
    if [ "$#" -lt 2 ]; then
        echo "Error: catjob - expecting 2 arguments, received $#" 1>&2
        return 1
    fi
    dest="${1}"
    jobfile="${2}"
    if [ -z "${dest}" ]; then
        echo "Error: catjob - dest is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${jobfile}" ]; then
        echo "Error: catjob - jobfile is not defined or empty" 1>&2
        return 1
    fi
    case "${dest}" in
        o)
            out=`grep "#\$ -o " "${jobfile}" | awk '{print $3}'`
            ;;
        e)
            out=`grep "#\$ -e " "${jobfile}" | awk '{print $3}'`
            ;;
        j)
            out="${jobfile}"
            ;;
        *)
            echo "Error: catjob - invalid dest '${dest}'" 1>&2
            ;;
    esac
    echo "${out}"
}

catfile () {
    # $1 dest file
    local file
    if [ -z "${1}" ]; then
        echo "Error: catjob - passed file is not defined or empty" 1>&2
        return 1
    fi
    file="${1}"
    if [ ! -r "${file}" ]; then
        echo "Error: catjob - unable to read file '${file}'" 1>&2
        return 1
    fi
    cat "${file}"
}

catjobs () {
    # $1 jobsbjdir
    # $2 dest o|e|j
    # $3 space-seperated list of jobids
    local jobsbjdir
    local dest
    local jobs
    local jobid
    local jobfile
    local destfile
    local failed
    failed=0
    if [ "$#" -lt 3 ]; then
        echo "Error: catjobs - expecting at 3 arguments, received $#" 1>&2
        return 1
    fi
    jobsbjdir="${1}"
    dest="${2}"
    jobs="${3}"
    if [ -z "${jobsbjdir}" ]; then
        echo "Error: catjobs - jobsbjdir is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${dest}" ]; then
        echo "Error: catjobs - dest is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${jobs}" ]; then
        echo "Error: catjobs - jobs is not defined or empty" 1>&2
        return 1
    fi
    for jobid in ${jobs}
    do
        if ! jobfile=`getjobfile "${jobsbjdir}" "${jobid}"`; then
            failed=1
            continue
        fi
        if ! destfile=`getdestfile "${dest}" "${jobfile}"`; then
            failed=1
            continue
        fi
        echo "JOB========================${jobid}@${destfile}" 1>&2
        if ! catfile "${destfile}"; then
            failed=1
        fi
    done
    if [ "${failed}" -ne 0 ]; then
        echo "Warning: Some catjobs failed.." 1>&2
        return "${failed}"
    fi
    return 0
}

valcl "$@"
readrlvconf "${config_file}"
catjobs "${jobs_byjid_dir}" "${option_dest}" "${jobs}"
