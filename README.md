# SGE Utils
This repository contains shell tools to submit jobs into SGE and display various outputs.  
Essentially, jobsub is the submission tool and jobcat prints stdout, stderr, jobscript or debug of a job submitted with jobsub. The aim of this repository is to become an extension to SGE workflows.  
jobsub is extremely useful, it allows reusuability of job templates that can be distributed to various users and manages output files without the hassle of keeping tracking other files.  
Available templates:

* MPI: simple MPI template.
* MPI/Valgrind: debugging template for MPI programs, valgrind aids in detecting invalid memory read or write in the passed program.
* time/MPI: Measures the execution of an MPI program along with the MPI bootstrap using the time command (wallclock, user CPU and system CPU time).
* SMP: simple template where the executable is the entry point of the jobscript. jobsub allows parameter expansion.
* time/SMP: Measures the execution of an executable using the time command (wallclock, user CPU and system CPU time).
* Valgrind/SMP: Valgrind debugging template for your executable.

## Job submission usage
jobsub aims to facilitates job submission. jobsub requires at least 3 arguments, the parallel environment, number of slots and the executable. The executable can be a compiled binary, an executable shell script or a shell command. Comparing this with qsub, you are not dealing with qsub format such as providing command-line options to fill in the stdout, stderr, queue, pe env slots that will span a long command-line... jobsub facilitates the submission by utilizing job templates and user-defined configuration.  
An important feature of jobsub, besides simplicity, is to submit multiple jobs while exponentially increasing the number of slots per job (-s option)  
Combining the above, jobsub is a suitable extension for an SGE workflow. Due its user-friendliness, jobsub is hugely beneficial for parallel programming students.

### Usage

```
$ jobsub -h
Job sumission usage:
    jobsub [OPTIONS] <environment> <slots> <program> [args..]
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
Example: jobsub mpi 1 a.out # will submit the compiled MPI program a.out with 1 core
```
### Sample usage 
```
$ jobsub -n -s -t mpi 2 helloworld
Submitting job with 1 slots
Submitting job with 2 slots
Your jobs has been submitted, use 'qstat' to monitor the status of your jobs.
Job IDs: 145 146
When the job is finished, it will disappear from qstat.
    To view job's status after completion, use the 'qacct -j <jobid>'
    To display the output file of your job, after its completion use:
        jobcat -o 145 146
    To display the error file of your job, after its completion use:
        jobcat -e 145 146
Scalability Report ID: 1
To view the scalability result after completion, use the following:
    scalcat 1
If you don't like memorizing the job id, you can use traditional cat.
Use 'ls' to list the files, you'll find files named
<program_name>-<nslots>.{out,err} -- cat it
```

jobsub stores the output files under the ```submissions_dir``` specified in the configuration file and, unless the -n option is used, it will created symbolic links in the user's current working directory that points to the output and error files. 

### Parameter expansion 
```
$ jobsub smp 1 "echo hello from \`hostname\`" # hello from ip-10-0-4-217
```


## Job output queries
### Usage
```
[centos@ip-10-0-11-5 temp]$ ./jobcat.sh --help
Job output query usage:
    jobcat.sh [OPTIONS] jobid [jobid2 [... [jobidn]]]
OPTIONS:
    -h, --help                  prints usage
    -c, --config <conf>         use <conf> as the config file
    -s, --scal                  interpret jobids as scalids
    -o, --out                   prints the stdout output of the job (conflicts with -e|-j)
    -e, --err                   prints the stderr output of the job (conflicts with -o|-j)
    -j, --job                   prints the corresponding jobsub file (conflicts with -o|-e)
    -d, --debug <format>        prints the corressponding debug file. Available formats:
                                vgf prints the specified valgrind's --log-file format,
                                vgl prints the generated process ids,
                                vgp prints valgrind's generated log file(s),
                                vgp%d prints the corresponding valgrind logfile
                                where %p is the process id,
                                vgpl%d is similar to vgp%d but %d is the logical
                                (starting from 1) process id
```
### Sample usage
Using jobid 146 (by default jobcat will print the output file -- stdout)

```
$ jobcat 146
JOB========================146@/home/centos/.submissions/1604/centos~helloworld-2-2.out
Hello world from processor ip-10-0-4-217, rank 1 out of 2 processors
Hello world from processor ip-10-0-4-217, rank 0 out of 2 processors
```
From the job submission section, We specified the -s option to submit multiple jobs. We can use the scalid instead of the jobid in jobcat. Using scalid 1 to print the result of multiple jobs submitted using jobsub

```
$ jobcat -s -o 1
JOB========================145@/home/centos/.submissions/1604/centos~helloworld-1-1.out
Hello world from processor ip-10-0-4-217, rank 0 out of 1 processors
JOB========================146@/home/centos/.submissions/1604/centos~helloworld-2-2.out
Hello world from processor ip-10-0-4-217, rank 1 out of 2 processors
Hello world from processor ip-10-0-4-217, rank 0 out of 2 processors
```

## Configuration file
Configuration file format is a key-value with sections that can classify keys. Available variables that can be used in the config:  

* $home - the home directory of the user ($HOME).
* $user - the username of the user ($USER)
* $cdm - current daymonth (e.g. 1604)
* $cym - current monthyear (e.g. 052020)
* $cy - current year (e.g. 2020)

Each value will be read until the end-of-line or until double-quotes if it was double quoted. Spaces between key, equal sign and value are not required and do not harm the configuration.

```
[jobsub]
qsub = qsub
jobs_dir = $home/.jobs/$cmy
jobs_byjid_dir = $home/.jobs/by-jid
jobs_last_index_file = $home/.jobs/$cmy/.last
scal_dir = $home/.scal
scal_max_entries = 1000000
scal_last_index_file = $home/.scal/.last
scal_index_table_prefix = scal.index
submissions_dir = $home/.submissions/$cmy
parallel_environments = mpi smp

[pe mpi]
max_slots = 64
templates = mpi_default mpi_time mpi_valgrind
default_template = mpi_default

[pe smp]
max_slots = 64
templates = smp_default smp_time smp_valgrind
default_template = smp_default

[template mpi_default]
sub_template = /etc/sge-utils/templates/mpisub.job.template

[template mpi_time]
sub_template = /etc/sge-utils/templates/timempisub.job.template

[template mpi_valgrind]
sub_template = /etc/sge-utils/templates/valgrindmpisub.job.template

[template smp_default]
sub_template = /etc/sge-utils/templates/smpsub.job.template

[template smp_time]
sub_template = /etc/sge-utils/templates/timesmpsub.job.template

[template smp_valgrind]
sub_template = /etc/sge-utils/templates/valgrindsmpsub.job.template
```

## TODO
* Maybe seperate the usage of jobcat -d into a different tool.
* Add usage, limitations and requirements in job templates
* POSIX does not allow lookahead/behind in regular expressions, we have a few grep commandlines that are not compatible under Unix. Replace grep lookbehind with sed.