# pilot3-wrapper

Minimal test:

Place source code in /tmp/$USER/pilot3-wrapper and create subdir "workdir".

Create a proxy,

setupATLAS -3 -c centos7
lsetup rucio
./pilot3-wrapper.sh -q CERN-PROD_UCORE_2 -a /srv/workdir
