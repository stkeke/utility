#!/usr/bin/bash

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

# main function
for cpu_count in $(seq -s ' '  1 2 5)
do
    # generate cpu list
    cpus=$(seq -s, 1 $cpu_count)
    all_cpus=$(lscpu | grep '^CPU(s):' | awk '{print $2}')
    sibling_start=$((all_cpus/2+1))
    sibling_cpus=$(seq -s, $sibling_start $((sibling_start+cpu_count-1)))

    cpuset_cpus="$cpus,$sibling_cpus"
    cpuset_mems="0"

    docker_run="docker run --cpuset-cpus $cpuset_cpus --cpuset-mems $cpuset_mems -itd --privileged"

    # run Opt
    docker_name="tony_opt"

    echo -n "$docker_name:$cpu_count:" >> "$log_file"

    docker rm -f $docker_name
    $docker_run --name $docker_name $image bash

    docker_exec="docker exec -it $docker_name"

    $docker_exec sed -i -e 's/opcache.jit=tracing/opcache.jit=disable/' /opt/pkb/git/oss-performance/conf/php.ini
    $docker_exec cat /opt/pkb/git/oss-performance/conf/php.ini
    docker exec -itd $docker_name bash -c 'cd /opt/pkb/git/hhvm-perf; ./run.py'

    sensor_log="${docker_name}_${cpu_count}"
    sleep_show_progress 120 "waiting 120s for benchmark warm up"
    collect_sensors "$sensor_log" 30
    wait_benchmark_stop $docker_name

    $docker_exec bash -c 'grep Transactions /opt/pkb/git/hhvm-perf/workspace-latest/results/wordpress/run/run1/allout.txt | tail -1' | tee -a "$log_file"
    docker rm -f $docker_name

    # run OptJIT
    docker_name="tony_optjit"
    echo -n "$docker_name:$cpu_count:" >> "$log_file"

    docker rm -f $docker_name
    $docker_run --name $docker_name $image bash

    docker_exec="docker exec -it $docker_name"

    $docker_exec cat /opt/pkb/git/oss-performance/conf/php.ini
    docker exec -itd $docker_name bash -c 'cd /opt/pkb/git/hhvm-perf; ./run.py'

    sensor_log="${docker_name}_${cpu_count}"
    sleep_show_progress 120 "waiting 120s for benchmark warm up"
    collect_sensors "$sensor_log" 30
    wait_benchmark_stop $docker_name

    $docker_exec bash -c 'grep Transactions /opt/pkb/git/hhvm-perf/workspace-latest/results/wordpress/run/run1/allout.txt | tail -1' | tee -a "$log_file"
    docker rm -f $docker_name
done
