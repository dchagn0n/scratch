#!/bin/bash
while getopts f:t:l:b:a:e:o:m:x:n:r: flag
do
    case "${flag}" in
        f) file=${OPTARG};;
        t) simulationtime=${OPTARG};;
        l) latency=${OPTARG};;
        b) bandwidth=${OPTARG};;
        a) datarateaccess=${OPTARG};;
        #e) datarateext=${OPTARG};;
        o) packetsize=${OPTARG};;
        m) meanexp=${OPTARG};;
        x) meanexppara=${OPTARG};;
        n) name=${OPTARG};;
        r) repertory=${OPTARG};;
    esac
done

: ${file:="ninth"}
: ${simulationtime:=5}
: ${latency:="1ms"}
: ${bandwidth:="1000bps"}
: ${datarateaccess:="10bps"}
#: ${datarateext:="10bps"}
: ${packetsize:=12000}
: ${meanexp:=0.5}
: ${meanexppara:=0.5}
: ${name:="total"}
: ${repertory:="${file}"}

time=$(LC_NUMERIC=C printf "%.6f" $simulationtime)
meanA=$(LC_NUMERIC=C printf "%.6f" $meanexp)
meanE=$(LC_NUMERIC=C printf "%.6f" $meanexppara)
# Check if files exist
shopt -s nullglob

# =======================
# 1. Extract key function
# =======================
extract_key() {
  fname="$1"
  basename="$(basename "$fname")"

  T=$(echo "$basename" | sed -n 's/.*\(T[0-9.]\+s\).*/\1/p')
  L=$(echo "$basename" | sed -n 's/.*\(L[0-9]\+ms\).*/\1/p')
  B=$(echo "$basename" | sed -n 's/.*\(B[0-9]\+\(K\|M\|G\)\?bps\).*/\1/p')
  Ra=$(echo "$basename" | sed -n 's/.*\(Ra[0-9]\+\(K\|M\|G\)\?bps\).*/\1/p')
  #Re=$(echo "$basename" | sed -n 's/.*\(Re[0-9]\+\(K\|M\|G\)\?bps\).*/\1/p')
  P=$(echo "$basename" | sed -n 's/.*\(P[0-9]\+b\).*/\1/p')
  Ma=$(echo "$basename" | sed -n 's/.*\(Ma[0-9.]\+\).*/\1/p')
  Me=$(echo "$basename" | sed -n 's/.*\(Me[0-9.]\+\).*/\1/p')
  
  if [[ -n "$T" && -n "$L" && -n "$B" && -n "$Ra" &&  -n "$P" && -n "$Ma" && -n "$Me" ]]; then #-n "$Re" &&
    echo "${T}_${L}_${B}_${Ra}_${P}_${Ma}_${Me}" #_${Re}
  else
    echo "Error: could not extract key from filename '$fname'" >&2
    echo "${T}_${L}_${B}_${Ra}_${P}_${Ma}_${Me}" #_${Re}
  fi
  # echo T${time}s_L${latency}_B${bandwidth}_Ra${datarateaccess}_Re${datarateext}_P${packetsize}b
}

# ================================
# 2. Define file types to process
# ================================
declare -a file_suffixes=(
  "_trace_all_output_stats.csv"
  "_queue.csv"
  "_bandwidth.csv"
)


# ================================
# 3. Main merging logic per type
# ================================

matches_part() {
  local fname="$(basename "$1")"
  local part="$2"
  local re="_Re120Mbps"

  if [[ "$part" == "merge_path_part" ]]; then
    [[ "$fname" == *"_a0_"* ]] && [[ "$fname" == *"${re}"* ]]
  elif [[ "$part" == "merge_detour_part" ]]; then
    [[ "$fname" == *"_h0_"* ]] && [[ "$fname" == *"${re}"* ]]
  elif [[ "$part" == "merge_parasite_part" ]]; then
    [[ "$fname" == *"_h0_"* ]] && [[ "$fname" == *"_a0_"* ]]
  else
    return 1
  fi
}

declare -a part_order=("merge_path_part" "merge_detour_part" "merge_parasite_part")

for suffix in "${file_suffixes[@]}"; do
  echo -e "\n🧪 Processing file type: *${suffix}"

  pattern="${repertory}/*${suffix}"
  all_files=($pattern)
  echo "Debug: found ${#all_files[@]} files matching pattern '$pattern'"

  if [ ${#all_files[@]} -eq 0 ]; then
    echo "  ⚠️ No files found for suffix: $suffix"
    continue
  fi

  for part_name in "${part_order[@]}"; do
    declare -A groups

    for f in "${all_files[@]}"; do
      matches_part "$f" "$part_name" || continue

      key=$(extract_key "$f")
      if [[ -z "$key" ]]; then
        echo "  ⚠️ Could not extract key for file: $f. Skipping."
        continue
      fi
      echo "Debug [$part_name]: extracted key = '$key'"
      groups["$key"]+="$f "
    done

    my_key="T${time}s_L${latency}_B${bandwidth}_Ra${datarateaccess}_P${packetsize}b_Ma${meanA}_Me${meanE}"
    file_array=(${groups[$my_key]})
    total=${#file_array[@]}

    if [ $total -eq 0 ]; then
      echo "  ⚠️ No files matched key '$my_key' for part '$part_name'"
      unset groups
      continue
    fi

    output_file="${repertory}/${my_key}_${part_name}_${name}${suffix}"
    echo "  🔄 [$part_name] Merging $total file(s) into: $output_file"

    header=$(head -n 1 "${file_array[0]}" | tr -d '\r')
    if [ ! -f "$output_file" ]; then
      echo "${header};source_file" > "$output_file"
    else
      echo "" >> "$output_file"
    fi

    count=1
    for f in "${file_array[@]}"; do
      echo "  • ($count/$total) $f"
      tail -n +2 "$f" | tr -d '\r' | awk -v fname="$(basename "$f")" -F',' -v OFS=';' '{print $0, fname}' >> "$output_file"
      ((count++))
    done

    unset groups
  done
done

echo -e "\n✅ All merging operations complete."