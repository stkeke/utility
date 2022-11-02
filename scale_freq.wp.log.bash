log_dir="scale_freq.wp"

function get_core_freq_range()
{
    local d=""

    for d in "$log_dir"/tony_opt.*
    do
        echo "$(basename $d)" | awk -F. '{print $2}'
    done | sort -n | uniq
}

function get_uncore_freq_range()
{
    local d=""

    for d in "$log_dir"/tony_opt.*
    do
        echo "$(basename $d)" | awk -F. '{print $3}'
    done | sort -n | uniq
}


function filter_emon_metric()
{
    local metric="$1"

    # print metric
    echo "\"$metric\""

    echo "\"**** Opt (JIT Disabled) ****\""
    _filter_sys_view_per_txn "tony_opt" "$metric"
    echo ""
    echo ""

    echo "\"#### OptJIT (JIT Enabled) ####\""
    _filter_sys_view_per_txn "tony_optjit" "$metric"
}

function filter_tps()
{
    # print metric
    echo "TPS"

    echo "\"**** Opt (JIT Disabled) ****\""
    _filter_config "tony_opt"
    echo ""
    echo ""

    echo "\"#### OptJIT (JIT Enabled) ####\""
    _filter_config "tony_optjit"
}

function _filter_config()
{
    local type="$1"

    local core_freq=""
    local uncore_freq=""

    # print table header: core frequency columns
    local core_freq_range=$(get_core_freq_range)
    echo -n "U\\C "
    for core_freq in $core_freq_range; do
    echo -n "$((core_freq/100000)) "
    done
    echo ""

    for uncore_freq in $(get_uncore_freq_range); do
        echo -n "$uncore_freq "
        for core_freq in $core_freq_range; do
            local log_file="$log_dir/${type}.${core_freq}.${uncore_freq}/config"
            echo -n "$(grep "^TotalTPS=" "$log_file" | awk -F= '{print $2}') "
        done # core_freq loop
        echo ""
    done # uncore_freq loop
}

function _filter_sys_view_per_txn()
{
    local type="$1"
    local metric="$2"

    local core_freq=""
    local uncore_freq=""

    # print table header: core frequency columns
    local core_freq_range=$(get_core_freq_range)
    echo -n "U\\C "
    for core_freq in $core_freq_range; do
        echo -n "$((core_freq/100000)) "
    done
    echo ""

    for uncore_freq in $(get_uncore_freq_range); do
        echo -n "$uncore_freq "
        for core_freq in $core_freq_range; do
            local log_file="$log_dir/${type}.${core_freq}.${uncore_freq}/__edp_system_view_summary.per_txn.csv"
            echo -n "$(grep "^$2" "$log_file" | awk -F, '{print $2}') "
        done # core_freq loop
        echo ""
    done # uncore_freq loop
}