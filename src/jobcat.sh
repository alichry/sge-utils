#!/bin/sh
# Copyright 2020 Ali Cherry <cmcrc@alicherry.net>
# This file is part of SGE Utils.
#
# SGE Utils is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# SGE Utils is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with SGE Utils.  If not, see <https://www.gnu.org/licenses/>.

set -e

script_name="$(basename "${0}")"
config_file="/etc/sge-utils/jobsub.conf"

startup_notice="\
SGE Utils Copyright 2020 Ali Cherry <cmcrc@alicherry.net> under GNU Affero
General Public License version 3 or any later version. Source code retrievable
from https://github.com/alichry/sge-utils"

pad () {
    # $1 - string
    # $2 - count
    local str
    local i
    str=""
    i=0
    while [ "${i}" -lt "${2}" ];
    do
        str="${str}${1}"
        i=$((i + 1))
    done
    printf "%s" "${str}"
    return 0
}

_pad=`pad " " "${#script_name}"`

usage="Job output query usage:
    ${script_name}  [-h|-a] [-c CONF] [-s]
    ${_pad}  [-o|-e|-j|-d FORMAT] jobid [jobid2 [... [jobidn]]]
Options:
    -h, --help          prints usage
    -a, --notice        prints startup notice on how to retrieve the source code
                        of this program.
    -c CONF, --config CONF
                        use CONF as the config file.
                        Defaults to "${config_file}"
    -s, --scal          interpret jobids as scalids
    -o, --out           prints the stdout output of the job, this is the default
    -e, --err           prints the stderr output of the job
    -j, --job           prints the corresponding jobsub file
    -d FORMAT, --debug FORMAT
                        prints the corressponding debug file. Available formats:
                        vgf prints the specified valgrind's --log-file format,
                        vgl prints the generated process ids,
                        vgp prints valgrind's generated log file(s),
                        vgp%d prints the corresponding valgrind logfile where
                        %d is the process id,
                        vgpl%d is similar to vgp%d but %d is the logical
                        (starting from 1) process id
Examples:
    # print the stdout output of jobid = 1
    \$ ${script_name} 1
    # Assume we submitted a scaljob with scalid = 1 and jobids = 1 2 3
    # the below will print the stdout output of jobids 1 2 3
    \$ ${script_name} -s 1"

printnotice () {
    echo "${startup_notice}"
}
printusage () {
    printnotice
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
    local cdm
    local cmy
    local cy
    local configfile
    local section
    local sedblock
    local sedtrunc
    local sedkv
    local sedvars
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
    cmy="$(date +%m%Y)"
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
    sedblock="/^\[${section}\]/,/^\[/!d;
              /^\[/d"
    sedtrunc='/^$|^#/d'
    # the below allows optional quotes, sadly does not work on Unix
    #sedkv='s/^([A-Za-z_]+)[ \t]*=[ \t]*("?)(.*)\2$/\1=\3/g'
    sedkv='s/^([A-Za-z_]+)[ \t]*=[ \t]*(.*)$/\1=\2/g'
    sedvars="s/\\\$user/${USER}/g;
             s|\\\$home|${HOME}|g;
             s/\\\$cdm/${cdm}/g;
             s/\\\$cmy/${cmy}/g;
             s/\\\$cy/${cy}/g"

    conf="$(sed -E "${sedblock};
                    ${sedtrunc};
                    ${sedkv};
                    ${sedvars}" "${configfile}")"
    if [ -z "${conf}" ]; then
        echo "readconf - unable to read section '${section}', " \
            "check your configuration" 1>&2
        return 1
    fi
    tmpfile="$(mktemp)"
    echo "${conf}" > "${tmpfile}"
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

    if [ "$1" = "-h" -o "$1" = "--help" ]; then
        printusage
        exit 0
    fi

    while [ "$#" -gt 0 ]
    do
        case "$1" in
            -a|--notice)
                printnotice
                exit 0
                ;;
            -h|--help)
                printusage
                exit 0
                ;;
            -c|--config)
                config_file="$2"
                shift `maxshift 2 "$#"`
                ;;
            -o|--out)
                option_dest="o"
                conflict_test="${conflict_test}1"
                shift `maxshift 1 "$#"`
                ;;
            -e|--err)
                option_dest="e"
                conflict_test="${conflict_test}1"
                shift `maxshift 1 "$#"`
                ;;
            -j|--job)
                option_dest="j"
                conflict_test="${conflict_test}1"
                shift `maxshift 1 "$#"`
                ;;
            -s|--scal)
                option_scal=1
                shift `maxshift 1 "$#"`
                ;;
            -d|--debug)
                option_dest="d${2}"
                option_debug=1
                conflict_test="${conflict_test}1"
                shift `maxshift 2 "$#"`
                ;;
            *)
                break
                ;;
        esac
    done

    if [ "$#" -lt 1 ]; then
        echo "Error! Few arguments passed" 1>&2
        printusage
        return 1
    fi


    case "${conflict_test}" in
        '')
            # no dest specified, default is stdout
            option_dest="o"
            ;;
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

maxshift () {
    # $1 - the desired shift
    # $2 - the "$#" of the caller
    local desired
    local nargs
    desired="${1}"
    nargs="${2}"
    if [ -z "${desired}" ]; then
        echo "error: maxshift - desired is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${nargs}" ]; then
        echo "error: maxshift - nargs is not defiend or empty" 1>&2
        return 1
    fi
    if [ "${desired}" -gt "${nargs}" ]; then
        echo "${nargs}"
    else
        echo "${desired}"
    fi
}

getjobfile () {
    # $1 jobsbjdir
    # $2 jobid
    # @echo jobfile path
    local jobsbjdir
    local jobid
    local jobpath
    if [ "$#" -lt 2 ]; then
        echo "Error: getjobfile - expecting 2 arguments, received $#" 1>&2
        return 1
    fi
    jobsbjdir="${1}"
    jobid="${2}"
    jobpath="${jobsbjdir}/${jobid}.job"
    if [ -z "${jobsbjdir}" ]; then
        echo "Error: getjobfile - jobs_by_jid is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${jobid}" ]; then
        echo "Error: getjobfile - jobid is not defined or empty" 1>&2
        return 1
    fi
    if ! ctype_digit "${jobid}"; then
        echo "Error: getjobfile - jobid '${jobid}' is not numerical" 1>&2
        return 1
    fi
    if [ ! -f "${jobpath}" ]; then
        echo "Warning: getjobfile - jobid '${jobid}' might be invalid" 1>&2
        echo "Error: getjobfile - corresponding job file '${jobpath}' \
does not exists, did you delete it ?" 1>&2
        return 1
    fi
    if [ ! -r "${jobpath}" ]; then
        echo "Error: getjobfile - job file '${jobpath}' is not readable" 1>&2
        return 1
    fi
    echo "${jobpath}"
    return 0
}

vgpid () {
    # $1 debugfile prefix
    # @echo pids
    local debugfile
    local file
    local pid
    local pids
    local opwd
    if [ "$#" -lt 1 ]; then
        echo "Error: vgpid - expecting 1 parameter, received $#" 1>&2
        return 1
    fi
    debugfile="${1}"
    if [ -z "${debugfile}" ]; then
        echo "Error: vgpid - debugfile is not defined or empty" 1>&2
        return 1
    fi
    opwd="${PWD}"
    cd `dirname "${debugfile}"`
    debugfile=`basename "${debugfile}"`
    for file in "${debugfile}"*
    do
        pid=`echo "${file}" | sed "s/^${debugfile}//g"`
        if ! ctype_digit "${pid}"; then
            continue
        fi
        if [ -z "${pids}" ]; then
            pids="${pid}"
        else
            pids="${pids} ${pid}"
        fi
    done
    pids=`printf "%d\n" ${pids} | sort -n`
    cd "${opwd}"
    echo "${pids}"
}

getdest () {
    # $1 dest
    # $2 jobfile
    # @echo dest(file)
    local dest
    local jobfile
    local out
    local pid
    local tmp
    if [ "$#" -lt 2 ]; then
        echo "Error: getdest - expecting 2 arguments, received $#" 1>&2
        return 1
    fi
    dest="${1}"
    jobfile="${2}"
    if [ -z "${dest}" ]; then
        echo "Error: getdest - dest is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${jobfile}" ]; then
        echo "Error: getdest - jobfile is not defined or empty" 1>&2
        return 1
    fi
    case "${dest}" in
        o)
            out="$(sed -En 's/^#\$ -o (.*)$/\1/p' "${jobfile}")"
            ;;
        e)
            out="$(sed -En 's/^#\$ -e (.*)$/\1/p' "${jobfile}")"
            ;;
        j)
            out="${jobfile}"
            ;;
        *)
            echo "Error: getdest - invalid dest '${dest}'" 1>&2
            return 1
            ;;
    esac
    echo "${out}"
}

catdebug () {
    # $1 jobid
    # $2 jobfile
    # $3 dest
    local jobfile
    local destopt
    local format
    local debugprefix
    local debugsuffix
    local pid
    local tmp
    local header
    local str
    local out
    if [ "$#" -lt 3 ]; then
        echo "Error: catdebug - expecting 3 arguments, received $#" 1>&2
        return 1
    fi
    jobid="${1}"
    jobfile="${2}"
    destopt="${3}"
    if [ -z "${jobid}" ]; then
        echo "Error: catdebug - jobid is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${jobfile}" ]; then
        echo "Error: catdebug - jobfile is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${destopt}" ]; then
        echo "Error: catdebug - dest is not defined or empty" 1>&2
        return 1
    fi
    if ! ctype_digit "${jobid}"; then
        echo "Error: catdebug - jobid '${jobid}' is not numeric" 1>&2
        return 1
    fi
    case "${destopt}" in
        dvg*)
            # log-file format string
            # currently, the only legal value is --log-file="{DEBUG_FILE}"
            debugprefix=`sed -En "s/^.*--log-file=(\"|')(.+)(%p)\1.*$/\2\3/p" \
                "${jobfile}"`
            if [ "${debugprefix: -2}" = "%p" ]; then
                debugprefix="${debugprefix:0:-2}"
                debugsuffix="%p"
            fi
            case "${destopt}" in
                dvgf)
                    header="${jobid}@${jobfile}"
                    str="${debugprefix}${debugsuffix}"
                    ;;
                dvgp)
                    if [ -z "${debugsuffix}" ]; then
                        echo "Error: catdebug - cant print pids, no valgrind\
parameter was specified in log format '${debugprefix}'" 1>&2
                        return 1
                    fi
                    header="${jobid}@${debugprefix}${debugsuffix}"
                    str=`vgpid "${debugprefix}"`
                    ;;
                dvg)
                    # print all
                    if [ -z "${debugsuffix}" ]; then
                        out="${debugprefix}${pid}"
                        catfile "${out}" "${jobid}"
                    else
                        for file in "${debugprefix}"*
                        do
                            catfile "${file}" "${jobid}"
                        done
                    fi
                    ;;
                dvgl*)
                    # dvg(l)%d
                    pid=`echo "${destopt}" | sed 's/^dvgl//'`
                    if ! ctype_digit "${pid}"; then
                        echo "Error: catdebug - invalid debug format" 1>&2
                        return 1
                    fi
                    tmp=`vgpid "${debugprefix}"`
                    pid=`echo "${tmp}" | awk "FNR == ${pid} {print}"`
                    if [ -z "${pid}" ]; then
                        echo "Error: catdebug - invalid lpid '${pid}'" 1>&2
                        return 1
                    fi
                    out="${debugprefix}${pid}"
                    catfile "${out}" "${jobid}"
                    ;;
                dvg*)
                    pid=`echo "${destopt}" | sed 's/^dvg//'`
                    if ! ctype_digit "${pid}"; then
                        echo "Error: catdebug - invalid debug format" 1>&2
                        return 1
                    fi
                    out="${debugprefix}${pid}"
                    catfile "${out}" "${jobid}"
                    ;;
            esac
            ;;
        *)
            echo "Error: catdebug - invalid destopt '${destopt}'" 1>&2
            return 1
            ;;
    esac
    if [ -n "${str}" ]; then
        echo "JOB========================${header}" 1>&2
        echo "${str}"
    fi
    return 0
}

catfile () {
    # $1 dest file
    # $2 headerprefx
    local file
    local prefix
    if [ -z "${1}" ]; then
        echo "Error: catfile - passed file is not defined or empty" 1>&2
        return 1
    fi
    file="${1}"
    prefix="${2}"
    if [ ! -r "${file}" ]; then
        echo "Error: catfile - unable to read file '${file}'" 1>&2
        return 1
    fi
    echo "JOB========================${prefix}@${file}" 1>&2
    cat "${file}"
}

catjobs () {
    # $1 jobsbjdir
    # $2 optiondest o|e|j
    # $3 space-seperated list of jobids
    local jobsbjdir
    local dest
    local jobs
    local jobid
    local jobfile
    local optiondest
    local failed
    failed=0
    if [ "$#" -lt 3 ]; then
        echo "Error: catjobs - expecting at 3 arguments, received $#" 1>&2
        return 1
    fi
    jobsbjdir="${1}"
    optiondest="${2}"
    jobs="${3}"
    if [ -z "${jobsbjdir}" ]; then
        echo "Error: catjobs - jobsbjdir is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${optiondest}" ]; then
        echo "Error: catjobs - optiondest is not defined or empty" 1>&2
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
        if [ -z "${option_debug}" ]; then
            if ! dest=`getdest "${optiondest}" "${jobfile}"`; then
                failed=1
                continue
            fi
            if ! catfile "${dest}" "${jobid}"; then
                failed=1
            fi
            continue
        fi
        if ! catdebug "${jobid}" "${jobfile}" "${optiondest}"; then
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
    local njobs
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
    if [ -z "${scals}" ]; then
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
        if [ ! -f "${scaltable}" ]; then
            echo "Warning: scal2jobs - possible invalid scalid '${scalid}'" 1>&2
            echo "Error: scal2jobs - index table '${scaltable}' does not exists, \
did you delete it?" 1>&2
            continue
        fi
        res=`sed -En "s/^${scalid}\t(.*)\$/\1/p" "${scaltable}"`
        if [ -z "${njobs}" ]; then
            njobs="${res}"
        else
            njobs="${njobs} ${res}"
        fi
    done
    echo "${njobs}"
    return 0
}

valcl "$@"
readconf "${config_file}" "jobsub"
if [ -n "${option_scal}" ]; then
    jobs=`scal2jobs "${scal_dir}" "${scal_max_entries}" "${scal_index_table_prefix}" \
        "${jobs}"`
fi
catjobs "${jobs_byjid_dir}" "${option_dest}" "${jobs}"
