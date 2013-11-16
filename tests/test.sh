#!/bin/bash -eux

# functional/stress tests for buildbox

# assumptions for this tests:
# - no other buildbox sessions running

test_profile=test123
test_variant=master

export PATH=$PATH:..

test_version=`buildbox -P $test_profile -l | head -n 1 | awk '{ print $1 }'`

mkdir -p testdata

# ------------------------------------------------------------------------------
function basic_test
{
rm -f testdata/*

for i in `seq 1 $1`; do
    buildbox -P $test_profile -s $test_variant -V $test_version -m /home/mydir=`pwd`/testdata -c "ls /; touch /home/mydir/${i}.marker; sleep $(( 1 + RANDOM % 5))" 2>testdata/$i.txt 1>&2 &
done

while true; do
    sleep 5
    if ! mount | grep -q $test_version; then
        break;
    fi
done

sleep 60 # wait until all logs get flushed (esp for large number of buildboxes)

diff <(cat testdata/*.txt | sort | uniq) <(cat <<EOF
bin
dev
etc
home
lib
proc
root
run
sbin
sys
tmp
*** Using $test_variant in version $test_version ***
usr
var
EOF
)

[[ `md5sum testdata/*.txt | cut -f1 -d' ' | sort | uniq | wc -l` -eq 1 ]]
}


# ------------------------------------------------------------------------------
# cleanup after previous tests, may fail on very first run, but that's ok
set +e
buildbox -P $test_profile -D -V $test_version
set -e

# ------------------------------------------------------------------------------
# trivial case
buildbox -P $test_profile -s $test_variant -V $test_version -c "ls /"

# ------------------------------------------------------------------------------
# bit more buildboxes :-)
basic_test 10
basic_test 100
basic_test 1000

# ------------------------------------------------------------------------------
# killing random buildbox
for i in {1..10}; do
    buildbox -P $test_profile -s $test_variant -V $test_version -m /home/mydir=`pwd`/testdata -c "ls /; touch /home/mydir/${i}.marker; sleep $(( 1 + RANDOM % 5))" 2>testdata/$i.txt 1>&2 &
done

# pick some buildbox pid and kill it
while true; do
    sleep 1
    z=`ls /tmp/*buildbox_mounts 2>/dev/null`
    [ -f "$z" ] && break
 done

pid=`cat /tmp/*buildbox_mounts | head -1 | cut -f2 -d' '`
kill -9 $pid

while true; do
    sleep 5
    if ! mount | grep -q $test_version; then
        break;
    fi
done

diff <(cat testdata/*.txt | sort | uniq) <(cat <<EOF
bin
dev
etc
home
lib
proc
root
run
sbin
sys
tmp
*** Using $test_variant in version $test_version ***
usr
var
WARNING: Dangling mounts for PID=$pid. Removing.
EOF
)

# ------------------------------------------------------------------------------
# killing all buildboxes
rm -f testdata/*

for i in {1..100}; do
    buildbox -P $test_profile -s $test_variant -V $test_version -m /home/mydir=`pwd`/testdata -c "ls /; touch /home/mydir/${i}.marker; sleep $(( 1 + RANDOM % 5))" 2>testdata/$i.txt 1>&2 &
done

sleep 60
killall -9 buildbox

# next execution should cleanup everything that is dangling...
buildbox -P $test_profile -s $test_variant -V $test_version -c "echo 'Recalibrator in action :-)'"

# ...so that next test works as usual
basic_test 10

# ------------------------------------------------------------------------------
# 2 recrusive buildboxes
buildbox -P $test_profile -D -V $test_version
repo_location=`cat ~/.buildbox_repo | sed 's#file://##'`
buildbox -P $test_profile -s $test_variant -V $test_version -m /home/mydir=`which buildbox | xargs dirname` -m /usr/repo=$repo_location \
    -c "echo '/usr/repo' > \$HOME/.buildbox_repo; sudo apt-get --assume-yes install git procmail; /home/mydir/buildbox -P $test_profile -s $test_variant -c ls /"

# ------------------------------------------------------------------------------
# failed initialization of inner buildbox (under init lock) due to no git
buildbox -P $test_profile -D -V $test_version
set +e
buildbox -P $test_profile -s $test_variant -V $test_version -m /home/mydir=`which buildbox | xargs dirname` -m /usr/repo=$repo_location \
    -c "echo '/usr/repo' > \$HOME/.buildbox_repo; sudo apt-get --assume-yes install procmail; /home/mydir/buildbox -P $test_profile -s $test_variant -c ls /"
set -e
buildbox -P $test_profile -s $test_variant -V $test_version -m /home/mydir=`which buildbox | xargs dirname` -m /usr/repo=$repo_location \
    -c "echo '/usr/repo' > \$HOME/.buildbox_repo; sudo apt-get --assume-yes install git procmail; /home/mydir/buildbox -P $test_profile -s $test_variant -c ls /"

basic_test 10

# ------------------------------------------------------------------------------
# simulate fatal error:
# - existing process
# - PID put to /tmp/*_buildbox_mounts, but no actual mount
sleep 180 &
fake_pid=$!
mount_point=$HOME/.buildbox/$test_profile/content-$test_version/rootfs
mounts_file=/tmp/`md5sum <(echo $mount_point) | awk '{print $1}'`_buildbox_mounts

echo "$mount_point/sys $fake_pid" > $mounts_file

# this should fail
if buildbox -P $test_profile -V $test_version > /tmp/log.txt; then
  false
fi

kill -9 $fake_pid

diff /tmp/log.txt <(cat <<EOF
ERROR: $mount_point/sys is not mounted! (and should be according to $mounts_file)
Cannot recover, aborting...
EOF
)

rm -f /tmp/log.txt

# ------------------------------------------------------------------------------
# after fatal error all should work as usual
# existing $mounts_file should be removed as dangling one since fake_pid is already
# killed
buildbox -P $test_profile -V $test_version > /tmp/log.txt
diff <(cat /tmp/log.txt | sort | uniq) <(cat <<EOF
*** Using $test_variant in version $test_version ***
WARNING: Dangling mounts for PID=$fake_pid. Removing.
EOF
)
rm -f /tmp/log.txt
basic_test 10

# ------------------------------------------------------------------------------
# make sure that there are no buildbox files in /tmp at the end of test
[[ `ls /tmp/*buildbox* 2>/dev/null | wc -l` -eq 0 ]]
# ... and no rubbish in mount also
if mount | grep $test_version; then false; fi


