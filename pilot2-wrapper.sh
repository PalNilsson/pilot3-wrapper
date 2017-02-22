#!/bin/bash
#
# wrapper for pilot2
# author: mario.lassnig@cern.ch

VERSION=20170222.001

function log_es() {
    # curl -ks --connect-timeout 5 --max-time 10 --netrc -XPOST https://es-atlas.cern.ch:9203/atlas_pilotfactory-$(date --utc +"%Y-%m-%d")/event/ -d \
    # 	 '{"timestamp": "'$(date --utc +%Y-%m-%dT%H:%M:%S.%3N)'",
    #        "apffid": "'$APFFID'",
    #        "apfcid": "'$APFCID'",
    #        "host": "'$(hostname -f)'",
    #        "pid": "'$$'",
    #        "version": "'$VERSION'",
    #        "msg": "'"$@"'"}' 1>/dev/null;
    sleep 0.01
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
    curl -ks --connect-timeout 10 --max-time 20 -d state=exiting -d rc=0 ${APFMON}/jobs/${APFFID}:${APFCID} 1>/dev/null
}

function trap_handler() {
    log_stdouterr "intercepted signal $1 - SIG$(kill -l $1) - signalling pilot PID $pilot_pid"
    kill -s $1 $pilot_pid
    wait
}

function main() {
    apfmon_start
    log_stdout "pilot2 wrapper version=$VERSION apffid=$APFFID apfcid=$APFCID"

    log_stdout "support: atlas-adc-pilot@cern.ch"
    log_stdout "author: mario.lassnig@cern.ch"

    log_stdout "--- parsing arguments ---"

    while getopts ":s:q:r:" opt; do
        case $opt in
            s)
                configured_site=$OPTARG
                ;;
	    r)
                configured_resource=$OPTARG
                ;;
            q)
                configured_queue=$OPTARG
                ;;
            \?)
                log_stdout "Unused option: $OPTARG" >&2
                ;;
        esac
    done

    if [ -z $configured_site ] || [ -z $configured_resource ] || [ -z $configured_queue ]; then
        log_stderr "site (-s), resource (-r), and queue (-q) must be specified"
	log_stderr "e.g.: -s BNL-ATLAS -r BNL_ATLAS_2 -q BNL_ATLAS_2-condor"
        log_stderr "aborting"
        exit 1
    fi
    log_stdout "Site: $configured_site"
    log_stdout "Resource: $configured_resource"
    log_stdout "Queue: $configured_queue"

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
    source $VO_ATLAS_SW_DIR/local/setup.sh -s $configured_resource

    log_stdout "--- setup DDM ---"
    log_es "setup DDM"
    source $ATLAS_LOCAL_ROOT_BASE/utilities/oldAliasSetup.sh "rucio 1.10.0"
    log_stdout "rucio whoami: \n$(rucio whoami)"

    log_stdout "--- retrieving pilot ---"
    log_es "retrieving pilot"
    wget -q https://github.com/mlassnig/pilot2/archive/ongoing-work.tar.gz -O pilot.tar.gz
    tar xfz pilot.tar.gz --strip-components=1

    log_stdout "--- installing signal handler ---"
    log_es "installing signal handler"
    trap trap_handler SIGTERM SIGQUIT SIGSEGV SIGXCPU SIGUSR1 SIGBUS

    log_stdout "--- running pilot ---"
    log_es "running pilot"
    python pilot.py -d -s $configured_site -q $configured_queue -l 60

    log_stdout "--- cleanup ---"
    log_es "cleanup"

    cd $init_dir
    rm -rf $work_dir

    log_stdout "--- done ---"
    log_es "done"
    apfmon_end
}

main "$@"
