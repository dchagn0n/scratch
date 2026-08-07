#!/bin/bash

# This script lives in ns-3.45/scratch but is executed from ns-3.45
BASE_DIR="$(pwd)"                      # ns-3.45
SCRATCH_DIR="$BASE_DIR/scratch"
NINTH_DIR="$SCRATCH_DIR"/{ninth,tenth}
# Pattern des répertoires datés
candidates=("$SCRATCH_DIR"/{ninth,tenth}/{2025-*,2026-*})


# Activer nullglob pour éviter que le pattern non trouvé ne reste littéral
shopt -s nullglob


# Construire la liste des répertoires existants
dirs=()
for d in "${candidates[@]}"; do
  [[ -d "$d" ]] && dirs+=("$d")
done

if (( ${#dirs[@]} == 0 )); then
  echo "Aucun répertoire daté trouvé sous scratch/{ninth,tenth}/{2025-*,2026-*}."
  exit 0
fi



# Construire une liste des noms de répertoires (dates) -> chemins correspondants
# On peut avoir plusieurs chemins pour la même date (ex: ninth/2026-01-19_12-00-00 et tenth/2026-01-19_12-00-00)
declare -A date_to_paths
dates=()

for fullpath in "${dirs[@]}"; do
  date_name="$(basename "$fullpath")"  # ex: 2026-01-19_12-00-00
  # Enregistrer la date si première fois
  if [[ -z "${date_to_paths[$date_name]+x}" ]]; then
    dates+=( "$date_name" )
    date_to_paths["$date_name"]="$fullpath"
  else
    # Concaténer avec un séparateur NUL (ou une nouvelle ligne). Ici, on utilise un caractère spécial \n géré plus bas.
    date_to_paths["$date_name"]+=$'\n'"$fullpath"
  fi
done

# Trier les dates lexicographiquement (format YYYY-MM-DD_HH-MM-SS => compatible)
IFS=$'\n' read -r -d '' -a sorted_dates < <(printf '%s\n' "${dates[@]}" | sort && printf '\0')
unset IFS




# # Trier les répertoires (ordre naturel) et exclure le plus récent
# # Remarque: si tes noms sont du type YYYY-MM-DD[_HHMMSS], un tri lexicographique convient.
# IFS=$'\n' sorted=($(printf '%s\n' "${dirs[@]}" | sort -V))
# unset IFS

latest_date="${sorted_dates[-1]}"
echo "Répertoire le plus récent (ignoré) : $latest_date"
echo



# Lister tous les chemins ayant cette date (possiblement plusieurs, sous ninth et/ou tenth)
latest_paths=()
if [[ -n "${date_to_paths[$latest_date]:-}" ]]; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && latest_paths+=( "$p" )
  done <<< "${date_to_paths[$latest_date]}"
fi
for p in "${latest_paths[@]}"; do
  echo "→ Ignoré: $p"
done
echo


# Boucler sur tous sauf le dernier
for date_name in "${sorted_dates[@]:0:${#sorted_dates[@]}}"; do # -1


  while IFS= read -r DATA_DIR; do
      [[ -z "$DATA_DIR" ]] && continue

    echo "Processing directory: $DATA_DIR"
    if [ -d "$DATA_DIR" ]; then
            echo "=== Checking data directory: $(basename "$DATA_DIR") ==="

            # Count CSV files in the directory
            TOTAL_FILES=$(find "$DATA_DIR" -maxdepth 1 -type f | wc -l)
            CSV_COUNT=$(find "$DATA_DIR" -maxdepth 1 -type f -name "*.csv" | wc -l)

            # if [ "$CSV_COUNT" -eq 260 ]; then
            # if [ "$TOTAL_FILES" -eq "$CSV_COUNT" ]; then
                echo "Found $CSV_COUNT CSV files. Running first program..."
                bash scratch/merge_file_ns3.sh -t 60 -r "$DATA_DIR" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path &
            # else
            #     echo "Skipping directory $(basename "$DATA_DIR") — found $CSV_COUNT CSV files."
            # fi
            echo "Completed directory: $(basename "$DATA_DIR")"
            echo
    fi

    # if [ -d "$DATA_DIR" ]; then
    #     echo "=== Processing data directory: $(basename "$DATA_DIR") ==="

    #     # Run the first program
    #     echo "Running first program..."
    #     bash scratch/merge_file_ns3.sh -t 60 -r $DATA_DIR -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path &
        

    #     echo "Completed directory: $(basename "$DATA_DIR")"
    #     echo
    # fi
done  <<< "${date_to_paths[$date_name]}"
done

echo "All executions completed."
# ================================
