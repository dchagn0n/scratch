export max_jobs=$(( $(nproc) * 98 / 100 ))
    echo "max proc : $max_jobs"

    export TOTAL_RAM_GB=$(awk '/MemTotal/ { print int($2 / 1024 / 1024) }' /proc/meminfo)
    echo "Total RAM: ${TOTAL_RAM_GB} GB"

    # seuil critique de RAM libre en Mo
    export min_free_mem_gb=$(( TOTAL_RAM_GB * 40 / 100 ))  # à ajuster selon ta machine
    echo "Min free RAM: ${min_free_mem_gb} GB"

    check_mem() {
        free_mem=$(awk '/MemAvailable/ { print int($2/1024 / 1024) }' /proc/meminfo)
        echo "DEBUGloop: free_mem=$free_mem, min_free_mem_gb=$min_free_mem_gb"

        while (( free_mem < min_free_mem_gb )); do
            echo "🛑 Memory too low: ${free_mem}GB available. Waiting..."
            sleep 60
            free_mem=$(awk '/MemAvailable/ { print int($2/1024 / 1024) }' /proc/meminfo)
        done
    }

    round_to_10() {
        local val=$1
        echo $(( (val + 5) / 10 * 10 ))
    }



