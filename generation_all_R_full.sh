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
: ${trainondetour:=0}
: ${trainonpath:=0}
: ${comment:=""}
: ${dographs:=TRUE}

# --- Base directories ---
BASE_DIR="$(pwd)"                  # typically ns-3.45
SCRATCH_DIR="$BASE_DIR/scratch"
#NINTH_DIR="$SCRATCH_DIR/ninth"

# Liste des niveaux à parcourir
LEVELS=("ninth" "tenth")
COMMENTS=("basic") # "same_size_dataset")

# --- Parameters ---
MAX_JOBS=1                         # Max concurrent processes
LOG_FILE="$SCRATCH_DIR/processed_dirs__parasite${trainonparasite}_path${trainonpath}_dograph${dographs}.txt"   # List of processed directories

# --- Optional argument: single directory ---
DATA_DIR_ARG="$1"

# --- Function to generate R commands ---
generate_commands() {
    local dir="$1"

    for COMMENT in "${COMMENTS[@]}"; do

        #Figure 3.21
        echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e FALSE -i $trainonparasite -d 0 -p $trainonpath -c $COMMENT -g $dographs " 
        #Figure 3.17
        echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path -e FALSE -i $trainonparasite -d 0 -p $trainonpath -c $COMMENT -g $dographs "
        # Figure 3.11
        echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite -e FALSE -i $trainonparasite -d 0 -p $trainonpath -c $COMMENT -g $dographs "

        echo "Rscript scratch/ninth/generation_ondetour_evolution.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e TRUE -i $trainonparasite -d 0_1_3_5_7_9 -p $trainonpath -c $COMMENT -g $dographs "



        echo "Rscript scratch/ninth/generation_ondetour.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e FALSE -i $trainonparasite -d 0_1_3_5_7_9 -p $trainonpath -c $COMMENT -g $dographs "
        echo "Rscript scratch/ninth/generation_ondetour.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path -e FALSE -i $trainonparasite -d 0_1_3_5_7_9 -p $trainonpath -c $COMMENT -g $dographs "
        echo "Rscript scratch/ninth/generation_ondetour.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite -e FALSE -i $trainonparasite -d 0_1_3_5_7_9 -p $trainonpath -c $COMMENT -g $dographs "


        echo "Rscript scratch/ninth/generation_ondetour_evolution.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e TRUE -i $trainonparasite -d 0 -p $trainonpath -c $COMMENT -g $dographs "

        echo "Rscript scratch/ninth/generation_ondetour_evolution.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e TRUE -i $trainonparasite -d 5 -p $trainonpath -c $COMMENT -g $dographs "

        # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e FALSE -i $trainonparasite -d 5 -p $trainonpath -c $COMMENT -g $dographs " 
        # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path -e FALSE -i $trainonparasite -d 5 -p $trainonpath -c $COMMENT -g $dographs "
        # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite -e FALSE -i $trainonparasite -d 5 -p $trainonpath -c $COMMENT -g $dographs "
        

        # echo "Rscript scratch/ninth/generation_ondetour_evolution.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e FALSE -i $trainonparasite -d 0_1_3_5_7_9 -p $trainonpath -c $COMMENT -g $dographs "

        # echo "Rscript scratch/ninth/generation_ondetour.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e TRUE -i $trainonparasite -d 0_1_3_5_7_9 -p $trainonpath -c $COMMENT -g $dographs "
        # echo "Rscript scratch/ninth/generation_ondetour.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path -e TRUE -i $trainonparasite -d 0_1_3_5_7_9 -p $trainonpath -c $COMMENT -g $dographs "
        # echo "Rscript scratch/ninth/generation_ondetour.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite -e TRUE -i $trainonparasite -d 0_1_3_5_7_9 -p $trainonpath -c $COMMENT -g $dographs "


        # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e TRUE -i $trainonparasite -d 0 -p $trainonpath -c $COMMENT -g $dographs " 
        # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path -e TRUE -i $trainonparasite -d 0 -p $trainonpath -c $COMMENT -g $dographs "
        # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite -e TRUE -i $trainonparasite -d 0 -p $trainonpath -c $COMMENT -g $dographs "

        # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e TRUE -i $trainonparasite -d 5 -p $trainonpath -c $COMMENT -g $dographs " 
        # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path -e TRUE -i $trainonparasite -d 5 -p $trainonpath -c $COMMENT -g $dographs "
        # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite -e TRUE -i $trainonparasite -d 5 -p $trainonpath -c $COMMENT -g $dographs "




    # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e $do_evolution -i $trainonparasite -d $trainondetour -p $trainonpath -c $comment -g $dographs" 
    # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path -e $do_evolution -i $trainonparasite -d $trainondetour -p $trainonpath -c $comment -g $dographs"
    # echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite -e $do_evolution -i $trainonparasite -d $trainondetour -p $trainonpath -c $comment -g $dographs"


    done


}


# Générer toutes les commandes de tous les répertoires d'un coup
generate_all_commands() {
    # for LEVEL in "${LEVELS[@]}"; do
    #     LEVEL_DIR="$SCRATCH_DIR/$LEVEL"
    #     [[ ! -d "$LEVEL_DIR" ]] && continue

    #     find "$LEVEL_DIR" -maxdepth 1 -type d -regex ".*/\(2025\|2026\)-.*" | while read dir; do
    #         # Vérifications
    #         if grep -qxF "$dir" "$LOG_FILE" 2>/dev/null; then
    #             continue
    #         fi
    #         local file_count
    #         file_count=$(find "$dir" -maxdepth 1 -type f -name "T60.000000s_L5ms*" | wc -l)
    #         if (( file_count != 1 )); then
    #             continue
    #         fi

    #         generate_commands "$dir"
    #     done
    # done
    # Construire les deux listes de répertoires
    local dirs_ninth=()
    local dirs_tenth=()

    while IFS= read -r dir; do
        dirs_ninth+=("$dir")
    done < <(find "$SCRATCH_DIR/ninth" -maxdepth 1 -type d -regex ".*/\(2025\|2026\)-.*" 2>/dev/null)

    while IFS= read -r dir; do
        dirs_tenth+=("$dir")
    done < <(find "$SCRATCH_DIR/tenth" -maxdepth 1 -type d -regex ".*/\(2025\|2026\)-.*" 2>/dev/null)

    # Alterner ninth / tenth
    local max=$(( ${#dirs_ninth[@]} > ${#dirs_tenth[@]} ? ${#dirs_ninth[@]} : ${#dirs_tenth[@]} ))

    for (( i=0; i<max; i++ )); do
        if (( i < ${#dirs_ninth[@]} )); then
            local dir="${dirs_ninth[$i]}"
            local file_count
            file_count=$(find "$dir" -maxdepth 1 -type f -name "T60.000000s_L5ms*" | wc -l)
            if ! grep -qxF "$dir" "$LOG_FILE" 2>/dev/null && (( file_count == 1 )); then
                printf "%s\n" "$dir" >> "$LOG_FILE"   # <--- log ici
                generate_commands "$dir"
            fi
        fi
        if (( i < ${#dirs_tenth[@]} )); then
            local dir="${dirs_tenth[$i]}"
            local file_count
            file_count=$(find "$dir" -maxdepth 1 -type f -name "T60.000000s_L5ms*" | wc -l)
            if ! grep -qxF "$dir" "$LOG_FILE" 2>/dev/null && (( file_count == 1 )); then
                printf "%s\n" "$dir" >> "$LOG_FILE"   # <--- log ici
                generate_commands "$dir"
            fi
        fi
    done
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

    ## ESSAIE ICI 20260331
    #generate_commands "$dir" | xargs -I CMD -P 15 bash -c "CMD"
    while IFS= read -r cmd; do
        # Attendre que la RAM disponible soit suffisante (ici seuil : 2 Go)
        while (( $(free -m | awk '/^Mem:/{print $7}') < 40000 )); do
            sleep 5
        done


        bash -c "$cmd" &
        while (( $(jobs -rp | wc -l) >= 12 )); do
            wait -n 2>/dev/null || sleep 0.5
        done
    done < <(generate_all_commands "$dir")
    wait

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

    # for LEVEL in "${LEVELS[@]}"; do
    #     LEVEL_DIR="$SCRATCH_DIR/$LEVEL"


    #     # Vérifier que le répertoire existe
    #     if [[ ! -d "$LEVEL_DIR" ]]; then
    #         echo "⚠️  Répertoire absent : $LEVEL_DIR (ignoré)"
    #         continue
    #     fi


    #     # Process all directories concurrently
    #     printf "=== Scanning %s for subdirectories ===\n" "$LEVEL_DIR"

    #     find "$LEVEL_DIR" -maxdepth 1 -type d -regex ".*/\(2025\|2026\)-.*" | while read dir; do
    #         # Launch each directory in background, respecting MAX_JOBS
    #         while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
    #             sleep 5
    #         done

    #         process_directory "$dir" &
    #     done
    # done
    # Boucle principale
    while IFS= read -r cmd; do
        while (( $(free -m | awk '/^Mem:/{print $7}') < 40000 )); do
            sleep 5
        done

        bash -c "$cmd" &

        while (( $(jobs -rp | wc -l) >= 5 )); do
            wait -n 2>/dev/null || sleep 0.5
        done
    done < <(generate_all_commands)

    # Wait for all background jobs
    wait
fi

printf "\n=== All executions completed. ===\n"
