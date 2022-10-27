#!/usr/bin/bash

WORKDIR=$(dirname $0)
source "$WORKDIR"/cpu_freq.sh
image=pkb-1.25.0-wp5.6-php8.0.18-optjit

log_file="$(basename $0).log"
rm -rf "$log_file"

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
    local cpu_count="$2"

    # generate cpu list
    local cpuset_cpus=$(get_cpuset_cpus $cpu_count)
    local cpuset_mems=$(get_cpuset_mems $cpu_count)

    # remove any existent docker instance
    docker rm -f $docker_name

    local docker_run="docker run --cpuset-cpus $cpuset_cpus --cpuset-mems $cpuset_mems -itd --privileged"

    # start OptJIT image
    $docker_run --name $docker_name $image bash


    local docker_exec="docker exec -it $docker_name"

    if [[ $docker_name == "tony_opt" ]]; then
         # disable JIT
        $docker_exec sed -i -e 's/opcache.jit=tracing/opcache.jit=disable/' /opt/pkb/git/oss-performance/conf/php.ini
    fi

    $docker_exec cat /opt/pkb/git/oss-performance/conf/php.ini

    # run benchmark
    docker exec -itd $docker_name bash -c 'cd /opt/pkb/git/hhvm-perf; ./run.py'

    # sensor_log="${docker_name}_${cpu_count}_${core_freq}_${uncore_freq}"
    # sleep_show_progress 120 "waiting 120s for benchmark warm up"
    # collect_sensors "$sensor_log" 30
    wait_benchmark_stop $docker_name

    # stop image
    $docker_exec bash -c 'grep Transactions /opt/pkb/git/hhvm-perf/workspace-latest/results/wordpress/run/run1/allout.txt | tail -1' | tee -a "$log_file"
    docker rm -f $docker_name

}

# main function
for cpu_count in $(seq -s ' '  5 2 15); do
for core_freq in $(seq 1000000 100000 2600000); do
for uncore_freq in $(seq 8 1 22); do
    # set fixed core frequency
    core_set_fixed_freq $core_freq

    # set fixed uncore frequency
    uncore_set_fixed_freq $uncore_freq

    # benchmark Opt
    docker_name="tony_opt"
    echo -n "$docker_name:$cpu_count:$core_freq:$uncore_freq:" >> "$log_file"
    run_benchmark $docker_name $cpu_count

    # run OptJIT
    docker_name="tony_optjit"
    echo -n "$docker_name:$cpu_count:$core_freq:$uncore_freq:" >> "$log_file"
    run_benchmark $docker_name $cpu_count
done # uncore frquency loop
done # core frequency loop
done # cpu_count loop

uncore_restore_freq