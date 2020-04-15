#!/bin/sh
# Author: Ali Cherry <ali@alicherry.net>

set -e

usage="Usage:   `basename "${0}"` [OPTIONS] jobid [jobid2 [... [jobidn]]]
OPTIONS:
    -c, --config <conf>         use <conf> as the config file
    -s, --scal                  interpret jobids as scalids
    -o, --out                   prints the stdout output of the job (conflicts with -e|-j)
    -e, --err                   prints the stderr output of the job (conflicts with -o|-j)
    -j, --job                   prints the corresponding jobsub file (conflicts with -o|-e)
    -d, --debug <format>        prints the corressponding debug file. Available formats: vg%d where %d the is the relative logical processor id (starting from 0 regardless of cpuid)"

printusage () {
    echo "${usage}"
}

ctype_digit () {
    case "${1}" in
        ''|*[!0-9]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

readconf () {
    # $1 - config file
    # $2 - section name
    # @env $USER
    # @env $HOME
    # first we assume that there are several blocks after $1 section
    # grep -Pzo '(?s)(?<=^\[jobsub\])(.*?)(?=^\[)' jobsub.conf
    # if the above command fails (no match), then there is
    # only no sections after [$1].
    local cdm
    local cmy
    local cy
    local configfile
    local section
    local regex1
    local regex2
    local regex3
    local regex4
    local regex5
    local regex6
    local conf
    local tmpfile
    local tmp
    if [ "$#" -lt 2 ]; then
        echo "Error: readconf - expecting 2 arguments, received $#" 1>&2
        return 1
    fi
    configfile="${1}"
    section="${2}"
    if [ -z "${configfile}" ]; then
        echo "Error: readconf - passed config file argument " \
            "is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${section}" ]; then
        echo "Error: readconf - passed section is not defined or empty" 1>&2
        return 1
    fi
    if [ ! -f "${configfile}" ]; then
        echo "Error: readconf - passed config file " \
            "'${configfile}' does not exists" 1>&2
        return 1
    fi
    if [ ! -r "${configfile}" ]; then
        echo "Error: readconf - unable to read config file " \
            "'${configfile}'" 1>&2
        return 1
    fi
    # default conf
    cdm="$(date +%d%m)"
    cym="$(date +%m%Y)"
    cy="$(date +%Y)"
    [ -z "${qsub}" ] && qsub="qsub"
    [ -z "${jobs_dir}" ] && jobs_dir="/home/$USER/.jobs/${cdm}"
    [ -z "${jobs_byjid_dir}" ] && jobs_byjid_dir="/home/$USER/.jobs/by-jid"
    [ -z "${jobs_last_index_file}" ] && jobs_last_index_file="${jobs_dir}/.last"
    [ -z "${submissions_dir}" ] && submissions_dir="/home/$USER/.submissions/${cdm}"
    [ -z "${scal_dir}" ] && scal_dir="/home/$USER/.scal"
    [ -z "${scal_max_entries}" ] && scal_max_entries=10
    [ -z "${scal_last_index_file}" ] && scal_last_index_file="${scal_dir}/.last"
    [ -z "${scal_index_table_prefix}" ] && scal_index_table_prefix="scal.index"
    # some regex can be simply combined..
    # but different behavior occured on POSIX and GNU
    regex1="(?s)(?<=^\[${section}\])(.*?)(?=^\[)"
    regex2="(?s)(?<=^\[${section}\])(.*)"
    regex3='^([A-Za-z_]+)[ \t]*=[ \t]*"?(.*)"?$'
    regex4='\1=\2'
    regex5='^(.*)(\\")?"$'
    regex6='\1\2'

    if ! grep -Fq "[${section}]" "${configfile}"; then
        echo "readconf - missing section '${section}' from config" 1>&2
        return 1
    fi
    if ! conf=`grep -Pzo "${regex1}" "${configfile}"`; then
        if ! conf=`grep -Pzo "${regex2}" "${configfile}"`; then
            echo "readconf - unable to read section '${section}', " \
                "check your configuration" 1>&2
            return 2
        fi
    fi
    tmpfile=`mktemp`
    echo "${conf}" | sed -E "/^\$|^#.*\$/d;
                s/${regex3}/${regex4}/g;
                s/${regex5}/${regex6}/g;
                s/\\\$user/${USER}/g;
                s|\\\$home|${HOME}|g;
                s/\\\$cdm/${cdm}/g;
                s/\\\$cym/${cym}/g;
                s/\\\$cy/${cy}/g" > "${tmpfile}"
    # TODO: deal with duplicate entries
    case "$(echo "${section}" | cut -d " " -f 1)" in
        jobsub)
            tmp=`sed -n 's/^qsub=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && qsub="${tmp}"
            tmp=`sed -n 's/^jobs_dir=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && jobs_dir="${tmp}"
            tmp=`sed -n 's/^jobs_byjid_dir=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && jobs_byjid_dir="${tmp}"
            tmp=`sed -n 's/^jobs_last_index_file=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && jobs_last_index_file="${tmp}"
            tmp=`sed -n 's/^scal_dir=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && scal_dir="${tmp}"
            tmp=`sed -n 's/^scal_max_entries=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && scal_max_entries="${tmp}"
            tmp=`sed -n 's/^scal_last_index_file=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && scal_last_index_file="${tmp}"
            tmp=`sed -n 's/^scal_index_table_prefix=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && scal_index_table_prefix="${tmp}"
            tmp=`sed -n 's/^submissions_dir=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && submissions_dir="${tmp}"
            tmp=`sed -n 's/^parallel_environments=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && parallel_environments="${tmp}"
            ;;
        pe)
            tmp=`sed -n 's/^max_slots=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && max_slots="${tmp}"
            tmp=`sed -n 's/^templates=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && templates="${tmp}"
            tmp=`sed -n 's/^default_template=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && default_template="${tmp}"
            ;;
        template)
            tmp=`sed -n 's/^sub_template=//p' "${tmpfile}"`
            [ -n "${tmp}" ] && sub_template="${tmp}"
            ;;
        *)
            echo "readconf - invalid section '${section}'" 1>&2
            return 3
            ;;
    esac
    rm "${tmpfile}"
    return 0
}

valcl () {
    # $@ -> the cl
    # @out config_file
    # @out option_dest
    # @out jobs
    local conflict_test
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
                conflict_test="${conflict_test}1"
                shift 1
                ;;
            -e|--err)
                option_dest="${option_dest}e"
                conflict_test="${conflict_test}1"
                shift 1
                ;;
            -j|--job)
                option_dest="${option_dest}j"
                conflict_test="${conflict_test}1"
                shift 1
                ;;
            -s|--scal)
                option_dest="${option_dest}s"
                conflict_test="${conflict_test}1"
                shift 1
                ;;
            -d|--debug)
                option_dest="${option_dest}d"
                debug_format="${2}"
                conflict_test="${conflict_test}1"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done

    case "${conflict_test}" in
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

vgminpid () {
    # $1 debugfile (prefix only)
    local debugfile
    local file
    local pid
    local min
    local opwd
    if [ "$#" -lt 1 ]; then
        echo "Error: vgminpid - expecting 1 parameter, received $#" 1>&2
        return 1
    fi
    debugfile="${1}"
    if [ -z "${debugfile}" ]; then
        echo "Error: vgminpid - debugfile is not defined or empty"
        return 1
    fi
    opwd="${PWD}"
    cd `dirname "${debugfile}"`
    debugfile=`basename "${debugfile}"`
    for file in "${debugfile}".*
    do
        pid=`echo "${file}" | sed "s/^${debugfile}.//g"`
        if ! ctype_digit "${pid}"; then
            continue
        fi
        if [ -z "${min}" -o "${pid}" -lt "${min}" ]; then
            min="${pid}"
        fi
    done
    cd "${opwd}"
}

getdestfile () {
    # $1 dest o|e|j
    # $2 jobfile
    # @echo destfile
    local dest
    local jobfile
    local out
    local tmp
    local tmp2
    if [ "$#" -lt 2 ]; then
        echo "Error: getdestfile - expecting 2 arguments, received $#" 1>&2
        return 1
    fi
    dest="${1}"
    jobfile="${2}"
    if [ -z "${dest}" ]; then
        echo "Error: getdestfile - dest is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${jobfile}" ]; then
        echo "Error: getdestfile - jobfile is not defined or empty" 1>&2
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
        vg*)
            tmp=`echo "${dest}" | sed 's/^vg//'`
            if ! ctype_digit "${tmp}"; then
                echo "Error: getdestfile - invalid debug format" 1>&2
                return 1
            fi
            # lookabehinds are not in POSIX :-(
            out=`sed -En "s/^.*--log-file=(\"?|'?)(.+)\.%p.*$\1/\2/p" "${jobfile}"`
            tmp2=`vgminpid "${out}"`
            tmp2=$((tmp2 + tmp))
            out="${out}.${tmp2}"
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

scal2jobs () {
    # $1 - scaldir
    # $2 - maxentries
    # $3 - tableprefix
    # $4 space-seperated list of scalids
    # @echo jobids
    local scaldir
    local maxentries
    local tableprefix
    local scals
    local scalid
    local scaltable
    local res
    local jobs
    if [ "$#" -lt 4  ]; then
        echo "Error: scal2jobs - expecting 4 arguments, received $#" 1>&2
        return 1
    fi
    scaldir="${1}"
    maxentries="${2}"
    tableprefix="${3}"
    scals="${4}"
    if [ -z "${scaldir}" ]; then
        echo "Error: scal2jobs - scaldir is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${maxentries}" ]; then
        echo "Error: scal2jobs - maxentries is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${tableprefix}" ]; then
        echo "Error: scal2jobs - tableplrefix is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${scalid}" ]; then
        echo "Error: scal2jobs - scals is not defined or empty" 1>&2
        return 1
    fi
    if ! ctype_digit "${maxentries}"; then
        echo "Error: scal2jobs - invalid maxentries '${maxentries}'" 1>&2
        return 1
    fi
    for scalid in ${scals}
    do
        if ! ctype_digit "${scalid}"; then
            echo "Error: scal2jobs - invalid scalid '${scalid}'" 1>&2
            return 1
        fi
        suffix=$((scalid / maxentries))
        scaltable="${scaldir}/${tableprefix}${suffix}"
        res=`sed -En "s/^${scalid}\t(.*)\$/\1/p" "${scaltable}"`
        if [ -z "${jobs}" ]; then
            res="${jobs}"
        else
            jobs="${jobs} ${jobs}"
        fi
    done
    echo "${jobs}"
    return 0
}

valcl "$@"
readrlvconf "${config_file}"
catjobs "${jobs_byjid_dir}" "${option_dest}" "${jobs}"
