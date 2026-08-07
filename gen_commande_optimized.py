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
    # ("twelveth", "2026-05-20_16-35-10", "basic"),
    # ("eleventh", "2026-05-19_13-17-41", "basic")

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
    # ("twelveth", "2026-06-09_18-27-42", "basic")


    ("eleventh", "2026-06-07_10-50-03", "basic"),
    ("eleventh", "2026-06-04_23-57-10", "basic"),
    ("eleventh", "2026-05-30_12-31-36", "basic"),
    ("eleventh", "2026-05-28_04-33-20", "basic"),
    ("eleventh", "2026-05-19_13-17-41", "basic"),
    ("eleventh", "2026-05-16_21-37-24", "basic"),
    ("eleventh", "2026-05-14_21-40-42", "basic"),
    ("eleventh", "2026-06-07_03-31-19", "basic"),
    ("eleventh", "2026-06-04_13-29-17", "basic"),
    ("eleventh", "2026-05-30_03-29-56", "basic"),
    ("eleventh", "2026-05-27_21-34-59", "basic"),
    ("eleventh", "2026-05-18_12-30-32", "basic"),
    ("eleventh", "2026-05-16_15-11-04", "basic"),
    ("eleventh", "2026-05-14_16-00-39", "basic"),
    ("eleventh", "2026-06-06_19-15-13", "basic"),
    ("eleventh", "2026-06-01_07-04-20", "basic"),
    ("eleventh", "2026-05-29_18-53-10", "basic"),
    ("eleventh", "2026-05-27_14-00-55", "basic"),
    ("eleventh", "2026-05-18_06-05-26", "basic"),
    ("eleventh", "2026-05-16_08-18-20", "basic"),
    ("eleventh", "2026-05-14_10-49-11", "basic"),
    ("eleventh", "2026-06-06_10-49-53", "basic"),
    ("eleventh", "2026-05-31_22-24-10", "basic"),
    ("eleventh", "2026-05-29_10-54-38", "basic"),
    ("eleventh", "2026-05-27_07-09-07", "basic"),
    ("eleventh", "2026-05-17_23-42-07", "basic"),
    ("eleventh", "2026-05-16_01-07-38", "basic"),
    ("eleventh", "2026-05-14_05-05-09", "basic"),
    ("eleventh", "2026-06-06_03-03-54", "basic"),
    ("eleventh", "2026-05-31_13-39-18", "basic"),
    ("eleventh", "2026-05-29_03-11-52", "basic"),
    ("eleventh", "2026-05-27_01-04-55", "basic"),
    ("eleventh", "2026-05-17_17-22-28", "basic"),
    ("eleventh", "2026-05-15_18-10-27", "basic"),
    ("eleventh", "2026-05-13_23-47-09", "basic"),
    ("eleventh", "2026-06-05_18-46-56", "basic"),
    ("eleventh", "2026-05-31_05-09-25", "basic"),
    ("eleventh", "2026-05-28_19-23-39", "basic"),
    ("eleventh", "2026-05-26_18-32-08", "basic"),
    ("eleventh", "2026-05-17_11-02-20", "basic"),
    ("eleventh", "2026-05-15_11-46-12", "basic"),
    ("eleventh", "2026-05-13_17-34-41", "basic"),
    ("eleventh", "2026-06-07_18-22-49", "basic"),
    ("eleventh", "2026-06-05_10-57-07", "basic"),
    ("eleventh", "2026-05-30_21-10-06", "basic"),
    ("eleventh", "2026-05-28_12-08-58", "basic"),
    ("eleventh", "2026-05-26_11-24-56", "basic"),
    ("eleventh", "2026-05-17_04-08-37", "basic"),
    ("eleventh", "2026-05-15_03-13-35", "basic"),
    ("eleventh", "2026-05-12_18-05-35", "basic")


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

    # ("tenth", "2026-04-27_13-46-33", "basic"),
    # ("tenth", "2026-04-27_17-31-43", "basic"),
    # ("tenth", "2026-04-27_21-17-29", "basic"),
    # ("tenth", "2026-04-28_01-06-39", "basic"),
    # ("tenth", "2026-04-28_04-51-03", "basic"),
    # ("tenth", "2026-04-28_08-36-19", "basic"),
    # ("tenth", "2026-04-28_12-52-16", "basic"),
    # ("tenth", "2026-04-28_18-21-41", "basic"),
    # ("tenth", "2026-04-28_23-49-37", "basic"),
    # ("tenth", "2026-04-29_05-08-30", "basic"),
    # ("tenth", "2026-04-29_10-48-46", "basic"),
    # ("tenth", "2026-04-29_16-15-30", "basic"),
    # ("tenth", "2026-04-29_21-39-33", "basic"),
    # ("tenth", "2026-04-30_03-27-25", "basic"),
    # ("tenth", "2026-04-30_08-41-38", "basic"),
    # ("tenth", "2026-04-30_14-01-44", "basic"),

    # # ("tenth", "2026-04-21_11-35-05", "basic"),
    # # ("tenth", "2026-04-22_10-21-13", "basic"),
    # # ("tenth", "2026-04-23_09-07-23", "basic"),
    # # ("tenth", "2026-04-24_08-09-38", "basic"),
    # # ("tenth", "2026-04-25_06-51-30", "basic"),
    # # ("tenth", "2026-04-26_05-49-33", "basic"),
    # # ("tenth", "2026-04-27_05-06-23", "basic"),
    # # ("tenth", "2026-04-21_16-27-53", "basic"),
    # # ("tenth", "2026-04-22_13-35-51", "basic"),
    # # ("tenth", "2026-04-23_12-29-32", "basic"),
    # # ("tenth", "2026-04-24_11-28-53", "basic"),
    # # ("tenth", "2026-04-25_10-12-35", "basic"),
    # # ("tenth", "2026-04-26_09-04-47", "basic"),
    # # ("tenth", "2026-04-27_08-21-59", "basic"),
    # # ("tenth", "2026-04-21_17-32-10", "basic"),
    # # ("tenth", "2026-04-22_16-50-04", "basic"),
    # # ("tenth", "2026-04-23_15-46-18", "basic"),
    # # ("tenth", "2026-04-24_14-36-51", "basic"),
    # # ("tenth", "2026-04-25_13-29-06", "basic"),
    # # ("tenth", "2026-04-26_12-21-18", "basic"),
    # # ("tenth", "2026-04-21_21-16-16", "basic"),
    # # ("tenth", "2026-04-22_20-07-05", "basic"),
    # # ("tenth", "2026-04-23_19-06-06", "basic"),
    # # ("tenth", "2026-04-24_17-50-03", "basic"),
    # # ("tenth", "2026-04-25_16-45-50", "basic"),
    # # ("tenth", "2026-04-26_15-39-08", "basic"),
    # # ("tenth", "2026-04-22_00-34-14", "basic"),
    # # ("tenth", "2026-04-22_23-22-46", "basic"),
    # # ("tenth", "2026-04-23_22-21-29", "basic"),
    # # ("tenth", "2026-04-24_21-06-56", "basic"),
    # # ("tenth", "2026-04-25_20-02-27", "basic"),
    # # ("tenth", "2026-04-26_19-18-30", "basic"),
    # # ("tenth", "2026-04-22_03-50-11", "basic"),
    # # ("tenth", "2026-04-23_02-38-19", "basic"),
    # # ("tenth", "2026-04-24_01-37-10", "basic"),
    # # ("tenth", "2026-04-25_00-21-25", "basic"),
    # # ("tenth", "2026-04-25_23-18-01", "basic"),
    # # ("tenth", "2026-04-26_22-33-05", "basic"),
    # # ("tenth", "2026-04-22_07-02-42", "basic"),
    # # ("tenth", "2026-04-23_05-53-34", "basic"),
    # # ("tenth", "2026-04-24_04-54-46", "basic"),
    # # ("tenth", "2026-04-25_03-40-09", "basic"),
    # # ("tenth", "2026-04-26_02-33-47", "basic"),
    # # ("tenth", "2026-04-27_01-51-51", "basic"),

    # # ("ninth", "2026-01-20_16-53-51", "basic"),
    # # ("ninth", "2026-02-05_03-07-57", "basic"),
    # # ("ninth", "2026-02-18_12-16-25", "basic"),
    # # ("ninth", "2026-02-24_06-26-14", "basic"),
    # # ("ninth", "2026-03-05_09-49-38", "basic"),
    # # ("ninth", "2026-03-11_05-03-44", "basic"),
    # # ("ninth", "2026-01-23_23-42-03", "basic"),
    # # ("ninth", "2026-02-05_21-14-20", "basic"),
    # # ("ninth", "2026-02-19_00-47-43", "basic"),
    # # ("ninth", "2026-02-24_19-02-07", "basic"),
    # # ("ninth", "2026-03-05_22-24-11", "basic"),
    # # ("ninth", "2026-03-16_12-16-21", "basic"),
    # # ("ninth", "2026-01-24_12-35-19", "basic"),
    # # ("ninth", "2026-02-13_13-53-51", "basic"),
    # # ("ninth", "2026-02-19_13-10-25", "basic"),
    # # ("ninth", "2026-02-25_07-33-24", "basic"),
    # # ("ninth", "2026-03-06_10-57-59", "basic"),
    # # ("ninth", "2026-03-17_00-54-14", "basic"),
    # # ("ninth", "2026-01-25_01-16-14", "basic"),
    # # ("ninth", "2026-02-14_03-58-15", "basic"),
    # # ("ninth", "2026-02-20_01-36-38", "basic"),
    # # ("ninth", "2026-02-25_20-17-57", "basic"),
    # # ("ninth", "2026-03-06_23-48-09", "basic"),
    # # ("ninth", "2026-03-17_13-28-28", "basic"),
    # # ("ninth", "2026-01-25_13-43-26", "basic"),
    # # ("ninth", "2026-02-14_17-35-54", "basic"),
    # # ("ninth", "2026-02-20_14-18-26", "basic"),
    # # ("ninth", "2026-02-26_08-47-00", "basic"),
    # # ("ninth", "2026-03-07_12-29-34", "basic"),
    # # ("ninth", "2026-03-18_02-04-28", "basic"),
    # # ("ninth", "2026-01-30_18-06-17", "basic"),
    # # ("ninth", "2026-02-15_06-15-50", "basic"),
    # # ("ninth", "2026-02-21_02-55-56", "basic"),
    # # ("ninth", "2026-02-26_21-30-39", "basic"),
    # # ("ninth", "2026-03-08_01-10-23", "basic"),
    # # ("ninth", "2026-01-31_11-09-53", "basic"),
    # # ("ninth", "2026-02-15_18-51-57", "basic"),
    # # ("ninth", "2026-02-21_15-27-37", "basic"),
    # # ("ninth", "2026-03-02_17-28-38", "basic"),
    # # ("ninth", "2026-03-08_13-54-01", "basic"),
    # # ("ninth", "2026-02-01_04-04-09", "basic"),
    # # ("ninth", "2026-02-16_07-41-43", "basic"),
    # # ("ninth", "2026-02-22_03-59-48", "basic"),
    # # ("ninth", "2026-03-03_06-11-30", "basic"),
    # # ("ninth", "2026-03-09_02-29-37", "basic"),
    # # ("ninth", "2026-02-01_18-16-38", "basic"),
    # # ("ninth", "2026-02-16_21-08-47", "basic"),
    # # ("ninth", "2026-02-22_16-37-40", "basic"),
    # # ("ninth", "2026-03-03_18-47-21", "basic"),
    # # ("ninth", "2026-03-09_15-15-53", "basic"),
    # # ("ninth", "2026-02-02_07-06-35", "basic"),
    # # ("ninth", "2026-02-17_10-48-50", "basic"),
    # # ("ninth", "2026-02-23_05-04-35", "basic"),
    # # ("ninth", "2026-03-04_07-32-04", "basic"),
    # # ("ninth", "2026-03-10_03-54-14", "basic"),
    # # ("ninth", "2026-02-04_09-37-31", "basic"),
    # # ("ninth", "2026-02-17_23-46-41", "basic"),
    # # ("ninth", "2026-02-23_17-46-58", "basic"),
    # # ("ninth", "2026-03-04_21-15-26", "basic"),
    # # ("ninth", "2026-03-10_16-30-49", "basic"),


    # ("tenth", "2026-04-27_13-46-33", "same_size_dataset"),
    # ("tenth", "2026-04-27_17-31-43", "same_size_dataset"),
    # ("tenth", "2026-04-27_21-17-29", "same_size_dataset"),
    # ("tenth", "2026-04-28_01-06-39", "same_size_dataset"),
    # ("tenth", "2026-04-28_04-51-03", "same_size_dataset"),
    # ("tenth", "2026-04-28_08-36-19", "same_size_dataset"),
    # ("tenth", "2026-04-28_12-52-16", "same_size_dataset"),
    # ("tenth", "2026-04-28_18-21-41", "same_size_dataset"),
    # ("tenth", "2026-04-28_23-49-37", "same_size_dataset"),
    # ("tenth", "2026-04-29_05-08-30", "same_size_dataset"),
    # ("tenth", "2026-04-29_10-48-46", "same_size_dataset"),
    # ("tenth", "2026-04-29_16-15-30", "same_size_dataset"),
    # ("tenth", "2026-04-29_21-39-33", "same_size_dataset"),
    # ("tenth", "2026-04-30_03-27-25", "same_size_dataset"),
    # ("tenth", "2026-04-30_08-41-38", "same_size_dataset"),
    # ("tenth", "2026-04-30_14-01-44", "same_size_dataset")
    # # ("tenth", "2026-04-21_11-35-05", "same_size_dataset"),
    # # ("tenth", "2026-04-22_10-21-13", "same_size_dataset"),
    # # ("tenth", "2026-04-23_09-07-23", "same_size_dataset"),
    # # ("tenth", "2026-04-24_08-09-38", "same_size_dataset"),
    # # ("tenth", "2026-04-25_06-51-30", "same_size_dataset"),
    # # ("tenth", "2026-04-26_05-49-33", "same_size_dataset"),
    # # ("tenth", "2026-04-27_05-06-23", "same_size_dataset"),
    # # ("tenth", "2026-04-21_16-27-53", "same_size_dataset"),
    # # ("tenth", "2026-04-22_13-35-51", "same_size_dataset"),
    # # ("tenth", "2026-04-23_12-29-32", "same_size_dataset"),
    # # ("tenth", "2026-04-24_11-28-53", "same_size_dataset"),
    # # ("tenth", "2026-04-25_10-12-35", "same_size_dataset"),
    # # ("tenth", "2026-04-26_09-04-47", "same_size_dataset"),
    # # ("tenth", "2026-04-27_08-21-59", "same_size_dataset"),
    # # ("tenth", "2026-04-21_17-32-10", "same_size_dataset"),
    # # ("tenth", "2026-04-22_16-50-04", "same_size_dataset"),
    # # ("tenth", "2026-04-23_15-46-18", "same_size_dataset"),
    # # ("tenth", "2026-04-24_14-36-51", "same_size_dataset"),
    # # ("tenth", "2026-04-25_13-29-06", "same_size_dataset"),
    # # ("tenth", "2026-04-26_12-21-18", "same_size_dataset"),
    # # ("tenth", "2026-04-21_21-16-16", "same_size_dataset"),
    # # ("tenth", "2026-04-22_20-07-05", "same_size_dataset"),
    # # ("tenth", "2026-04-23_19-06-06", "same_size_dataset"),
    # # ("tenth", "2026-04-24_17-50-03", "same_size_dataset"),
    # # ("tenth", "2026-04-25_16-45-50", "same_size_dataset"),
    # # ("tenth", "2026-04-26_15-39-08", "same_size_dataset"),
    # # ("tenth", "2026-04-22_00-34-14", "same_size_dataset"),
    # # ("tenth", "2026-04-22_23-22-46", "same_size_dataset"),
    # # ("tenth", "2026-04-23_22-21-29", "same_size_dataset"),
    # # ("tenth", "2026-04-24_21-06-56", "same_size_dataset"),
    # # ("tenth", "2026-04-25_20-02-27", "same_size_dataset"),
    # # ("tenth", "2026-04-26_19-18-30", "same_size_dataset"),
    # # ("tenth", "2026-04-22_03-50-11", "same_size_dataset"),
    # # ("tenth", "2026-04-23_02-38-19", "same_size_dataset"),
    # # ("tenth", "2026-04-24_01-37-10", "same_size_dataset"),
    # # ("tenth", "2026-04-25_00-21-25", "same_size_dataset"),
    # # ("tenth", "2026-04-25_23-18-01", "same_size_dataset"),
    # # ("tenth", "2026-04-26_22-33-05", "same_size_dataset"),
    # # ("tenth", "2026-04-22_07-02-42", "same_size_dataset"),
    # # ("tenth", "2026-04-23_05-53-34", "same_size_dataset"),
    # # ("tenth", "2026-04-24_04-54-46", "same_size_dataset"),
    # # ("tenth", "2026-04-25_03-40-09", "same_size_dataset"),
    # # ("tenth", "2026-04-26_02-33-47", "same_size_dataset"),
    # # ("tenth", "2026-04-27_01-51-51", "same_size_dataset"),
     

    
    

    # # ("ninth", "2026-01-20_16-53-51", "same_size_dataset"),
    # # ("ninth", "2026-02-05_03-07-57", "same_size_dataset"),
    # # ("ninth", "2026-02-18_12-16-25", "same_size_dataset"),
    # # ("ninth", "2026-02-24_06-26-14", "same_size_dataset"),
    # # ("ninth", "2026-03-05_09-49-38", "same_size_dataset"),
    # # ("ninth", "2026-03-11_05-03-44", "same_size_dataset"),
    # # ("ninth", "2026-01-23_23-42-03", "same_size_dataset"),
    # # ("ninth", "2026-02-05_21-14-20", "same_size_dataset"),
    # # ("ninth", "2026-02-19_00-47-43", "same_size_dataset"),
    # # ("ninth", "2026-02-24_19-02-07", "same_size_dataset"),
    # # ("ninth", "2026-03-05_22-24-11", "same_size_dataset"),
    # # ("ninth", "2026-03-16_12-16-21", "same_size_dataset"),
    # # ("ninth", "2026-01-24_12-35-19", "same_size_dataset"),
    # # ("ninth", "2026-02-13_13-53-51", "same_size_dataset"),
    # # ("ninth", "2026-02-19_13-10-25", "same_size_dataset"),
    # # ("ninth", "2026-02-25_07-33-24", "same_size_dataset"),
    # # ("ninth", "2026-03-06_10-57-59", "same_size_dataset"),
    # # ("ninth", "2026-03-17_00-54-14", "same_size_dataset"),
    # # ("ninth", "2026-01-25_01-16-14", "same_size_dataset"),
    # # ("ninth", "2026-02-14_03-58-15", "same_size_dataset"),
    # # ("ninth", "2026-02-20_01-36-38", "same_size_dataset"),
    # # ("ninth", "2026-02-25_20-17-57", "same_size_dataset"),
    # # ("ninth", "2026-03-06_23-48-09", "same_size_dataset"),
    # # ("ninth", "2026-03-17_13-28-28", "same_size_dataset"),
    # # ("ninth", "2026-01-25_13-43-26", "same_size_dataset"),
    # # ("ninth", "2026-02-14_17-35-54", "same_size_dataset"),
    # # ("ninth", "2026-02-20_14-18-26", "same_size_dataset"),
    # # ("ninth", "2026-02-26_08-47-00", "same_size_dataset"),
    # # ("ninth", "2026-03-07_12-29-34", "same_size_dataset"),
    # # ("ninth", "2026-03-18_02-04-28", "same_size_dataset"),
    # # ("ninth", "2026-01-30_18-06-17", "same_size_dataset"),
    # # ("ninth", "2026-02-15_06-15-50", "same_size_dataset"),
    # # ("ninth", "2026-02-21_02-55-56", "same_size_dataset"),
    # # ("ninth", "2026-02-26_21-30-39", "same_size_dataset"),
    # # ("ninth", "2026-03-08_01-10-23", "same_size_dataset"),
    # # ("ninth", "2026-01-31_11-09-53", "same_size_dataset"),
    # # ("ninth", "2026-02-15_18-51-57", "same_size_dataset"),
    # # ("ninth", "2026-02-21_15-27-37", "same_size_dataset"),
    # # ("ninth", "2026-03-02_17-28-38", "same_size_dataset"),
    # # ("ninth", "2026-03-08_13-54-01", "same_size_dataset"),
    # # ("ninth", "2026-02-01_04-04-09", "same_size_dataset"),
    # # ("ninth", "2026-02-16_07-41-43", "same_size_dataset"),
    # # ("ninth", "2026-02-22_03-59-48", "same_size_dataset"),
    # # ("ninth", "2026-03-03_06-11-30", "same_size_dataset"),
    # # ("ninth", "2026-03-09_02-29-37", "same_size_dataset"),
    # # ("ninth", "2026-02-01_18-16-38", "same_size_dataset"),
    # # ("ninth", "2026-02-16_21-08-47", "same_size_dataset"),
    # # ("ninth", "2026-02-22_16-37-40", "same_size_dataset"),
    # # ("ninth", "2026-03-03_18-47-21", "same_size_dataset"),
    # # ("ninth", "2026-03-09_15-15-53", "same_size_dataset"),
    # # ("ninth", "2026-02-02_07-06-35", "same_size_dataset"),
    # # ("ninth", "2026-02-17_10-48-50", "same_size_dataset"),
    # # ("ninth", "2026-02-23_05-04-35", "same_size_dataset"),
    # # ("ninth", "2026-03-04_07-32-04", "same_size_dataset"),
    # # ("ninth", "2026-03-10_03-54-14", "same_size_dataset"),
    # # ("ninth", "2026-02-04_09-37-31", "same_size_dataset"),
    # # ("ninth", "2026-02-17_23-46-41", "same_size_dataset"),
    # # ("ninth", "2026-02-23_17-46-58", "same_size_dataset"),
    # # ("ninth", "2026-03-04_21-15-26", "same_size_dataset"),
    # # ("ninth", "2026-03-10_16-30-49", "same_size_dataset")

   

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
            #f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0_1_3_5_7_9 -c {c}',
            f'Rscript {s}/generation_ondetour_evolution.R {a} -r {r} -n detour -e TRUE  -d 0_1_3_5_7_9 -c {c}'
        ]
    else:
        lines = [
            #f'printf "%s\\n" "{r}" >> "$LOG_FILE_START"',

            # genreation
            #f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0         -c {c}',
            # f'Rscript {s}/generation_unified.R {a} -r {r} -n path     -e FALSE -d 0         -c {c}',
            # f'Rscript {s}/generation_unified.R {a} -r {r} -n parasite -e FALSE -d 0         -c {c}',

            # # generation evolution
            # f'Rscript {s}/generation_unified.R {a} -r {r} -n detour -e TRUE  -d 0_1_3_5_7_9 -c {c}',

            # # generation on detour
            # f'Rscript {s}/generation_unified.R {a} -r {r} -n detour   -e FALSE -d 0_1_3_5_7_9 -c {c}',
            # f'Rscript {s}/generation_unified.R {a} -r {r} -n path     -e FALSE -d 0_1_3_5_7_9 -c {c}',
            # f'Rscript {s}/generation_unified.R {a} -r {r} -n parasite -e FALSE -d 0_1_3_5_7_9 -c {c}',

            # # generation evolution
            # f'Rscript {s}/generation_unified.R {a} -r {r} -n detour -e TRUE  -d 0 -c {c}',
            # f'Rscript {s}/generation_unified.R {a} -r {r} -n detour -e TRUE  -d 5 -c {c}',
            # # f'printf "%s\\n" "{r}" >> "$LOG_FILE_END"',


            # f'Rscript {s}/generation_ondetour_evolution.R {a} -r {r} -n detour -e TRUE  -d 0_1_3_5_7_9 -c {c}'

            ## feature reduction
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