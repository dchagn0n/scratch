#!/bin/bash
set -euxo pipefail

echo "[$(date)] PID $$ STARTED with args: $@" >> /tmp/exec_log.txt

while getopts f:t:l:b:a:e:o:p:i:d:m:x:r: flag
do
    case "${flag}" in
        f) file=${OPTARG};;
        t) simulationtime=${OPTARG};;
        l) latency=${OPTARG};;
        b) bandwidth=${OPTARG};;
        a) datarateaccess=${OPTARG};;
        e) datarateext=${OPTARG};;
        o) packetsize=${OPTARG};;
        p) protocol=${OPTARG};;
        i) intermediate=${OPTARG};;
        d) detour=${OPTARG};;
        m) meanexp=${OPTARG};;
        x) meanexppara=${OPTARG};;
        r) repertory=${OPTARG};;
    esac
done

: ${file:="ninth"}
: ${simulationtime:=60}
: ${latency:="5ms"}
: ${bandwidth:="120Mbps"}
: ${datarateaccess:="10Mbps"}
: ${datarateext:="60Mbps"}
: ${packetsize:=12000}
: ${protocol:="Udp"}
: ${intermediate:=0}
: ${detour:=0}
: ${meanexp:=0.5}
: ${meanexppara:=0.5}
: ${repertory:="${file}"}

time=$(LC_NUMERIC=C printf "%.6f" $simulationtime)
meanA=$(LC_NUMERIC=C printf "%.6f" $meanexp)
meanE=$(LC_NUMERIC=C printf "%.6f" $meanexppara)

source ./scratch/bash_function.sh

prefix="${repertory}/T${time}s_h${intermediate}_a${detour}_L${latency}_B${bandwidth}_Ra${datarateaccess}_Re${datarateext}_P${packetsize}b_${protocol}_Ma${meanA}_Me${meanE}_"


rm -f ${prefix}*.csv ${prefix}*.tr ${prefix}*.pcap ${prefix}*.txt 

EXCLUDED=("tenth" "twelveth")
# Fonction réutilisable
is_excluded() {
    local val="$1"
    for excl in "${EXCLUDED[@]}"; do
        [[ "$val" == "$excl" ]] && return 0
    done
    return 1
}

./ns3
./ns3 run "scratch/$file/$file.cc --repertory=$repertory --simulationTime=$simulationtime --latency=$latency --bandwidth=$bandwidth --dataRateAccess=$datarateaccess --dataRateExt=$datarateext --packetSize=$packetsize --transportProt=$protocol --numExtraRouters=$intermediate --numExtraDetour=$detour --meanExpo=$meanexp --meanExpoPara=$meanexppara"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/bash_function.sh"

check_mem
python3 scratch/read_pcap.py -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -p $protocol -i $intermediate -d $detour -m $meanexp -x $meanexppara

rm ${prefix}*.pcap

# check_mem
# python3 scratch/calculate_bandwidth.py -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -p $protocol -i $intermediate -d $detour -m $meanexp -x $meanexppara

# check_mem
# python3 scratch/calculate_queue.py -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -p $protocol -i $intermediate -d $detour -m $meanexp -x $meanexppara

rm ${prefix}*.tr

#if [ "$file" == "tenth" ]; then
if is_excluded "$file"; then
python3 scratch/plot_parasiterate.py -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -p $protocol -i $intermediate -d $detour -m $meanexp -x $meanexppara
fi

echo "[$(date)] PID $$ FINISHED" >> /tmp/exec_log.txt