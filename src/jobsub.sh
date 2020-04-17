#!/bin/sh
# Author: Ali Cherry
# Constraint/note: suitable if username does not contain '~'
set -e

config_file="/etc/sge-utils/jobsub.conf"

usage="Job sumission usage:
    `basename "${0}"` [OPTIONS] <environment> <slots> <program> [args..]
OPTIONS:
    -h, --help                  prints usage
    -c, --config <conf>         use <conf> as the config file
    -t, --template <name>       use <name> as the template name
    -s, --scal                  submits multiple jobs, each using up to <slots> (1,2,4,8,..,<slots>)
    -n, --no-output-sl          do not create symbolic link in current working directory
Where:
    <environment> is the desired environment -- acceptable values are 'mpi', 'cuda' and 'smp'
    <slots> is the number of requested slots (for MPI this is # of cores),
    <program> is an executable. A compiled binary, script or command,
    and [args..] as optional arguments that are passed to your program.
Example: `basename "${0}"` mpi 1 a.out # will submit the compiled MPI program a.out with 1 core"

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

quote () {
    # adapted from http://www.etalabs.net/sh_tricks.html thanks!
    # single quotes
    #printf %s\\n "$1" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/" ;
    # double quotes (useful to allow expansion when the job is run)
    printf %s\\n "${1}" | sed 's/"/\\"/g;1s/^/"/;$s/$/"/'
}

valcl () {
    # $@ -> the cl
    # @out config_file
    # @out sub_template_name
    # @out option_scal
    # @out environment
    # @out prog
    # @out nslots
    # @out prog_args
    local arg

    while [ "$#" -gt 3 ]
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
            -t|--template)
                sub_template_name="$2"
                shift 2
                ;;
            -s|--scal)
                option_scal=1
                shift 1
                ;;
            -n|--no-output-sl)
                no_output_sl=1
                shift 1
                ;;
            *)
                break
                ;;
        esac
    done

    if [ "$#" -lt 3 ]; then
        echo "Error! Few arguments passed" 1>&2
        printusage
        return 1
    fi

    environment="${1}"
	nslots="${2}"
	prog="${3}"

    if [ -z "${environment}" ]; then
        echo "Error: valcl - environment argument is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${nslots}" ]; then
        echo "Error: valcl - slots argument is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${prog}" ]; then
        echo "Error: valcl - program argument is not defined or empty" 1>&2
        return 1
    fi

    shift 3
    for arg in "$@"
    do
        if [ -z "${prog_args}" ]; then
            prog_args=`quote "${arg}"`
            continue
        fi
        prog_args="${prog_args} `quote "${arg}"`"
    done
    return 0
}


nextindex () {
    # $1 lif
    # TODO: Use locking...
    local lif
    local index
    if [ -z "${1}" ]; then
        echo "Error: nextindex - last index file argument is not defined or empty" 1>&2
        return 1
    fi
    lif="${1}"
    if [ -f "${lif}" ]; then
        index=`cat "${lif}"`
        if [ -z "${index}" ]; then
            index=0
        fi
        if ! ctype_digit "${index}"; then
            echo "Error: nextindex - invalid index '${index}'" 1>&2
            return 1
        fi
        index=$((index + 1))
    else
        index=1
    fi
    echo "${index}"
    return 0
}

setindex () {
    # $1 - lif
    # $2 - index value
    # TODO: Use locking...
    local lif
    local index
    if [ -z "${1}" ]; then
        echo "Error: setindex - lastindex filename  argument is " \
            " not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${2}" ]; then
        echo "Error: setindex - index argument is not defined or empty" 1>&2
        return 2
    fi
    lif="${1}"
    index="${2}"
    if ! ctype_digit "${index}"; then
        echo "Error: setindex - invalid index '${index}'" 1>&2
        return 2
    fi
    echo "${index}" > "${lif}"
    return 0
}

chk () {
    # @env $USER
    # @env $PWD
    # @env $cdm
    if [ -z "${USER}" ]; then
		echo "\$USER is not defined or empty, are you " \
            "running this from your toaster?" 1>&2
		return 999
    fi
    if [ -z "${cdm}" ]; then
        echo "Error: chk - \$cdm is not defined or empty" 1>&2
        return 999
    fi
    case "$PWD/" in
        /home/$USER/*)
            ;;
        *)
            echo "Error, please run `basename ${0}` from your home directory." 1>&2
            return 1
    esac
    return 0
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

chkpenv () {
    # @env $parallel_environments
    # @env $environment
    local penv
    local penv_ok
    penv_ok=0
    for penv in ${parallel_environments}
    do
        if [ "${environment}" = "${penv}" ]; then
            penv_ok=1
            break;
        fi
    done
    if [ "${penv_ok}" -eq 0 ]; then
        echo "Error! Invalid parallel environment '${environment}'" 1>&2
        return 3
    fi
    return 0
}

valtemplt () {
    # @env $default_template
    # @env $templates
    # @out $sub_template_name if it was empty
    local templt
    local templt_ok
    templt_ok=0
    if [ -z "${sub_template_name}" ]; then
        sub_template_name="${default_template}"
    fi
    for templt in ${templates}
    do
        if [ "${sub_template_name}" = "${templt}" ]; then
            templt_ok=1
            break;
        fi
    done
    if [ "${templt_ok}" -eq 0 ]; then
        echo "Error! Invalid template '${sub_template_name}'" 1>&2
        return 3
    fi
    return 0
}

prepare () {
    # $1 - jobsdir
    # $2 - jobsbjdir (jobs by jid dir)
    # $3 - subdir
    # $4 - scaldir
    local jobsdir
    local jobsbjdir
    local subdir
    if [ "$#" -lt 4 ]; then
        echo "Error: prepare - expected 4 arguments, received $#" 1>&2
        return 1
    fi
    jobsdir="${1}"
    jobsbjdir="${2}"
    subdir="${3}"
    scaldir="${4}"
    if [ -z "${jobsdir}" ]; then
        echo "Error: prepare - jobsdir argument is not defined or empty"
        return 1
    fi
    if [ -z "${jobsbjdir}" ]; then
        echo "Error: prepare - jobsbjdir argument is not defined or empty"
        return 1
    fi
    if [ -z "${subdir}" ]; then
        echo "Error: prepare - subdir argument is not defined or empty"
        return 1
    fi
    if [ -z "${scaldir}" ]; then
        echo "Error: prepare - scaldir argument is not defined or empty"
        return 1
    fi
    if ! mkdir -p "${jobsdir}"; then
        echo "Unable to create dir '${jobsdir}'" 1>&2
        return 1
    fi
    if ! mkdir -p "${jobsbjdir}"; then
        echo "Unable to create dir '${jobsbjdir}'" 1>&2
        return 1
    fi
    if ! mkdir -p "${subdir}"; then
        echo "Unable to create dir '${subdir}'" 1>&2
        return 1
    fi
    if ! mkdir -p "${scaldir}"; then
        echo "Unable to create dir '${scaldir}'" 1>&2
        return 1
    fi
}

genjob () {
    # $1 - job template
    # $2 - slots
    # $3 - jobsdir
    # $4 - subdir
    # $5 - last index file
    # $6 - progpath
    # $7 - literally-quoted prog args
    # @echo jobfile on success
    local template
    local slots
    local progname
    local progpath
    local progargs
    local subdir
    local jobsdir
    local lif
    local jobname
    local jobfile
    local outfile
    local errfile
    local index
    local tmpfile
    local tmpfile2
    if [ "$#" -lt 5 ]; then
        echo "Error: genjob - few arguments passed, received $# expecting 5" 1>&2
        return 1
    fi
    template="${1}"
    slots="${2}"
    jobsdir="${3}"
    subdir="${4}"
    lif="${5}"
    progpath="${6}"
    progname=`basename "${progpath}"`
    progargs="${7}"
    if [ -z "${template}" ]; then
        echo "Error: genjob - template argument is not defined or empty" 1>&2
        return 2
    fi
    if [ -z "${slots}" ]; then
        echo "Error: genjob - slots argument is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${jobsdir}" ]; then
        echo "Error: genjob - jobsdir argument is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${subdir}" ]; then
        echo "Error: genjob - subdir argument is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${lif}" ]; then
        echo "Error: genjob - lastindex file argument is not " \
            "defined or empty" 1>&2
        return 1
    fi
    if [ -z "${progpath}" ]; then
        echo "Error: genjob - progpath argument is not defined or empty" 1>&2
        return 1
    fi

    if ! ctype_digit "${slots}"; then
		echo "Error: genjob - invalid number of slots requested, not even numerical: ${slots}" 1>&2
		return 5
	fi

    if [ "${slots}" -lt 1 -o "${slots}" -gt "${max_slots}" ]; then
        echo "Error: genjob - invalid number of slots requested, acceptable range is 1-${max_slots}" 1>&2
        return 6
    fi

    if [ ! -f "${template}" ]; then
        echo "Error: genjob - passed job template '${template}' does not exists" 1>&2
        return 7
    fi

    if [ ! -r "${template}" ]; then
        echo "Error: genjob - passed job template '${template}' is not readable" 1>&2
        return 8
    fi
	if [ ! -f "${progpath}" ]; then
        if ! command -v "${progpath}" > /dev/null 2>&1; then
		    echo "Passed program '${progpath}' does not exists!" 1>&2
		    return 4
        fi
        progpath=`which "${progpath}"`
	fi
	if [ ! -x "${progpath}" ]; then
        echo "Passed program '${progpath}' is not executable, make sure " \
            "it refers to a compiled binary or a script" 1>&2
		return 5
	fi

    index=`nextindex "${lif}"`

	jobname="${USER}~${progname}-${slots}-${index}"
	outfile="${subdir}/${jobname}.out"
	errfile="${subdir}/${jobname}.err"
	jobfile="${jobsdir}/${jobname}.job"
    debugfile="${subdir}/${jobname}.vg"

    sed "s|{JOB_NAME}|${jobname}|g;
         s|{OUT_FILE}|${outfile}|g;
         s|{ERR_FILE}|${errfile}|g;
         s|{NSLOTS}|${slots}|g;
         s|{PROG_PATH}|${progpath}|g;
         s|{DEBUG_FILE}|${debugfile}|g" "${template}" > "${jobfile}"

    tmpfile="$(mktemp)"
    tmpfile2="$(mktemp)"
    printf "%s" "${progargs}" > "${tmpfile}"
    awk -v tmpfile="${tmpfile}" \
        'BEGIN{getline l < tmpfile}/{PROG_ARGS}/{gsub("{PROG_ARGS}",l)}1' \
        "${jobfile}" > "${tmpfile2}"
    cp "${tmpfile2}" "${jobfile}"
    rm "${tmpfile}" "${tmpfile2}"
    setindex "${lif}" "${index}"

    echo "${jobfile}"
    return 0
}

submitjob () {
    # $1 jobfile
    # @env $parallel_environments
    # @echo jobid on success
    local jobid
    local jobfile
    local jobname
    local progname
    local outfile
    local errfile
    local slots
    local outsl
    local errsl
    local sub
    local penvs
    if [ "$#" -lt 1 ]; then
        echo "Error: submitjob - expecting 1 arguments, received $#" 1>&2
        return 1
    fi
    jobfile="${1}"
    if [ ! -f "${jobfile}" ]; then
        echo "Error: submitjob - passed jobfile '${jobfile}' does not exists!" 1>&2
        return 4
    fi
    if [ ! -r "${jobfile}" ]; then
        echo "Error: submitjob - passed jobfile '${jobfile}' is not readable" 1>&2
        return 5
    fi
    penvs=`echo "${parallel_environments}" | \
        sed -E 's/[ \t]+([a-zA-Z_]+)/\\\|\1/g'`
    jobname="$(sed -En 's/^#\$ -N (.*)$/\1/p' "${jobfile}")"
    outfile="$(sed -En 's/^#\$ -o (.*)$/\1/p' "${jobfile}")"
    errfile="$(sed -En 's/^#\$ -e (.*)$/\1/p' "${jobfile}")"
    slots="$(sed -En 's/^#\$ -pe .+ ([0-9]+)$/\1/p' "${jobfile}")"
    progname=`echo "${jobname}" | sed -E 's/^.+~(.*)-[0-9]+-[0-9]+$/\1/'`
	if [ -z "${jobname}" -o -z "${outfile}" -o -z "${errfile}" ]; then
		echo "Error: submitjob - unable to retrieve jobname, outfile or errfile \
from '${jobfile}'" 1>&2
		return 1
	fi
    if [ -z "${slots}" ]; then
        slots=1
        echo "Warning: submitjob - no slots value was found in jobfile/template. \
Using slots=1" 1>&2
    fi
	outsl="${progname}-${slots}.out"
	errsl="${progname}-${slots}.err"

	touch "${outfile}"
	touch "${errfile}"

    if [ -z "${no_output_sl}" ]; then
        ln -si "${outfile}" "${outsl}"
        ln -si "${errfile}" "${errsl}"
    fi

	sub=`"${qsub}" "${jobfile}" 2>&1`
	if [ $? -ne 0 ]; then
		echo "Some errors or warnings occurred. qsub exited with non-zero status." 1>&2
        echo "qsub stdout/stderr:" 1>&2
        echo "${sub}" 1>&2
        echo "------------------------" 1>&2
    fi

    jobid=`echo "${sub}" | sed -En 's/^Your job ([0-9]+).*$/\1/p'`
    if [ -z "${jobid}" ]; then
        echo "Unable to retrieve job id, cleaning up." 1>&2
        if [ -z "${no_output_sl}" ]; then
            rm -i "${outsl}"
            rm -i "${errsl}"
        fi
        rm "${outfile}"
        rm "${errfile}"
        rm "${jobfile}"
        return 4
    fi

	ln -si "${jobfile}" "${jobs_byjid_dir}/${jobid}.job"

    echo "${jobid}"
    return 0
}

addscal () {
    # $1 - scaldir
    # $2 - maxentries
    # $3 - lif
    # $4 - tableprefix
    # $5 - jobs (list of space-seperated job ids)
    # @echo scalid in case of success
    local scaldir
    local maxentries
    local lif
    local tableprefix
    local suffix
    local scalid
    local scaltable
    local jobs
    if [ "$#" -lt 5 ]; then
        echo "Error: addscal - expecting 5 arguments, received $#" 1>&2
        return 1
    fi
    scaldir="${1}"
    maxentries="${2}"
    lif="${3}"
    tableprefix="${4}"
    jobs="${5}"
    if [ -z "${scaldir}" ]; then
        echo "Error: addscal - scaldir is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${maxentries}" ]; then
        echo "Error: addscal - max entries is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${lif}" ]; then
        echo "Error: addscal - last index file is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${tableprefix}" ]; then
        echo "Error: addscal - table prefix is not defined or empty" 1>&2
        return 1
    fi
    if [ -z "${jobs}" ]; then
        echo "Error: addscal - jobs is not defined or empty" 1>&2
        return 1
    fi
    scalid=`nextindex "${lif}"`
    suffix=$((scalid / maxentries))
    scaltable="${scaldir}/${tableprefix}${suffix}"

    printf "%d\t%s\n" "${scalid}" "${jobs}" >> "${scaltable}"
    setindex "${lif}" "${scalid}"
    echo "${scalid}"
}

run () {
    # $@ - cl args
    valcl "$@"
    readconf "${config_file}" "jobsub"
    chkpenv
    readconf "${config_file}" "pe ${environment}"
    valtemplt
    readconf "${config_file}" "template ${sub_template_name}"
    prepare "${jobs_dir}" "${jobs_byjid_dir}" "${submissions_dir}" "${scal_dir}"

    jobs=""
    nc="${nslots}"
    if [ -n "${option_scal}" ]; then
        nc=1
    fi

    while :
    do
        if [ "${nc}" -gt "${nslots}" ]; then
            break;
        fi
        echo "Submitting job with ${nc} slots"
        if ! job_file=`genjob "${sub_template}" "${nc}" "${jobs_dir}" "${submissions_dir}" \
            "${jobs_last_index_file}" "${prog}" "${prog_args}"`; then
            exit $?
        fi
        if ! job_id=`submitjob "${job_file}"`; then
            ret=$?
            if [ -z "${job_id}" ]; then
                echo "Unable to submit job, exiting.."
                if [ -n "${jobs}" ]; then
                    echo "Deleting previous jobs before exiting.."
                    qdel "${jobs}"
                fi
                echo "Bye :("
                exit $ret
            fi
        fi
        if [ -z "${jobs}" ]; then
            jobs="${job_id}"
        else
            jobs="${jobs} ${job_id}"
        fi
        nc=$((nc * 2))
    done

    if [ -n "${option_scal}" ]; then
        scal_id=`addscal "${scal_dir}" "${scal_max_entries}" \
            "${scal_last_index_file}" "${scal_index_table_prefix}" \
            "${jobs}"`
    fi

    s=`test "$((nc / 2))" -gt 1 -a -n "${option_scal}" && printf "s" || true`
    submit_output="Your job${s} has been submitted, use 'qstat' to monitor the status of your job${s}.
Job ID${s}: ${jobs}
When the job is finished, it will disappear from qstat.
    To view job's status after completion, use the 'qacct -j <jobid>'
    To display the output file of your job, after its completion use:
        jobcat -o ${jobs}
    To display the error file of your job, after its completion use:
        jobcat -e ${jobs}"

    scal_output="Scalability Report ID: ${scal_id:-NIL}
To view the scalability result after completion, use the following:
    scalcat ${scal_id:-NIL}"

    note="If you don't like memorizing the job id, you can use traditional cat.
Use 'ls' to list the files, you'll find files named
<program_name>-<nslots>.{out,err} -- cat it"

    echo "${submit_output}"
    if [ -n "${option_scal}" ]; then
        echo "${scal_output}"
    fi
    echo "${note}"
}

run "$@"
