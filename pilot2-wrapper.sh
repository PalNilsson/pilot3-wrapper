#!/bin/bash
#
# wrapper for pilot2
# author: mario.lassnig@cern.ch, paul.nilsson@cern.ch
# ./pilot2-wrapper.sh -w generic -a /scratch -j ptest -q UTA_PAUL_TEST -r UTA_PAUL_TEST -v https://aipanda007.cern.ch -l 2000

VERSION=20170914.001

function log_es() {
    if [ ! -z ${APFMON+x} ] && [ ! -z ${APFFID+x} ] && [ ! -z ${APFCID+x} ]; then
        curl -ks --connect-timeout 5 --max-time 10 --netrc -XPOST https://es-atlas.cern.ch:9203/atlas_pilotfactory-$(date --utc +"%Y-%m-%d")/event/ -d \
	     '{"timestamp": "'$(date --utc +%Y-%m-%dT%H:%M:%S.%3N)'",
           "apffid": "'$APFFID'",
           "apfcid": "'$APFCID'",
           "host": "'$(hostname -f)'",
           "pid": "'$$'",
           "version": "'$VERSION'",
           "msg": "'"$@"'"}' 1>/dev/null;
    fi
}

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

function apfmon_start() {
    curl -ks --connect-timeout 10 --max-time 20 -d state=running -d wrapper=$VERSION ${APFMON}/jobs/${APFFID}:${APFCID} 1>/dev/null
}

function apfmon_end() {
    curl -ks --connect-timeout 10 --max-time 20 -d state=exiting -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID} 1>/dev/null
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

    if [ ! -z ${APFMON+x} ] && [ ! -z ${APFFID+x} ] && [ ! -z ${APFCID+x} ]; then
        apfmon_start
        log_stdout "pilot2 wrapper version=$VERSION apffid=$APFFID apfcid=$APFCID"
    else
        log_stdout "pilot2 wrapper version=$VERSION"
    fi

    log_stdout "support: atlas-adc-pilot@cern.ch"
    log_stdout "author: mario.lassnig@cern.ch, paul.nilsson@cern.ch"

    debug=""
    workdir=""

    # put options that do not require a value at the end (like h and d), ie do not put a : after
    while getopts ":a:d:j:h:l:q:r:s:v:w:z:" opt; do
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
            r)
                # resource is needed by the wrapper but not the pilot
                resource=$OPTARG
                ;;
            s)
                site=$OPTARG
                ;;
            v)
                url=$OPTARG
                ;;
            w)
                workflow=$OPTARG
                ;;
	        z)
		        pilot_user=$OPTARG
		        ;;
            \?)
                log_stdout "Unused option: $OPTARG" >&2
                ;;
        esac
    done

    if [ -z $site ] || [ -z $resource ] || [ -z $queue ]; then
        log_stderr "site (-s), resource (-r), and queue (-q) must be specified"
        log_stderr "e.g.: -s BNL-ATLAS -r BNL_ATLAS_2 -q BNL_ATLAS_2-condor"
        log_stderr "      -s UTA_SWT2 -r UTA_PAUL_TEST -q UTA_PAUL_TEST"
       log_stderr "aborting"
        exit 1
    fi

    if [ -z $workflow ]; then
        workflow=generic
    fi

    if [ -z $lifetime ]; then
        lifetime=1200
    else
        lifetime=$lifetime
    fi

    if [ -z $job_label ]; then
        job_label=ptest
    fi

    if [ -z $url ]; then
        url="https://pandaserver.cern.ch"
    fi

    if [ -z $pilot_user ]; then
        pilotuser=$pilot_user
    fi

    # Run the OSG setup if necessary
    setup_osg

    log_stdout "--- main ---"
    log_es "main"

    log_stdout "--- environment ---"
    log_es "environment"
    log_stdout "hostname: $(hostname -f)"
    log_stdout "pwd: $(pwd)"
    log_stdout "whoami: $(whoami)"
    log_stdout "id: $(id)"
    if [[ -r /proc/version ]]; then
        log_stdout "/proc/version: $(cat /proc/version)"
    fi
    log_stdout "ulimit: \n$(ulimit -a)"
    log_stdout "env: \n$(printenv | sort)"

    log_stdout "--- proxy ---"
    log_es "proxy"
    out=$( { voms-proxy-info --all; } 2>&1)
    if [ $? -ne 0 ]; then
        out=$(echo ${out} | tr -d '\n')
        log_stderr "failed: voms-proxy-info --all: $out"
        log_stderr "aborting"
        exit 1
    fi
    log_stdout "voms-proxy-info: \n$out"

    log_stdout "--- setup working directory ---"
    log_es "setup working directory"
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

    log_stdout "--- setup ALRB ---"
    log_es "setup ALRB"
    export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
    source $ATLAS_LOCAL_ROOT_BASE/user/atlasLocalSetup.sh --quiet
    source $VO_ATLAS_SW_DIR/local/setup.sh -s $resource

    log_stdout "--- setup python ---"
    lsetup "python 2.7.9-x86_64-slc6-gcc48"

    log_stdout "--- setup DDM ---"
    log_es "setup DDM"
    export VO_LOCAL_SITE=$site
    export VO_LOCAL_RESOURCE=$resource
    export VO_LOCAL_QUEUE=$queue
    source $ATLAS_LOCAL_ROOT_BASE/utilities/oldAliasSetup.sh "rucio testing-SL6"
    log_stdout "rucio whoami: \n$(rucio whoami)"

    log_stdout "--- retrieving pilot ---"
    log_es "retrieving pilot"
    wget -q https://github.com/PalNilsson/pilot2/archive/next.tar.gz -O pilot.tar.gz
    tar xfz pilot.tar.gz --strip-components=1

    log_stdout "--- installing signal handler ---"
    log_es "installing signal handler"
    trap trap_handler SIGTERM SIGQUIT SIGSEGV SIGXCPU SIGUSR1 SIGBUS

    log_stdout "--- running pilot ---"
    log_es "running pilot"

    #python pilot.py -d -w generic -s $site -q $queue -l 1200
    python pilot.py $debug -a $workdir -j $job_label -l $lifetime -w $workflow -q $queue -s $site
        --pilot_user=$pilotuser
        --url=$url
    ec=$?
    log_stdout "exitcode: $ec"

    if [ ! -z ${APFMON+x} ] && [ ! -z ${APFFID+x} ] && [ ! -z ${APFCID+x} ]; then
        apfmon_end $ec
    fi

    log_stdout "--- cleanup ---"
    log_es "cleanup"

    cd $init_dir
    rm -rf $work_dir

    log_stdout "--- done ---"
    log_es "done"
}

main "$@"
