#!/bin/bash
#
# wrapper for pilot2
# author: mario.lassnig@cern.ch

VERSION=20161027.001

function log_es() {
    curl -ks --connect-timeout 5 --max-time 10 --netrc -XPOST https://es-atlas.cern.ch:9203/atlas_pilotfactory-$(date --utc +"%Y-%m-%d")/event/ -d \
	 '{"timestamp": "'$(date --utc +%Y-%m-%dT%H:%M:%S.%3N)'",
           "apffid": "'$APFFID'",
           "apfcid": "'$APFCID'",
           "host": "'$(hostname -f)'",
           "pid": "'$$'",
           "version": "'$VERSION'",
           "msg": "'"$@"'"}' 1>/dev/null;
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
	log_stdouterr "failed: voms-proxy-info --all: $out"
	log_stdouterr "aborting"
	exit 1
    fi
    log_stdout "voms-proxy-info: \n$out"

    log_stdout "--- setup working directory ---"
    log_es "setup working directory"
    init_dir=$(pwd)
    work_dir_template=$(pwd)/condorg_XXXXXXXX
    work_dir=$( { mktemp -d $(work_dir_template); } 2>&1)
    if [ $? -ne 0 ]; then
	log_stdouterr "failed: $work_dir"
	log_stdouterr "aborting"
	exit 1
    else
	cd $work_dir
	log_stdout "pwd: $(pwd)"
    fi

    log_stdout "--- setup ALRB ---"
    log_es "setup ALRB"
    export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
    source $ATLAS_LOCAL_ROOT_BASE/user/atlasLocalSetup.sh --quiet
    source $VO_ATLAS_SW_DIR/local/setup.sh -s INFN-T1_TEST

    log_stdout "--- setup DDM ---"
    log_es "setup DDM"
    source $ATLAS_LOCAL_ROOT_BASE/utilities/oldAliasSetup.sh rucio
    log_stdout "rucio whoami: \n$(rucio whoami)"

    log_stdout "--- retrieving pilot ---"
    log_es "retrieving pilot"

    log_stdout "--- installing signal handler ---"
    log_es "installing signal handler"
    trap trap_handler SIGTERM SIGQUIT SIGSEGV SIGXCPU SIGUSR1 SIGBUS

    log_stdout "--- running pilot ---"
    log_es "running pilot"

    log_stdout "--- cleanup ---"
    log_es "cleanup"

    cd $init_dir
    rm -rf $work_dir

    log_stdout "--- done ---"
    log_es "done"
    apfmon_end
}

main "$@"
