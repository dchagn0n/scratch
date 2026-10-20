#!/usr/bin/env python3
"""
Generate Rscript command blocks for multiple datasets.
Usage: python generate_commands.py
       python generate_commands.py --output commands.sh
"""

import argparse

# ─── Configuration ────────────────────────────────────────────────────────────

BASE_DIR = "/home/dochagnon/ns-3.45/scratch"
COMMON_ARGS = "-t 60 -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -i 120Mbps -p 0 -g FALSE -q FALSE" # -q TRUE" # option for do_queue

# Each dataset: (subfolder, folder_name, category_flag)
DATASETS = [
    ("twelveth", "2026-05-20_16-35-10", "basic"),
    ("eleventh", "2026-05-19_13-17-41", "basic")

    # ("twelveth", "2026-05-19_10-04-45", "basic"),
    # ("twelveth", "2026-05-22_04-20-02", "basic"),
    # ("twelveth", "2026-05-23_13-18-22", "basic"),
    # ("twelveth", "2026-05-24_17-08-54", "basic"),
    # ("twelveth", "2026-05-25_14-24-59", "basic"),
    # ("twelveth", "2026-06-01_16-09-57", "basic"),
    # ("twelveth", "2026-06-03_05-35-14", "basic"),
    # ("twelveth", "2026-06-09_23-40-44", "basic"),
    # ("twelveth", "2026-05-19_20-31-51", "basic"),
    # ("twelveth", "2026-05-22_11-50-18", "basic"),
    # ("twelveth", "2026-05-23_17-44-04", "basic"),
    # ("twelveth", "2026-05-24_20-05-21", "basic"),
    # ("twelveth", "2026-05-25_17-23-00", "basic"),
    # ("twelveth", "2026-06-01_21-26-23", "basic"),
    # ("twelveth", "2026-06-03_10-58-25", "basic"),
    # ("twelveth", "2026-05-19_23-40-13", "basic"),
    # ("twelveth", "2026-05-22_16-13-07", "basic"),
    # ("twelveth", "2026-05-23_22-03-01", "basic"),
    # ("twelveth", "2026-05-24_23-03-03", "basic"),
    # ("twelveth", "2026-05-25_20-25-56", "basic"),
    # ("twelveth", "2026-06-02_02-47-23", "basic"),
    # ("twelveth", "2026-06-03_16-19-35", "basic"),
    # ("twelveth", "2026-05-20_02-46-51", "basic"),
    # ("twelveth", "2026-05-22_20-24-38", "basic"),
    # ("twelveth", "2026-05-24_02-02-19", "basic"),
    # ("twelveth", "2026-05-25_01-58-19", "basic"),
    # ("twelveth", "2026-05-25_23-24-02", "basic"),
    # ("twelveth", "2026-06-02_08-11-59", "basic"),
    # ("twelveth", "2026-06-03_21-38-52", "basic"),
    # ("twelveth", "2026-05-20_05-48-41", "basic"),
    # ("twelveth", "2026-05-23_00-37-17", "basic"),
    # ("twelveth", "2026-05-24_06-19-13", "basic"),
    # ("twelveth", "2026-05-25_05-04-51", "basic"),
    # ("twelveth", "2026-05-26_02-16-06", "basic"),
    # ("twelveth", "2026-06-02_13-43-30", "basic"),
    # ("twelveth", "2026-06-04_03-01-06", "basic"),
    # #("twelveth", "2026-05-20_16-35-10", "basic"),
    # ("twelveth", "2026-05-23_04-49-34", "basic"),
    # ("twelveth", "2026-05-24_10-04-50", "basic"),
    # ("twelveth", "2026-05-25_08-08-56", "basic"),
    # ("twelveth", "2026-05-26_05-18-06", "basic"),
    # ("twelveth", "2026-06-02_18-57-14", "basic"),
    # ("twelveth", "2026-06-04_08-11-47", "basic"),
    # ("twelveth", "2026-05-21_11-17-38", "basic"),
    # ("twelveth", "2026-05-23_09-13-29", "basic"),
    # ("twelveth", "2026-05-24_14-06-57", "basic"),
    # ("twelveth", "2026-05-25_11-18-07", "basic"),
    # ("twelveth", "2026-05-26_08-18-37", "basic"),
    # ("twelveth", "2026-06-03_00-15-17", "basic"),
    # ("twelveth", "2026-06-09_18-27-42", "basic"),


    # ("eleventh", "2026-06-07_10-50-03", "basic"),
    # ("eleventh", "2026-06-04_23-57-10", "basic"),
    # ("eleventh", "2026-05-30_12-31-36", "basic"),
    # ("eleventh", "2026-05-28_04-33-20", "basic"),
    # ("eleventh", "2026-05-19_13-17-41", "basic"),
    # ("eleventh", "2026-05-16_21-37-24", "basic"),
    # ("eleventh", "2026-05-14_21-40-42", "basic"),
    # ("eleventh", "2026-06-07_03-31-19", "basic"),
    # ("eleventh", "2026-06-04_13-29-17", "basic"),
    # ("eleventh", "2026-05-30_03-29-56", "basic"),
    # ("eleventh", "2026-05-27_21-34-59", "basic"),
    # ("eleventh", "2026-05-18_12-30-32", "basic"),
    # ("eleventh", "2026-05-16_15-11-04", "basic"),
    # ("eleventh", "2026-05-14_16-00-39", "basic"),
    # ("eleventh", "2026-06-06_19-15-13", "basic"),
    # ("eleventh", "2026-06-01_07-04-20", "basic"),
    # ("eleventh", "2026-05-29_18-53-10", "basic"),
    # ("eleventh", "2026-05-27_14-00-55", "basic"),
    # ("eleventh", "2026-05-18_06-05-26", "basic"),
    # ("eleventh", "2026-05-16_08-18-20", "basic"),
    # ("eleventh", "2026-05-14_10-49-11", "basic"),
    # ("eleventh", "2026-06-06_10-49-53", "basic"),
    # ("eleventh", "2026-05-31_22-24-10", "basic"),
    # ("eleventh", "2026-05-29_10-54-38", "basic"),
    # ("eleventh", "2026-05-27_07-09-07", "basic"),
    # ("eleventh", "2026-05-17_23-42-07", "basic"),
    # ("eleventh", "2026-05-16_01-07-38", "basic"),
    # ("eleventh", "2026-05-14_05-05-09", "basic"),
    # ("eleventh", "2026-06-06_03-03-54", "basic"),
    # ("eleventh", "2026-05-31_13-39-18", "basic"),
    # ("eleventh", "2026-05-29_03-11-52", "basic"),
    # ("eleventh", "2026-05-27_01-04-55", "basic"),
    # ("eleventh", "2026-05-17_17-22-28", "basic"),
    # ("eleventh", "2026-05-15_18-10-27", "basic"),
    # ("eleventh", "2026-05-13_23-47-09", "basic"),
    # ("eleventh", "2026-06-05_18-46-56", "basic"),
    # ("eleventh", "2026-05-31_05-09-25", "basic"),
    # ("eleventh", "2026-05-28_19-23-39", "basic"),
    # ("eleventh", "2026-05-26_18-32-08", "basic"),
    # ("eleventh", "2026-05-17_11-02-20", "basic"),
    # ("eleventh", "2026-05-15_11-46-12", "basic"),
    # ("eleventh", "2026-05-13_17-34-41", "basic"),
    # ("eleventh", "2026-06-07_18-22-49", "basic"),
    # ("eleventh", "2026-06-05_10-57-07", "basic"),
    # ("eleventh", "2026-05-30_21-10-06", "basic"),
    # ("eleventh", "2026-05-28_12-08-58", "basic"),
    # ("eleventh", "2026-05-26_11-24-56", "basic"),
    # ("eleventh", "2026-05-17_04-08-37", "basic"),
    # ("eleventh", "2026-05-15_03-13-35", "basic"),
    # ("eleventh", "2026-05-12_18-05-35", "basic")


    # ("eleventh", "2026-05-12_18-05-35", "basic"),
    # ("eleventh", "2026-05-15_03-13-35", "basic"),
    # ("eleventh", "2026-05-17_04-08-37", "basic"),
    # ("eleventh", "2026-05-26_11-24-56", "basic"),
    # ("eleventh", "2026-05-28_12-08-58", "basic"),
    # ("eleventh", "2026-05-30_21-10-06", "basic"),
    # ("eleventh", "2026-06-05_10-57-07", "basic"),
    # ("eleventh", "2026-06-07_18-22-49", "basic"),
    # ("eleventh", "2026-05-13_17-34-41", "basic"),
    # ("eleventh", "2026-05-15_11-46-12", "basic"),
    # ("eleventh", "2026-05-17_11-02-20", "basic"),
    # ("eleventh", "2026-05-26_18-32-08", "basic"),
    # ("eleventh", "2026-05-28_19-23-39", "basic"),
    # ("eleventh", "2026-05-31_05-09-25", "basic"),
    # ("eleventh", "2026-06-05_18-46-56", "basic"),
    # ("eleventh", "2026-05-13_23-47-09", "basic"),
    # ("eleventh", "2026-05-15_18-10-27", "basic"),
    # ("eleventh", "2026-05-17_17-22-28", "basic"),
    # ("eleventh", "2026-05-27_01-04-55", "basic"),
    # ("eleventh", "2026-05-29_03-11-52", "basic"),
    # ("eleventh", "2026-05-31_13-39-18", "basic"),
    # ("eleventh", "2026-06-06_03-03-54", "basic"),
    # ("eleventh", "2026-05-14_05-05-09", "basic"),
    # ("eleventh", "2026-05-16_01-07-38", "basic"),
    # ("eleventh", "2026-05-17_23-42-07", "basic"),
    # ("eleventh", "2026-05-27_07-09-07", "basic"),
    # ("eleventh", "2026-05-29_10-54-38", "basic"),
    # ("eleventh", "2026-05-31_22-24-10", "basic"),
    # ("eleventh", "2026-06-06_10-49-53", "basic"),
    # ("eleventh", "2026-05-14_10-49-11", "basic"),
    # ("eleventh", "2026-05-16_08-18-20", "basic"),
    # ("eleventh", "2026-05-18_06-05-26", "basic"),
    # ("eleventh", "2026-05-27_14-00-55", "basic"),
    # ("eleventh", "2026-05-29_18-53-10", "basic"),
    # ("eleventh", "2026-06-01_07-04-20", "basic"),
    # ("eleventh", "2026-06-06_19-15-13", "basic"),
    # ("eleventh", "2026-05-14_16-00-39", "basic"),
    # ("eleventh", "2026-05-16_15-11-04", "basic"),
    # ("eleventh", "2026-05-18_12-30-32", "basic"),
    # ("eleventh", "2026-05-27_21-34-59", "basic"),
    # ("eleventh", "2026-05-30_03-29-56", "basic"),
    # ("eleventh", "2026-06-04_13-29-17", "basic"),
    # ("eleventh", "2026-06-07_03-31-19", "basic"),
    # ("eleventh", "2026-05-14_21-40-42", "basic"),
    # ("eleventh", "2026-05-16_21-37-24", "basic"),
    # ("eleventh", "2026-05-19_13-17-41", "basic"),
    # ("eleventh", "2026-05-28_04-33-20", "basic"),
    # ("eleventh", "2026-05-30_12-31-36", "basic"),
    # ("eleventh", "2026-06-04_23-57-10", "basic"),
    # ("eleventh", "2026-06-07_10-50-03", "basic")


    # ("twelveth", "2026-06-09_18-27-42", "basic"),
    # ("twelveth", "2026-06-09_23-40-44", "basic"),
    # ("twelveth", "2026-06-10_04-44-10", "basic"),
    # ("twelveth", "2026-06-10_09-10-51", "basic")

    # ("eleventh", "2026-06-08_17-35-37", "basic"),
    # ("eleventh", "2026-06-09_01-26-12", "basic"),
    # ("eleventh", "2026-06-09_09-39-05", "basic")

    # ("eleventh", "2026-06-04_13-29-17", "basic"),
    # ("eleventh", "2026-06-04_23-57-10", "basic"),
    # ("eleventh", "2026-06-05_10-57-07", "basic"),
    # ("eleventh", "2026-06-05_18-46-56", "basic"),
    # ("eleventh", "2026-06-06_03-03-54", "basic"),
    # ("eleventh", "2026-06-06_10-49-53", "basic"),
    # ("eleventh", "2026-06-06_19-15-13", "basic"),
    # ("eleventh", "2026-06-07_03-31-19", "basic"),
    # ("eleventh", "2026-06-07_10-50-03", "basic"),
    # ("eleventh", "2026-06-07_18-22-49", "basic"),
    # ("eleventh", "2026-06-08_02-14-31", "basic"),
    # ("eleventh", "2026-06-08_10-06-16", "basic")

    # ("twelveth", "2026-06-01_16-09-57", "basic"),
    # ("twelveth", "2026-06-01_21-26-23", "basic"),
    # ("twelveth", "2026-06-02_02-47-23", "basic"),
    # ("twelveth", "2026-06-02_08-11-59", "basic"),
    # ("twelveth", "2026-06-02_13-43-30", "basic"),
    # ("twelveth", "2026-06-02_18-57-14", "basic"),
    # ("twelveth", "2026-06-03_00-15-17", "basic"),
    # ("twelveth", "2026-06-03_05-35-14", "basic"),
    # ("twelveth", "2026-06-03_10-58-25", "basic"),
    # ("twelveth", "2026-06-03_16-19-35", "basic"),
    # ("twelveth", "2026-06-03_21-38-52", "basic"),
    # ("twelveth", "2026-06-04_03-01-06", "basic"),
    # ("twelveth", "2026-06-04_08-11-47", "basic"),

    
    # ("eleventh", "2026-05-29_10-54-38", "basic"),
    # ("eleventh", "2026-05-29_18-53-10", "basic"),
    # ("eleventh", "2026-05-30_03-29-56", "basic"),
    # ("eleventh", "2026-05-30_12-31-36", "basic"),
    # ("eleventh", "2026-05-30_21-10-06", "basic"),
    # ("eleventh", "2026-05-31_05-09-25", "basic"),
    # ("eleventh", "2026-05-31_13-39-18", "basic"),
    # ("eleventh", "2026-05-31_22-24-10", "basic"),
    # ("eleventh", "2026-06-01_07-04-20", "basic")

    
    # ("eleventh", "2026-05-28_12-08-58", "basic"),
    # ("eleventh", "2026-05-28_19-23-39", "basic"),
    # ("eleventh", "2026-05-29_03-11-52", "basic")

    # ("eleventh", "2026-05-27_14-00-55", "basic"),
    # ("eleventh", "2026-05-27_21-34-59", "basic"),
    # ("eleventh", "2026-05-28_04-33-20", "basic")

    # ("eleventh", "2026-05-26_11-24-56", "basic"),
    # ("eleventh", "2026-05-26_18-32-08", "basic"),
    # ("eleventh", "2026-05-27_01-04-55", "basic"),
    # ("eleventh", "2026-05-27_07-09-07", "basic")

    # ("twelveth", "2026-05-22_16-13-07", "basic"),
    # ("twelveth", "2026-05-22_20-24-38", "basic"),
    # ("twelveth", "2026-05-23_00-37-17", "basic"),
    # ("twelveth", "2026-05-23_04-49-34", "basic"),
    # ("twelveth", "2026-05-23_09-13-29", "basic"),
    # ("twelveth", "2026-05-23_13-18-22", "basic"),
    # ("twelveth", "2026-05-23_17-44-04", "basic"),
    # ("twelveth", "2026-05-23_22-03-01", "basic"),
    # ("twelveth", "2026-05-24_02-02-19", "basic"),
    # ("twelveth", "2026-05-24_06-19-13", "basic"),
    # ("twelveth", "2026-05-24_10-04-50", "basic"),
    # ("twelveth", "2026-05-24_14-06-57", "basic"),
    # ("twelveth", "2026-05-24_17-08-54", "basic"),
    # ("twelveth", "2026-05-24_20-05-21", "basic"),
    # ("twelveth", "2026-05-24_23-03-03", "basic"),
    # ("twelveth", "2026-05-25_01-58-19", "basic"),
    # ("twelveth", "2026-05-25_05-04-51", "basic"),
    # ("twelveth", "2026-05-25_08-08-56", "basic"),
    # ("twelveth", "2026-05-25_11-18-07", "basic"),
    # ("twelveth", "2026-05-25_14-24-59", "basic"),
    # ("twelveth", "2026-05-25_17-23-00", "basic"),
    # ("twelveth", "2026-05-25_20-25-56", "basic"),
    # ("twelveth", "2026-05-25_23-24-02", "basic"),
    # ("twelveth", "2026-05-26_02-16-06", "basic"),
    # ("twelveth", "2026-05-26_05-18-06", "basic"),
    # ("twelveth", "2026-05-26_08-18-37", "basic"),

    # ("twelveth", "2026-05-21_11-17-38", "basic"),
    # ("twelveth", "2026-05-22_04-20-02", "basic"),
    # ("twelveth", "2026-05-22_11-50-18", "basic"),

    # ("twelveth", "2026-05-20_16-35-10", "basic"),

    # ("twelveth", "2026-05-19_20-31-51", "basic"),
    # ("twelveth", "2026-05-19_23-40-13", "basic"),
    # ("twelveth", "2026-05-20_02-46-51", "basic"),
    # ("twelveth", "2026-05-20_05-48-41", "basic"),
    
    #("eleventh", "2026-05-19_13-17-41", "basic")

    # ("twelveth", "2026-05-19_10-04-45", "basic")
    
    #("eleventh", "2026-05-18_12-30-32", "basic")

    # ("eleventh", "2026-05-15_11-46-12", "basic"),
    # ("eleventh", "2026-05-15_18-10-27", "basic"),
    # ("eleventh", "2026-05-16_01-07-38", "basic"),
    # ("eleventh", "2026-05-16_08-18-20", "basic"),
    # ("eleventh", "2026-05-16_15-11-04", "basic"),
    # ("eleventh", "2026-05-16_21-37-24", "basic"),
    # ("eleventh", "2026-05-17_04-08-37", "basic"),
    # ("eleventh", "2026-05-17_11-02-20", "basic"),
    # ("eleventh", "2026-05-17_17-22-28", "basic"),
    # ("eleventh", "2026-05-17_23-42-07", "basic"),
    # ("eleventh", "2026-05-18_06-05-26", "basic")

    #  ("eleventh", "2026-05-13_17-34-41", "basic"),
    #  ("eleventh", "2026-05-13_23-47-09", "basic"),
    #  ("eleventh", "2026-05-14_05-05-09", "basic"),
    #  ("eleventh", "2026-05-14_10-49-11", "basic"),
    #  ("eleventh", "2026-05-14_16-00-39", "basic"),
    #  ("eleventh", "2026-05-14_21-40-42", "basic"),
    #  ("eleventh", "2026-05-15_03-13-35", "basic")

    #("eleventh", "2026-05-12_18-05-35", "basic")
    #("eleventh", "2026-05-12_11-28-29", "basic")
    #("tenth", "2026-05-05_11-36-50", "basic")


]

# ─── Command templates ────────────────────────────────────────────────────────

def make_block(sub: str, dataset: str, category: str) -> str:
    r = f"{BASE_DIR}/{sub}/{dataset}"  # full path to dataset
    s = f"scratch/ninth"               # script prefix
    c = category
    a = COMMON_ARGS                    # shared arguments

    if sub == "twelveth":
        lines = [
            # generation evolution
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour -e TRUE  -d 0_1_3_5_7_9 -c {c}',
            # generation on detour
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0_1_3_5_7_9 -c {c}',
            f'Rscript {s}/generation_ondetour_evolution.R {a} -r {r} -n detour -e TRUE  -d 0_1_3_5_7_9 -c {c}'
        ]
    else:
        lines = [
            #f'printf "%s\\n" "{r}" >> "$LOG_FILE_START"',

            # genreation
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0         -c {c}',
            f'Rscript {s}/generation_unified.R {a} -r {r} -n path     -e FALSE -d 0         -c {c}',
            f'Rscript {s}/generation_unified.R {a} -r {r} -n parasite -e FALSE -d 0         -c {c}',

            # # generation evolution
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour -e TRUE  -d 0_1_3_5_7_9 -c {c}',

            # # generation on detour
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0_1_3_5_7_9 -c {c}',
            f'Rscript {s}/generation_unified.R {a} -r {r} -n path     -e FALSE -d 0_1_3_5_7_9 -c {c}',
            f'Rscript {s}/generation_unified.R {a} -r {r} -n parasite -e FALSE -d 0_1_3_5_7_9 -c {c}',

            # # generation evolution
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour -e TRUE  -d 0 -c {c}',
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour -e TRUE  -d 5 -c {c}',
            # # f'printf "%s\\n" "{r}" >> "$LOG_FILE_END"',


            f'Rscript {s}/generation_ondetour_evolution.R {a} -r {r} -n detour -e TRUE  -d 0_1_3_5_7_9 -c {c}',

            # ## feature reduction
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0  -c basic --reducedFeatures scratch/ninth/feature_reduction_8/reduced_features_kopt_minauc550.rds',
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0  -c basic --reducedFeatures scratch/ninth/feature_reduction_8/reduced_features_k11_minauc550.rds',
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0  -c basic --reducedFeatures scratch/ninth/feature_reduction_8/reduced_features_k13_minauc550.rds',
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0  -c basic --reducedFeatures scratch/ninth/feature_reduction_8/reduced_features_k15_minauc550.rds',
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0  -c basic --reducedFeatures scratch/ninth/feature_reduction_8/reduced_features_k8_minauc550.rds',
            f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0  -c basic --reducedFeatures scratch/ninth/feature_reduction_8/reduced_features_k40_minauc550.rds'
        ]

    return "\n    ".join(lines)


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Generate Rscript command blocks.")
    parser.add_argument("--output", "-o", default=None, help="Output file (default: stdout)")
    args = parser.parse_args()

    separator = "\n\n" + "#" * 105 + "\n    "
    blocks = separator.join(make_block(sub, ds, cat) for sub, ds, cat in DATASETS)
    output = "    " + blocks + "\n"

    if args.output:
        with open(args.output, "w") as f:
            f.write(output)
        print(f"Written to {args.output}")
    else:
        print(output)


if __name__ == "__main__":
    main()