#!/bin/bash
while getopts f:t:l:b:a:e:o:m:x: flag
do
    case "${flag}" in
        f) file=${OPTARG};;
        t) simulationtime=${OPTARG};;
        l) latency=${OPTARG};;
        b) bandwidth=${OPTARG};;
        a) datarateaccess=${OPTARG};;
        e) datarateext=${OPTARG};;
        o) packetsize=${OPTARG};;
        m) meanexp=${OPTARG};;
        x) meanexppara=${OPTARG};;
    esac
done

: ${file:="ninth"}
: ${simulationtime:=60}
: ${latency:="5ms"}
: ${bandwidth:="120Mbps"}
: ${datarateaccess:="10Mbps"}
: ${datarateext:="60Mbps"}
: ${packetsize:=12000}
: ${meanexp:=0.5}
: ${meanexppara:=0.5}


for ((i=1; i<=60; i++)); do
    echo "Iteration $i: Generating dataset..."
    bash scratch/loop_on_sequential.sh -f $file -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
done