#!/bin/bash
# ============================================================
# Automated R generation for NS-3 experiment directories
# Author: [you]
# ============================================================
while getopts f:n: flag
do
    case "${flag}" in
        f) COMMANDS=${OPTARG};;
        n) MAX_JOBS=${OPTARG};;
    esac
done

: ${COMMANDS:="commande.txt"}
: ${MAX_JOBS:=2}

# --- Base directories ---
BASE_DIR="$(pwd)"                  # typically ns-3.45
SCRATCH_DIR="$BASE_DIR/scratch"
#NINTH_DIR="$SCRATCH_DIR/ninth"

# Liste des niveaux à parcourir
LEVELS=("ninth" "tenth")
COMMENTS=("basic") # "same_size_dataset")

# --- Parameters ---
#MAX_JOBS=2 #9 #1                        # Max concurrent Rscript processes
MIN_FREE_RAM_MB=40000             # Minimum free RAM (MB) before launching a new job

LOG_FILE_ERROR="$SCRATCH_DIR/processed_dirs_error.txt"
LOG_FILE_END="$SCRATCH_DIR/processed_dirs_end.txt"


# --- Command file ---
COMMANDS_FILE="$COMMANDS"




#  ============================================================
# --- Helper: wait until RAM and job slots are available ---
# ============================================================
wait_for_slot() {
    while true; do
        local free_ram running_jobs
        free_ram=$(free -m | awk '/^Mem:/{print $7}')
        running_jobs=$(jobs -rp | wc -l)

        if (( free_ram >= MIN_FREE_RAM_MB && running_jobs < MAX_JOBS )); then
            break
        fi

        # Report why we're waiting
        if (( free_ram < MIN_FREE_RAM_MB )); then
            echo "[WAIT] RAM too low: ${free_ram}MB free (need ${MIN_FREE_RAM_MB}MB)"
        else
            echo "[WAIT] Too many jobs: ${running_jobs} running (max ${MAX_JOBS})"
        fi
        sleep 5
    done
}


#  ============================================================
# --- Wrapper: run one command and log its dataset on completion ---
# ============================================================
run_and_log() {
    local cmd="$1"

    # Extract the dataset path from the -r argument
    local dataset
    dataset=$(echo "$cmd" | grep -oP '(?<=-r )\S+')

    local error_msg
    #error_msg=$(bash -c "$cmd" 2>&1)
    error_msg=$(eval "$cmd" 2>&1)
    local status=$?

    if (( status == 0 )); then
        {
            echo "=============================================="
            echo "[END] $(date '+%Y-%m-%d %H:%M:%S') exit=$status"
            echo "[DATASET] $dataset"
            echo "[CMD] $cmd"
            echo ""
        } >> "$LOG_FILE_END"
    else
        {
            echo "=============================================="
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') exit=$status"
            echo "[DATASET] $dataset"
            echo "[CMD] $cmd"
            echo "[OUTPUT]"
            echo "$output"
            echo ""
        } >> "$LOG_FILE_ERROR"
    fi
}
export -f run_and_log
export LOG_FILE_END
export LOG_FILE_ERROR

# ============================================================
# --- Main Execution ---
# ============================================================

# Create log file if missing
touch "$LOG_FILE_ERROR"
touch "$LOG_FILE_END"

# Check that the command file exists
if [[ ! -f "$COMMANDS_FILE" ]]; then
    echo "[ERROR] Command file not found: $COMMANDS_FILE"
    exit 1
fi
echo "=== Starting generation pipeline ==="
echo "    MAX_JOBS      = $MAX_JOBS"
echo "    MIN_FREE_RAM  = ${MIN_FREE_RAM_MB}MB"
echo "    COMMANDS      = $COMMANDS_FILE ($(grep -c '.' "$COMMANDS_FILE") lines)"
echo ""



# Boucle principale
while IFS= read -r cmd; do
    # Skip empty lines and comment lines
    [[ -z "$cmd" || "$cmd" == \#* ]] && continue

    wait_for_slot

    echo "[RUN] $(date '+%H:%M:%S') $cmd"
    run_and_log "$cmd" &

done < "$COMMANDS_FILE"

# Wait for all background jobs
wait

echo ""
echo "=== All executions completed. ==="
