#!/bin/bash
# ============================================================
# Automated R generation for NS-3 experiment directories
# Author: [you]
# ============================================================

while getopts e:i:d:p:c:g: flag
do
    case "${flag}" in
        e) do_evolution=${OPTARG};;
        i) trainonparasite=${OPTARG};;
        d) trainondetour=${OPTARG};;
        p) trainonpath=${OPTARG};;
        c) comment=${OPTARG};;
        g) dographs=${OPTARG};;
    esac
done
shift $((OPTIND - 1)) 

: ${do_evolution:=FALSE}
: ${trainonparasite:="60Mbps"}
: ${trainondetour:="0_1_3_5_7_9"}
: ${trainonpath:=0}
: ${comment:=""}
: ${dographs:=TRUE}

# --- Base directories ---
BASE_DIR="$(pwd)"                  # typically ns-3.45
SCRATCH_DIR="$BASE_DIR/scratch"
#NINTH_DIR="$SCRATCH_DIR/ninth"

# Liste des niveaux à parcourir
LEVELS=("ninth" "tenth")

# --- Parameters ---
MAX_JOBS=1                         # Max concurrent processes
LOG_FILE="$SCRATCH_DIR/processed_dirs_evolution${do_evolution}_detour${trainondetour}_parasite${trainonparasite}_path${trainonpath}_${comment}_dograph${dographs}.txt"   # List of processed directories

# --- Optional argument: single directory ---
DATA_DIR_ARG="$1"

# --- Function to generate R commands ---
generate_commands() {
    local dir="$1"
    echo "Rscript scratch/ninth/generation_ondetour_evolution.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e $do_evolution -i $trainonparasite -d $trainondetour -p $trainonpath -c $comment -g $dographs"
    #echo "Rscript scratch/ninth/generation_ondetour_evolution.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path" -e "$do_evolution" -i "$trainonparasite" -d "$trainondetour" -p "$trainonpath"
    #echo "Rscript scratch/ninth/generation_ondetour_evolution.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite" -e "$do_evolution" -i "$trainonparasite" -d "$trainondetour" -p "$trainonpath"
}

# --- Function to process a single directory ---
process_directory() {
    local dir="$1"

    printf "\n=== [%s] Processing: %s ===\n" "$(date '+%H:%M:%S')" "$dir"

    # Check if directory was already processed
    if grep -qxF "$dir" "$LOG_FILE" 2>/dev/null; then
        printf "[INFO] Skipping already processed: %s\n" "$dir"
        return
    fi

    # Check number of files
    local file_count
    file_count=$(find "$dir" -maxdepth 1 -type f -name "T60.000000s_L5ms*" | wc -l)

    if (( file_count != 1 )); then
        printf "[WARN] %s has %d files (expected 3). Running merge/copy scripts...\n" "$dir" "$file_count"
        #bash scratch/merge_all_ns3.sh
        #bash scratch/copy_all.sh
        return
    fi

    # Run Rscript commands in parallel for this directory
    printf "[INFO] Starting R scripts for %s\n" "$dir"
    printf "%s\n" "$dir" >> "$LOG_FILE"
    generate_commands "$dir" | xargs -I CMD -P 3 bash -c "CMD"

    # Mark as processed
    
    printf "[OK] Completed: %s\n" "$dir"
}

# ============================================================
# --- Main Execution ---
# ============================================================

# Create log file if missing
touch "$LOG_FILE"

if [[ -n "$DATA_DIR_ARG" ]]; then
    # Process only one directory (if provided)
    if [[ -d "$DATA_DIR_ARG" ]]; then
        process_directory "$DATA_DIR_ARG"
    else
        printf "[ERROR] Directory '%s' not found.\n" "$DATA_DIR_ARG" >&2
        exit 1
    fi
else

for LEVEL in "${LEVELS[@]}"; do
        LEVEL_DIR="$SCRATCH_DIR/$LEVEL"


        # Vérifier que le répertoire existe
        if [[ ! -d "$LEVEL_DIR" ]]; then
            echo "⚠️  Répertoire absent : $LEVEL_DIR (ignoré)"
            continue
        fi
    # Process all directories concurrently
    printf "=== Scanning %s for subdirectories ===\n" "$LEVEL_DIR"

find "$LEVEL_DIR" -maxdepth 1 -type d -regex ".*/\(2025\|2026\)-.*" | while read dir; do
        # Launch each directory in background, respecting MAX_JOBS
        while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
            sleep 5
        done

        process_directory "$dir" &
    done
    done

    # Wait for all background jobs
    wait
fi

printf "\n=== All executions completed. ===\n"

