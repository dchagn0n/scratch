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



# # ================================
# # 3. Main merging logic per type
# # ================================
# for suffix in "${file_suffixes[@]}"; do
#   echo -e "\n🧪 Processing file type: *${suffix}"

#   declare -A groups
#   pattern="scratch/${prefix}/*p${suffix}"
#   files=($pattern)
#   #files=(*"$suffix")

#   if [ ${#files[@]} -eq 0 ]; then
#     echo "  ⚠️ No files found for suffix: $suffix"
#     continue
#   fi

#   # Group files by key
#   for f in "${files[@]}"; do
#     key=$(extract_key "$f")
#     if [[ -z "$key" ]]; then
#       echo "  ⚠️ Could not extract key for file: $f. Skipping."
#       continue
#     fi
#     echo "Debug: extracted key = '$key'"
#     groups["$key"]+="$f "
#   done

#   # Merge each group
#   for key in "${!groups[@]}"; do
#     file_array=(${groups[$key]})
#     total=${#file_array[@]}
#     output_file="scratch/${prefix}/${key}_merge${suffix}"
#     echo "  🔄 Merging group '$key' into file: $output_file"

#     header=$(head -n 1 "${file_array[0]}" | tr -d '\r')
#     echo "${header};source_file" > "$output_file"

#     count=1
#     for f in "${file_array[@]}"; do
#       echo "  • ($count/$total) $f"
#       tail -n +2 "$f" | tr -d '\r' | awk -v fname="$(basename "$f")" -F',' -v OFS=';' '{print $0, fname}' >> "$output_file"
#       ((count++))
#     done
#   done

#   # Clean up group map before next suffix
#   unset groups
# done

# # ================================
# # 3. Main merging logic per type
# # ================================
# for suffix in "${file_suffixes[@]}"; do
#   echo -e "\n🧪 Processing file type: *${suffix}"

#   key=$(extract_key)
#   pattern="scratch/${prefix}/${key}*p${suffix}"
#   files=($pattern)

#   if [ ${#files[@]} -eq 0 ]; then
#     echo "  ⚠️ No files found for suffix: $suffix and key: $key"
#     continue
#   fi

#   output_file="scratch/${prefix}/${key}_merge${suffix}"
#   echo "  🔄 Merging ${#files[@]} file(s) into: $output_file"

#   header=$(head -n 1 "${files[0]}" | tr -d '\r')
#   echo "${header};source_file" > "$output_file"

#   count=1
#   for f in "${files[@]}"; do
#     echo "  • ($count/${#files[@]}) $f"
#     tail -n +2 "$f" | tr -d '\r' | awk -v fname="$(basename "$f")" -F',' -v OFS=';' '{print $0, fname}' >> "$output_file"
#     ((count++))
#   done
# done

# ================================
# 3. Main merging logic per type
# ================================
for suffix in "${file_suffixes[@]}"; do
  echo -e "\n🧪 Processing file type: *${suffix}"

  declare -A groups
  # pattern="scratch/${prefix}/*${suffix}" # 0 ici
  pattern="${repertory}/*${suffix}"
  files=($pattern)
  echo "Debug: found ${#files[@]} files matching pattern '$pattern'"

  if [ ${#files[@]} -eq 0 ]; then
    echo "  ⚠️ No files found for suffix: $suffix"
    continue
  fi

  #key=$(extract_key)
  # Group files by key
  for f in "${files[@]}"; do
    key=$(extract_key "$f")
    if [[ -z "$key" ]]; then
      echo "  ⚠️ Could not extract key for file: $f. Skipping."
      continue
    fi
    echo "Debug: extracted key = '$key'"
    groups["$key"]+="$f "
  done

  # Merge each group
  my_key="T${time}s_L${latency}_B${bandwidth}_Ra${datarateaccess}_P${packetsize}b_Ma${meanA}_Me${meanE}" #_Re${datarateext}
  #for key in "${!groups[@]}"; do
    file_array=(${groups[$my_key]})
    total=${#file_array[@]}
    #output_file="scratch/${prefix}/${my_key}_merge_${name}${suffix}"
    output_file="${repertory}/${my_key}_merge_${name}${suffix}"
    echo "  🔄 Merging group '$my_key' into file: $output_file"

    header=$(head -n 1 "${file_array[0]}" | tr -d '\r')
    if [ ! -f "$output_file" ]; then
      echo "${header};source_file" > "$output_file"
    else
      echo "\n" >> "$output_file"
    fi
    count=1
    for f in "${file_array[@]}"; do
      echo "  • ($count/$total) $f"
      tail -n +2 "$f" | tr -d '\r' | awk -v fname="$(basename "$f")" -F',' -v OFS=';' '{print $0, fname}' >> "$output_file"
      # Delete the file after processing
      #rm "$f"
      ((count++))
    done
  #done

  #sort --unique "$output_file" --output="$output_file"

  # Clean up group map before next suffix
  unset groups
done


echo -e "\n✅ All merging operations complete."


# ###############################################################################
# # Bash script to merge CSV files ending with _trace_all_output_stats.csv
# # and add a source_file column indicating origin

# #output="scratch/${prefix}/merged_trace_all_output_stats.csv"
# pattern="scratch/${prefix}/*_trace_all_output_stats.csv"


# files=($pattern)
# total=${#files[@]}

# # Exit if no files found
# if [ $total -eq 0 ]; then
#   echo "No matching CSV files found."
#   exit 1
# fi




# declare -A groups

# # # Write the header with the additional column
# # first_file="${files[0]}"
# # header=$(head -n 1 "$first_file" | tr -d '\r')
# # echo "${header},source_file" > "$output"


# # Step 1: group files by key
# for f in "${files[@]}"; do
#   key=$(extract_key "$(basename "$f")")
#   if [ -z "$key" ]; then
#     echo "Warning: Could not extract key from filename '$f'. Skipping."
#     continue
#   fi
#   # Replace spaces or problematic chars with underscore
#   #key=$(echo "$key" | tr ' ' '_')
#   echo "Debug: extracted key = '$key'"
#   groups["$key"]+="$f "
# done

# # Step 2: process each group
# for key in "${!groups[@]}"; do
#   out="scratch/${prefix}/${key}_merge_stats.csv"
#   file_array=(${groups[$key]})
#   total=${#file_array[@]}

#   echo "🧪 Merging group: $key → $out"

#   # Write clean header
#   header=$(head -n 1 "${file_array[0]}" | tr -d '\r')
#   echo "${header},source_file" > "$out"

#   count=1
#   for f in "${file_array[@]}"; do
#     echo "  • ($count/$total) $f"
#     tail -n +2 "$f" | tr -d '\r' | awk -v fname="$(basename "$f")" -F',' -v OFS=',' '{print $0, fname}' >> "$out"
#     ((count++))
#   done
# done

# ###############################################################################
