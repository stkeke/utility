#!/usr/bin/bash

# Usage
# uncore frequency iteration for benchmark
#
# Change cpu type from icx to your type - search --cpu-type
# Change image to your image
# Require cpu_freq.sh script in utility repo
# 	git clone https://github.com/stkeke/utility.git
#
# git clone https://github.com/intel-sandbox/frameworks.benchmarking.cloud.language.runtime.git
# put this script to frameworks.benchmarking.cloud.language.runtime/scripts/workload-tools/

docker kill $(docker ps -aq); docker rm $(docker ps -qa)

WORKDIR=$(dirname $0)
source "$WORKDIR"/cpu_freq.sh
image=pkb-1.25.0-wp5.6-php8.0.18-optjit

log_dir="$WORKDIR/$(basename $0 .sh)/"
log_file="$log_dir/$(basename $0).log"
sudo rm -rf "$log_dir"
mkdir -p "$log_dir"

sudo rm -rf "$WORKDIR"/run-*

# functions
function sleep_show_progress()
{
    local seconds=$1
    local message="$2"

    if [[ -n "$message" ]]; then
        echo "$message"
    fi

    local count=1
    while(($count <= $seconds))
    do
        echo -ne "\r$count"
        sleep 1
        count=$((count+1))
    done
}

function collect_sensors()
{
    local log_file="$1"
    local log_seconds="$2"

    local count=0
    rm -rf "${log_file}.freq.csv" "${log_file}.temp.csv"

    # header of freq csv file
    echo "$(cat /proc/cpuinfo | grep 'processor' | awk -F: '{print $2}' | sed -e 's/ //g' | tr '\n' ',')" >> "${log_file}.freq.csv"

    # header of temp csv file
    echo "$(/usr/bin/sensors | /usr/bin/sensors | grep  -E 'Package id|Core' | awk -F: '{print $1}' | sed -e 's/Core //g' | sed -e 's/id //g' | tr '\n' ',')" >> "${log_file}.temp.csv"

    while (( count <= log_seconds ))
    do
        echo "$(cat /proc/cpuinfo | grep -E 'cpu MHz' | awk '{print $4}' | tr  '\n' ',')" >> "${log_file}.freq.csv"
        echo "$(/usr/bin/sensors | grep  -E 'Package id|Core' | awk -F: '{print $2}' | awk '{print $1}' | sed -e 's/+\(.*\)°C/\1/g' | tr '\n' ',')" >> "${log_file}.temp.csv"

        sleep 2;
        count=$((count+2))
        echo -ne "\rCollected $count seconds"
    done
    echo ""
}

function wait_benchmark_stop()
{
    local docker_name="$1"
    run="$(docker exec -it $docker_name bash -c 'ps -ef | grep -v grep | grep run.py')"
    while [[ -n "$run" ]]; do
        # benchmark running
        echo -ne "\rstill running $(date)"
        sleep 2
        run="$(docker exec -it $docker_name bash -c 'ps -ef | grep -v grep | grep run.py')"
    done
    echo ""
}

function get_cpuset_cpus()
{
    local cpu_count="$1"
    local cpus=$(seq -s, 1 $cpu_count)
    local all_cpus=$(lscpu | grep '^CPU(s):' | awk '{print $2}')
    local sibling_start=$((all_cpus/2+1))
    local sibling_cpus=$(seq -s, $sibling_start $((sibling_start+cpu_count-1)))

    echo "$cpus,$sibling_cpus"
}

function get_cpuset_mems()
{
    # TODO: now we use hard code
    local cpu_count="$1"
    echo "0"
}

function run_benchmark()
{
    local docker_name="$1"

    "$WORKDIR"/run_containers.sh --count 8 --env runtime.env --image $image --numa-pinning

    if [[ $docker_name == "tony_opt" ]]; then
         # disable JIT
        local d=""
        for d in $(docker ps -q); do
            docker exec -it $d sed -i -e 's/opcache.jit=tracing/opcache.jit=disable/' ../oss-performance/conf/php.ini;
            docker exec -it $d cat ../oss-performance/conf/php.ini;
        done
    fi

    $WORKDIR/run_benchmark.sh --run-case 0 --cpu-type icx --emon --emon-time 120
}

# main function
for uncore_freq in $(seq 8 2 22); do
    # set fixed uncore frequency
    uncore_set_fixed_freq $uncore_freq

    # benchmark Opt
    docker_name="tony_opt"
    echo "$(date):$docker_name:$uncore_freq:" >> "$log_file"
    run_benchmark $docker_name
    mv run-* "$log_dir"/${docker_name}.${uncore_freq}

    # run OptJIT
    docker_name="tony_optjit"
    echo "$(date):$docker_name:$uncore_freq:" >> "$log_file"
    run_benchmark $docker_name
    mv run-* "$log_dir"/${docker_name}.${uncore_freq}
done # uncore frquency loop

uncore_restore_freq
