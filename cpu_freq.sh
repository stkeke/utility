#!/bin/bash

RDMSR_CMD="sudo /usr/sbin/rdmsr"
WRMSR_CMD="sudo /usr/sbin/wrmsr --all"

function _all_cpus()
{
    lscpu | grep "^CPU(s):" | awk '{print $2}'
}

function core_show_freq()
{
    local i="$1"
    if [[ -z "$i" ]]; then
        echo "Use cpu0 as default"
        i=0
    fi
    echo "max=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq)"
    echo "min=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_min_freq)"
}

function core_show_driver()
{
    local i="$1"
    if [[ -z "$i" ]]; then
        echo "Use cpu0 as default"
        i=0
    fi

    cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_driver
}

function core_show_governor()
{
    local i="$1"
    if [[ -z "$i" ]]; then
        echo "Use cpu0 as default"
        i=0
    fi

    cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor
}

function core_show_max_freq()
{
    local i="$1"
    if [[ -z "$i" ]]; then
        echo "Use cpu0 as default"
        i=0
    fi

    cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq
}

function core_show_min_freq()
{
    local i="$1"
    if [[ -z "$i" ]]; then
        echo "Use cpu0 as default"
        i=0
    fi

    cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_min_freq
}

function core_set_fixed_freq()
{
    local ghz="$1" # 900000 means 0.9Ghz 1000000=1Ghz
    local all_cpus=$(_all_cpus)
    local i=0

    for (( i=0; i<$all_cpus; i++ ))
    do
        echo "set cpu$i to $ghz"
        sudo su - -c "echo $ghz >  /sys/devices/system/cpu/cpu$i/cpufreq/scaling_min_freq"
        sudo su - -c "echo $ghz >  /sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq"
    done
}

function uncore_show_freq()
{
    local i="$1"
    if [[ -z "$i" ]]; then
        i=0
    fi

    local freq=$($RDMSR_CMD -0 -p $i 0x620)
    local max=${freq: -2}
    local min=${freq:12:2}

    echo "min=0x$min ($(printf "%d" 0x$min))"
    echo "max=0x$max ($(printf "%d" 0x$max))"
}

function uncore_set_fixed_freq()
{
    local ghz="$1" # 18 (decimal) means 1.8Ghz

    [[ -z "$ghz" ]] && {
        echo "Missed argument for uncore frequency"
        return 1
    }

    if [[ -z "$ORIGINAL_UNCORE_FREQ" ]]; then
        ORIGINAL_UNCORE_FREQ=$($RDMSR_CMD -p 0 0x620)
    fi

    local ghz_hex=$(printf "%02x" $ghz)
    local ghz_wr="0x${ghz_hex}${ghz_hex}"

    echo "uncore frequency set to $ghz_wr"

    $WRMSR_CMD 0x620 $ghz_wr
}

function uncore_restore_freq()
{
    $WRMSR_CMD 0x620 0x$ORIGINAL_UNCORE_FREQ
}
