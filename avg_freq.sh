#!/bin/bash

echo "tony_opt"
for cpu_count in $(seq -s ' '  1 2 40)
do
        file="tony_opt_${cpu_count}.freq.csv"
        echo "$cpu_count $(awk -F, '{print $2}' $file | tr '\n' ' ')"
done


echo "tony_optjit"
for cpu_count in $(seq -s ' '  1 2 40)
do
        file="tony_optjit_${cpu_count}.freq.csv"
        echo "$cpu_count $(awk -F, '{print $2}' $file | tr '\n' ' ')"
done

