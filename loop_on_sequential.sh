#!/bin/bash
# set -euxo pipefail
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


time=$(LC_NUMERIC=C printf "%.6f" $simulationtime)
meanA=$(LC_NUMERIC=C printf "%.6f" $meanexp)
meanE=$(LC_NUMERIC=C printf "%.6f" $meanexppara)
unit=$(echo "$datarateext" | sed -n 's/^[0-9.]\+\(.*\)$/\1/p')
number_bandwidth=$(echo "$bandwidth" | sed -n 's/^\([0-9.]\+\).*/\1/p')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/bash_function.sh"

current_date="$(date +"%Y-%m-%d_%H-%M-%S")"
repertory="scratch/${file}/${current_date}"
mkdir -p "${repertory}" || exit 1
echo "Created: ${repertory}"

prefix="${repertory}/T${time}s_h"

EXCLUDED=("tenth" "twelveth")

# Fonction réutilisable
is_excluded() {
    local val="$1"
    for excl in "${EXCLUDED[@]}"; do
        [[ "$val" == "$excl" ]] && return 0
    done
    return 1
}


# if [ "$file" != "tenth" ]; then
if ! is_excluded "$file"; then

bash scratch/loop_on_parasiterate.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_parasiterate2.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_parasiterate3.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_parasiterate4.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_parasiterate5.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_parasiterate6.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_parasiterate7.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_parasiterate8.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_parasiterate9.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

fi

bash scratch/loop_on_path4.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_path5.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_path6.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_detour2.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml



# if [ "$file" != "tenth" ]; then
if ! is_excluded "$file"; then

bash scratch/loop_on_detour.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_path.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_path2.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

bash scratch/loop_on_path3.sh -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -m $meanexp -x $meanexppara
rm -f "${prefix}"*.log "${prefix}"*.tr "${prefix}"*.pcap "${prefix}"*.txt "${prefix}"*.xml

fi

