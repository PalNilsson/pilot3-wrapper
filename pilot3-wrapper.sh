#!/bin/bash
#
# wrapper for pilot3
# author: paul.nilsson@cern.ch
# ./pilot3-wrapper.sh -w generic -a /scratch -j ptest -q UTA_PAUL_TEST -v https://aipanda007.cern.ch -l 2000

VERSION=20220627.001

function log_stdout() {
    date --utc +"%Y-%m-%d %H:%M:%S %Z [wrapper:stdout] " | tr -d '\n'
    echo -e "$@"
}

function log_stderr() {
    date --utc +"%Y-%m-%d %H:%M:%S %Z [wrapper:stderr] "  | tr -d '\n' >&2
    echo -e "$@"
}

function log_stdouterr() {
    date --utc +"%Y-%m-%d %H:%M:%S %Z [wrapper:stdout] " | tr -d '\n'
    echo -e "$@"
    date --utc +"%Y-%m-%d %H:%M:%S %Z [wrapper:stderr] " | tr -d '\n' >&2
    echo -e "$@" >&2
}

function trap_handler() {
    log_stdouterr "intercepted signal $1 - SIG$(kill -l $1) - signalling pilot PID $pilot_pid"
    kill -s $1 $pilot_pid
    wait
}

function setup_osg() {
    # If OSG setup script exists, run it
    if [ ! -z ${OSG_GRID+x} ]; then
        log_stdout "setting up OSG environment"
        if test -f $OSG_GRID/setup.sh ; then
            log_stdout "Running OSG setup from $OSG_GRID/setup.sh"

            source $OSG_GRID/setup.sh
        else
            log_stderr "OSG_GRID defined but setup file $OSG_GRID/setup.sh does not exist"
        fi
    fi
}

function show_help() {

    log_stdout "(add help)"

}
function main() {

    log_stdout "pilot3 wrapper version=$VERSION"
    log_stdout "support: atlas-adc-pilot@cern.ch"
    log_stdout "author: paul.nilsson@cern.ch"

    debug=""
    workdir=""

    # put options that do not require a value at the end (like h and d), ie do not put a : after
    while getopts ":a:j:h:l:q:v:w:x:z:dt" opt; do
        case ${opt} in
            a)
                workdir=$OPTARG
                ;;
            d)
                debug=-d
                ;;
            j)
                job_label=$OPTARG
                ;;
            h)
                show_help
                exit 1
                ;;
            l)
                lifetime=$OPTARG
                ;;
            q)
                queue=$OPTARG
                ;;
            t)
                proxy=-t
                ;;
            v)
                url=$OPTARG
                ;;
            w)
                workflow=$OPTARG
                ;;
            x)
                hpc_resource=$OPTARG
                ;;
            z)
                pilot_user=$OPTARG
                ;;
            \?)
                log_stdout "Unused option: $OPTARG" >&2
                ;;
        esac
    done

    if [ -z $queue ]; then
        log_stderr "queue (-q) must be specified"
        log_stderr "e.g.: -q BNL_ATLAS_2-condor"
       log_stderr "aborting"
        exit 1
    fi

    if [ -z $workflow ]; then
        workflow=generic
    fi

    if [ ! -z ${lifetime+x} ]; then
        lifetime_arg="-l $lifetime"
    fi

    if [ -z $job_label ]; then
        job_label=ptest
    fi

    if [ -z $url ]; then
        url="https://pandaserver.cern.ch"
    fi

    if [ ! -z ${hpc_resource+x} ]; then
        hpc_arg="--hpc-resource $hpc_resource"
    fi

    if [ -z $pilot_user ]; then
        pilot_user="ATLAS"
    fi

    # Run the OSG setup if necessary
    setup_osg

    log_stdout "--- environment ---"
    log_stdout "hostname: $(hostname -f)"
    log_stdout "pwd: $(pwd)"
    log_stdout "whoami: $(whoami)"
    log_stdout "id: $(id)"
    if [[ -r /proc/version ]]; then
        log_stdout "/proc/version: $(cat /proc/version)"
    fi
    log_stdout "env: \n$(printenv | sort)"

    log_stdout "--- proxy ---"
    out=$( { voms-proxy-info --all; } 2>&1)
    if [ $? -ne 0 ]; then
        out=$(echo ${out} | tr -d '\n')
        log_stderr "failed: voms-proxy-info --all: $out"
        log_stderr "aborting"
        exit 1
    fi
    log_stdout "voms-proxy-info: \n$out"

    log_stdout "--- setup working directory ---"
    init_dir=$(pwd)
    work_dir_template=$(pwd)/condorg_XXXXXXXX
    work_dir=$( { mktemp -d $work_dir_template; } 2>&1)
    if [ $? -ne 0 ]; then
        log_stderr "failed: $work_dir"
        log_stderr "aborting"
        exit 1
    else
        cd $work_dir
        log_stdout "pwd: $(pwd)"
    fi

    #log_stdout "--- setup ALRB ---"
    #export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
    #source $ATLAS_LOCAL_ROOT_BASE/user/atlasLocalSetup.sh --quiet
    #source $VO_ATLAS_SW_DIR/local/setup.sh -s $queue

    #log_stdout "--- setup python ---"
    #lsetup "python 2.7.9-x86_64-slc6-gcc48"

    #log_stdout "--- setup DDM ---"
    #export VO_LOCAL_QUEUE=$queue
    #source $ATLAS_LOCAL_ROOT_BASE/utilities/oldAliasSetup.sh "rucio testing-SL6"
    #log_stdout "rucio whoami: \n$(rucio whoami)"

    log_stdout "--- retrieving pilot ---"
    wget -q http://cern.ch/atlas-panda-pilot/pilot3-dev2.tar.gz
    tar xfz pilot3-dev2.tar.gz --strip-components=1

    log_stdout "--- installing signal handler ---"
    trap trap_handler SIGTERM SIGQUIT SIGSEGV SIGXCPU SIGUSR1 SIGBUS

    log_stdout "--- running pilot ---"

    echo python3 pilot.py $proxy $debug -a $workdir -j $job_label -w $workflow -q $queue --pilot-user=$pilot_user --url=$url $lifetime_arg $hpc_arg
    python3 pilot.py $proxy $debug -a $workdir -j $job_label -w $workflow -q $queue --pilot-user=$pilot_user --url=$url $lifetime_arg $hpc_arg
    ec=$?
    log_stdout "exitcode: $ec"

    log_stdout "--- cleanup ---"

    cd $init_dir
    rm -rf $work_dir

    log_stdout "--- done ---"
}

main "$@"
