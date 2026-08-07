# Detour Detection Pipeline — ns-3 → Python → R

This README describes the full processing chain: generating delay traces with ns-3, automatic PCAP-to-CSV extraction with Python, merging, and finally analysis / model training with R.

---

## 0. Prerequisites — Install ns-3

Follow the official documentation:
https://www.nsnam.org/docs/release/3.45/tutorial/html/quick-start.html

Tested version: **ns-3.45**.

```bash
tar xjf ns-3.45.tar.bz2
cd ns-3.45
./ns3 configure --enable-examples --enable-tests
./ns3 build
./test.py
```

All commands below assume the terminal is in the `ns-3.45` directory.

---

## 1. Generate delay datasets (ns-3, C++) — with automatic PCAP → CSV extraction

Two simulation scenarios, corresponding to two distinct `.cc` files:

| Tag `-f`   | File                           | Description                                 |
|------------|--------------------------------|---------------------------------------------|
| `eleventh` | `scratch/eleventh/eleventh.cc` | Basic scenarios, **constant parasite rate** |
| `twelveth` | `scratch/twelveth/twelveth.cc` | Scenarios with **variable parasite rate** (AR(1) → EWMA → token bucket pipeline) |

### Available parameters

| Tag  | Long name        | Default   | Description                                     |
|------|------------------|-----------|---------------------------------------------|
| `-f` | `file`           | `ninth`\* | Scenario to run (always pass `eleventh` or `twelveth` explicitly) |
| `-t` | `simulationtime` | `60`      | Simulation duration (seconds) |
| `-l` | `latency`        | `5ms`     | Propagation delay per link |
| `-b` | `bandwidth`      | `120Mbps` | Capacity of every link |
| `-a` | `datarateaccess` | `10Mbps`  | Application data rate of the source of interest ($A_0$) |
| `-e` | `datarateext`    | `60Mbps`  | Application data rate of the parasite sources |
| `-o` | `packetsize`     | `12000`   | Packet size **in bits** (12000 bits = 1500 bytes, standard MTU) |
| `-m` | `meanexp`        | `0.5`     | On-Off traffic model: **constant** duration of the "On" period **and** mean of the exponential "Off" period, **in seconds**, for the flows of interest |
| `-x` | `meanexppara`    | `0.5`     | Same parameter for the parasite sources |

\* *`ninth` is still hard-coded as the default value in several scripts (`generate_dataset.sh`, `read_pcap.py`, `generation_unified.R`...). It is not the scenario actually used — always pass `-f eleventh` or `-f twelveth` explicitly.*

> ℹ️ Methodological reminder: traffic is **not** a packet-level Poisson process. Each source alternates a constant-duration "On" burst and an exponentially-distributed "Off" silence (same mean `meanexp`/`meanexppara`, in seconds). See the manuscript, §3.2, for the full derivation.

### Command actually used

```bash
bash scratch/generate_dataset.sh -f eleventh -t 60 -l 5ms -b 120Mbps -a 10Mbps -e 60Mbps -o 12000 -m 0.5 -x 0.5 &
bash scratch/generate_dataset.sh -f twelveth -t 60 -l 5ms -b 120Mbps -a 10Mbps -e 60Mbps -o 12000 -m 0.5 -x 0.5 &
```

### Internal orchestration of the parameter sweep

`generate_dataset.sh` calls `scratch/loop_on_sequential.sh`, which chains a series of `loop_on_*.sh` scripts, each sweeping part of the parameter space (parasite rate, path length, detour length):

- **`loop_on_parasiterate.sh` to `loop_on_parasiterate9.sh`** (9 files) — sweep the parasite rate in chunks (e.g. `loop_on_parasiterate.sh` covers 1/10/20/30 Mbps), at fixed path length (0) while varying detour length (0,1,3,5,7,9 → displayed as 1,2,4,6,8,10).
- **`loop_on_path.sh` to `loop_on_path6.sh`** (6 files) — sweep path length.
- **`loop_on_detour.sh`, `loop_on_detour2.sh`** — sweep the full detour-length range (0 to 10) at fixed path length.

> ⚠️ Behaviour differs by scenario: for `twelveth` (variable parasite rate), the 9 `loop_on_parasiterate*.sh` scripts as well as `loop_on_detour.sh`/`loop_on_path.sh`/`loop_on_path2.sh`/`loop_on_path3.sh` are **skipped** (the parasite rate is no longer swept in discrete steps since it is driven by the continuous AR(1) process instead) — only `loop_on_path4.sh`, `loop_on_path5.sh`, `loop_on_path6.sh` and `loop_on_detour2.sh` run for this scenario.

Each of these scripts sources `scratch/bash_function.sh` (utility functions: `check_mem`, which pauses execution until at least 40% of total RAM is free, based on `/proc/meminfo`; `round_to_10`, used when generating rounded parasite-rate values) and calls `scratch/execute.sh` for each individual parameter combination.

### `execute.sh` — the actual simulation + extraction chain

This is the key script: for a single combination of parameters, it **runs the ns-3 simulation and immediately extracts the PCAP captures to CSV**, all in one automated chain — PCAP-to-CSV extraction is **not** a separate manual step.

```bash
./ns3 run "scratch/$file/$file.cc --repertory=$repertory --simulationTime=$simulationtime --latency=$latency --bandwidth=$bandwidth --dataRateAccess=$datarateaccess --dataRateExt=$datarateext --packetSize=$packetsize --transportProt=$protocol --numExtraRouters=$intermediate --numExtraDetour=$detour --meanExpo=$meanexp --meanExpoPara=$meanexppara"

python3 scratch/read_pcap.py -f $file -r $repertory -t $simulationtime -l $latency -b $bandwidth -a $datarateaccess -e $datarateext -o $packetsize -p $protocol -i $intermediate -d $detour -m $meanexp -x $meanexppara

rm ${prefix}*.pcap   # PCAP files are deleted right after CSV extraction to save disk space
rm ${prefix}*.tr     # ASCII trace files are deleted after (optional) bandwidth/queue diagnostics
```

This confirms the exact mapping between the shell-script tags above and the `CommandLine` arguments read inside `eleventh.cc`/`twelveth.cc` (`--repertory`, `--simulationTime`, `--latency`, `--bandwidth`, `--dataRateAccess`, `--dataRateExt`, `--packetSize`, `--transportProt`, `--numExtraRouters`, `--numExtraDetour`, `--meanExpo`, `--meanExpoPara`).

`calculate_bandwidth.py` and `calculate_queue.py` are also called at this point in the script — they are optional diagnostic tools, not part of the standard pipeline (see below). 
`plot_parasiterate.py` is called only when the scenario is `twelveth` (parasite-rate plotting is only meaningful for the variable-rate regime).

`copy_all.sh`, referenced in comments in some older scripts, is **no longer used** in the current pipeline.

### `read_pcap.py` — PCAP → per-packet CSV (called automatically by `execute.sh`)

Reads all `.pcap` files matching a given parameter set and writes one CSV row per packet (timestamp, source/destination IP, protocol, ports, size, plus the scenario metadata as columns).

Same tags as the ns-3 simulation, plus:

| Tag  | Long name   | Default          | Description                             |
|------|-------------|------------------|---------------------------------------|
| `-p` | `protocol`  | `Tcp`            | Transport protocol (`Tcp` or `Udp`) — use `Udp` to reproduce the manuscript's experiments |
| `-r` | `repertory` | `scratch/ninth/` | Folder containing the `.pcap` files **(⚠️ stale default — always pass `-r` explicitly)** |

> ⚠️ The script filters packets of interest by a hard-coded source IP address (`src_ip == "10.1.9.1"`). Verify that this address matches the intended interface if the topology is modified.

### Diagnostic tools (optional, not required to reproduce the manuscript's results)

- **`calculate_bandwidth.py`** / **`calculate_queue.py`** — compute the actual observed bandwidth / queue occupancy per hop from the ASCII `.tr` trace files. Useful to validate the simulation, not required to reproduce the results.
- **`plot_parasiterate.py`** — plots the actual generated parasite rate over time (useful for `twelveth`, to visually check the AR(1) → EWMA → token bucket pipeline).

These three scripts still have the scenario name `ninth` hard-coded into the `.tr`/`.txt` filenames they read (not parameterised via `-f`) — fix this if reusing them on `eleventh`/`twelveth` data.

---

## 2. Merge the generated files (ns-3 level)

```bash
bash scratch/merge_file_ns3.sh -t 60 -r scratch/eleventh/<YYYY-MM-DD_HH-MM-SS>/ -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path
```

Run **individually for each dated folder**, one per parameter set generated in Step 1.

> ⚠️ `merge_all_ns3.sh` exists in the repository and automates this step across all folders, but has a known bug — bypass it and run `merge_file_ns3.sh` manually on each folder as shown above.

---

## 3. Analyse the datasets (R)

### 3.1 Build the command list

`gen_commande_optimized.py` generates a file of `Rscript` commands from the list of dated folders to process (edit the `DATASETS` list at the top of the script: `(scenario, dated_folder, category)` tuples).

```bash
python3 gen_commande_optimized.py --output commande.txt
```

For each folder of the `eleventh` scenario (constant rate), the script generates calls to `generation_unified.R` for the three axes (`-n detour/path/parasite`, default path/detour training length), training on several detour lengths (`-d 0_1_3_5_7_9`), then a call to `generation_ondetour_evolution.R`. For `twelveth` (variable rate), only the `-e TRUE -d 0_1_3_5_7_9` calls are generated (`generation_unified.R` and `generation_ondetour_evolution.R`).

### 3.2 Run the commands

```bash
bash generation_explicite.sh -f commande.txt
```

Runs the commands from the file in parallel (limited by the number of concurrent jobs and available RAM), logging successes and failures separately (`scratch/processed_dirs_end.txt`, `scratch/processed_dirs_error.txt`).

### 3.3 Underlying R scripts

The R scripts themselves live in **`scratch/ninth/`**, regardless of which scenario's data is being processed (`ninth` here denotes the location of the shared code, not a scenario):

- **`scratch/ninth/generation_unified.R`** — feature extraction, training and evaluation of the 6 models for a given axis.
- **`scratch/ninth/generation_ondetour_evolution.R`** — training on several detour lengths (generic models).

Main parameters (common to both scripts):

| Tag  | Long name         | Default         | Description                                   |
|------|-------------------|-----------------|-------------------------------------------|
| `-r` | `repertory`       | `scratch/ninth` | Data folder to process (the real path, e.g. `scratch/eleventh/<date>`) |
| `-n` | `name`            | `path`          | Axis: `detour`, `path`, or `parasite` |
| `-e` | `evolution`       | `FALSE`         | `TRUE` for the variable parasite-rate regime |
| `-i` | `trainonparasite` | `60Mbps`        | Training parasite rate |
| `-d` | `trainondetour`   | `0`             | Training detour length(s) |
| `-p` | `trainonpath`     | `0`             | Training path length |
| `-c` | `comment`         | `""`            | `basic` / `same_size_dataset` |
| `-g` | `graph`           | `FALSE`         | Generate PDF plots |
| `-q` | `do_queue`        | `FALSE`         | Include queue diagnostics |

> ℹ️ Older scripts (`global_R.sh`, `generation_all_R.sh`, `generation_all_R_full.sh`, `generation_ondetour_R.sh`, `generation_ondetourevolution_R.sh`) still exist in the repository and reference outdated R scripts (`generation.R`, `generation_ondetour.R` instead of `generation_unified.R`) under `scratch/ninth`/`scratch/tenth`. **They no longer match the current workflow** (superseded by `gen_commande_optimized.py` + `generation_explicite.sh`) — ignore them or remove them from the repository to avoid future confusion.

---

## 4. Gather the analysis results

```bash
Rscript merge_file.R
```

Aggregates the results of the different runs (scenarios × seeds × axes × models) into a single dataset.

---

## 5. Manuscript-specific analyses

Once results are aggregated, the manuscript's figures and tables are produced by:

- **`feature_analysis_section32.R`** — analysis of the 42 candidate features (§3.2: separability, redundancy, robustness, dendrogram).
- **`plot_model_prediction_3.qmd`** — illustrative figures of model behaviour (§3.4: SVM/REGLOG/baseline decisions, t-SNE and DAE/VAE heatmaps).
- **`analysis_flow.qmd`** — quantitative results figures (§3.5: parasite rate influence, path/detour length, generic models, flow size). *(Large file that also contains many abandoned exploration blocks — only the blocks after `## isolation forest` for data loading, and from `# graphe en fonction du flux parasite` up to (excluding) `# specific for poster` for the plots, correspond to the figures actually published.)*

---

## Full pipeline summary

```
ns-3 (C++, eleventh.cc / twelveth.cc)
   │  scratch/generate_dataset.sh -f eleventh|twelveth
   │    → loop_on_sequential.sh → loop_on_{parasiterate,path,detour}*.sh → execute.sh
   │    → for each parameter combination: runs ns-3, THEN automatically runs read_pcap.py,
   │      then deletes the .pcap/.tr files
   │  → produces: per-packet CSV, plus .txt parasite-rate traces for twelveth
   ▼
scratch/merge_file_ns3.sh (individually, per dated folder)
   │  → merges the CSV files of one scenario run
   ▼
Python: gen_commande_optimized.py → commande.txt
   ▼
bash generation_explicite.sh -f commande.txt
   │  → calls scratch/ninth/generation_unified.R and generation_ondetour_evolution.R
   │  → feature extraction, training of the 6 models, evaluation
   ▼
Rscript merge_file.R
   │  → aggregates all results
   ▼
feature_analysis_section32.R + plot_model_prediction_3.qmd + analysis_flow.qmd
   │  → manuscript figures and tables
```

---

## Reproducibility

For the exact software environment (OS, compiler, Python/R versions, libraries and seeds), see the *Reproducibility: Software and Build Environment* appendix of the manuscript, as well as `requirements.txt` and `R_sessionInfo.txt` at the root of this repository.
