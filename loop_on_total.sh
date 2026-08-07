#!/bin/bash
set -euxo pipefail
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
#        d) detour=${OPTARG};;
    esac
done

: ${file:="ninth"}
: ${simulationtime:=30}
: ${latency:="10ms"}
: ${bandwidth:="1000bps"}
: ${datarateaccess:="10bps"}
: ${datarateext:="10bps"}
: ${packetsize:=12000}
#: ${detour:=0}
: ${meanexp:=0.5}
: ${meanexppara:=0.5}

time=$(LC_NUMERIC=C printf "%.6f" $simulationtime)
meanA=$(LC_NUMERIC=C printf "%.6f" $meanexp)
meanE=$(LC_NUMERIC=C printf "%.6f" $meanexppara)
unit=$(echo "$datarateext" | sed -n 's/^[0-9.]\+\(.*\)$/\1/p')
number_bandwidth=$(echo "$bandwidth" | sed -n 's/^\([0-9.]\+\).*/\1/p')
number_bdw=$(echo "$number_bandwidth * 2" | bc)
number_bdw_plus_half=$(echo "$number_bandwidth * 1.25" | bc| cut -d'.' -f1)
half_number_bdw=$(echo "$number_bandwidth * 0.5" | bc| cut -d'.' -f1)
echo "number_bdw: $number_bdw"
echo "number_bdw_plus_half: $number_bdw_plus_half"
echo "half_number_bdw: $half_number_bdw"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/bash_function.sh"


./ns3 clean
./ns3 configure --enable-examples --enable-tests
./ns3 build



current_jobs=0




for intermediate in {0..10}; #0..10
do
    for detour in {0..10}; 
    do
        # for rateaccess in {10..1000..10}; 
        # do
        #     datarateaccess=$(printf "%dMbps" $rateaccess)
        #for ((rateext=1; rateext<=number_bdw; rateext+=10)); do

        bdw=$(( number_bdw / (detour + 1) ))
        #vals=(1 $(( bdw * 25 / 100 )) $(( bdw * 50 / 100 )) $(( bdw * 75 / 100 )) $bdw)
        vals=(1 $(( bdw * 10 / 100 ))  $(( bdw * 30 / 100 ))  $(( bdw * 50 / 100 ))  $(( bdw * 70 / 100 )) $bdw $(( number_bdw * 10 / 100 )) $(( number_bdw * 20 / 100 )) $(( number_bdw * 30 / 100 )) $(( number_bdw * 40 / 100 )) $(( number_bdw * 50 / 100 )) $(( number_bdw * 60 / 100 )) $(( number_bdw * 70 / 100 )) $(( number_bdw * 80 / 100 )) $(( number_bdw * 90 / 100 )) $number_bdw )
        

        for ((i=half_number_bdw; i<=number_bdw_plus_half; i+=10)); do
          vals+=("$i")
        done

        rounded_vals=()
        for v in "${vals[@]}"; do
          rounded=$(round_to_10 "$v")
          rounded_vals+=("$rounded")
        done

        rounded_vals+=(1)  # Start with 1
        rounded_vals+=(10)

        # Suppression des doublons et des zéros
        #declare -a seen
        uniq_vals=()
        seen=()

        for v in "${rounded_vals[@]}"; do
          if [[ $v -gt 0 && ! " ${seen[*]} " =~ " $v " ]]; then #if [[ $v -gt 0 && -z "${seen[$v]}" ]]; then #
            uniq_vals+=($v) # uniq_vals+=("$v") #
            seen+=($v) #seen[$v]=1 #
          fi
        done
        # Optionnel : Tri croissant (nécessite une commande externe)
        IFS=$'\n' sorted_vals=($(sort -n <<<"${uniq_vals[*]}"))
        unset IFS

        for rateext in "${sorted_vals[@]}"; do

                datarateext="${rateext}${unit}"
                echo "Running with : $datarateext"
                prefixUDP="scratch/${file}/T${time}s_h${intermediate}_a${detour}_L${latency}_B${bandwidth}_Ra${datarateaccess}_Re${datarateext}_P${packetsize}b_Udp_Ma${meanA}_Me${meanE}_"

                # prefixTcp="scratch/${file}/T${time}s_h${intermediate}_a${detour}_L${latency}_B${bandwidth}_Ra${datarateaccess}_Re${datarateext}_P${packetsize}b_Tcp_Ma${meanA}_Me${meanE}_"
                
                check_mem

                echo "Running with : $prefixUDP"
                bash ./scratch/execute.sh -f $file -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -p Udp   -i $intermediate -d $detour -m $meanexp -x $meanexppara > ${prefixUDP}output.log # &
                
                
                # ((current_jobs++))
                # if [[ $current_jobs -ge $max_jobs ]]; then
                #     echo "🛑 Too many jobs: ${current_jobs}. Waiting..."
                #     wait -n  # Wait for at least one job to finish
                #     ((current_jobs--))
                # fi

                # check_mem
                # echo "Running with : $prefixTcp"
                # bash ./scratch/execute.sh -f $file -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -p Tcp   -i $intermediate -d $detour -m $meanexp -x $meanexppara > ${prefixTcp}output.log  &
                
                # pids+=($!)
                
                # ((current_jobs++))
                # if [[ $current_jobs -ge $max_jobs ]]; then
                #     echo "🛑 Too many jobs: ${current_jobs}. Waiting..."
                #     wait -n  # Wait for at least one job to finish
                #     ((current_jobs--))
                # fi
              
        done
        # done
    done
done

echo "All jobs completed. Waiting for remaining processes to finish..."


wait



echo "done loop NS3"
                
bash ./scratch/merge_file_ns3.sh -f $file -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -o $packetsize -m $meanexp -x $meanexppara -n total #-e $datarateext 

echo "done merging NS3 files"
Rscript ./scratch/ninth/generation.R -f $file -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess  -o $packetsize -m $meanexp -x $meanexppara  -n total #-e $datarateext
echo "done analyzing packets"


Rscript ./scratch/merge_file.R
echo "done merging R files"