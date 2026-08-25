# ============================================================
#  feature_analysis_section32.R
#
#  Feature justification analysis — Section 3.2
#  Companion script to generation_unified.R
#
#  PRINCIPLE: uses the EXACT same data loading and flow-building
#  pipeline as generation_unified.R. The only difference is that
#  the model training loop is replaced by a statistical analysis
#  of features computed on flows of GROUP = 9 packets.
#
#  INPUT: the same CSV as generation_unified.R
#    → <prefix>_merge_path_trace_all_output_stats.csv
#
#  OUTPUT (written to ./feature_analysis_output/):
#    → feature_summary.csv          : four-criteria table per feature
#    → criterion1_reliability.pdf   : within-class CV and bootstrap
#    → criterion2_separation.pdf    : AUC-ROC per feature
#    → criterion3_correlation.pdf   : Spearman correlation heatmap
#    → criterion4_robustness_*.pdf  : AUC per feature x scenario
#                                     (one plot per axis: rate, path, detour)
#    → feature_catalog.md           : manuscript-ready text
#
#  USAGE (same arguments as generation_unified.R):
#    Rscript feature_analysis_section32.R -f ninth -t 300 -l 5ms \
#            -b 120Mbps -a 10Mbps -o 12000 -n path -r scratch/ninth
# ============================================================


# ============================================================
#  SECTION 1 — SETUP  (identical to generation_unified.R)
# ============================================================

directory <- "./scratch/ninth/"
source(file = paste0(directory, "real_data.R"))
source(file = paste0(directory, "variation_generator_function.R"))
source(file = paste0(directory, "variation_generator_function_optimized.R"))
source(file = paste0(directory, "model_function.R"))
source(file = paste0(directory, "setup_function.R"))
source(file = paste0(directory, "setup_param.R"))

library(data.table); setDTthreads(percent = 65)
library(cluster);      library(digest);   library(DescTools); library(e1071)
library(FactoMineR);   library(getip);    library(ggplot2);   library(igraph)
library(isotree);      library(magrittr); library(optparse);  library(patchwork)
library(randomForest); library(readr);    library(rpart);     library(sads)
library(stringr);      library(zeallot);  library(caret);     library(glmnet)

for (pkg in c("pROC", "ggcorrplot", "viridis", "dendextend")) {
  if (!requireNamespace(pkg, quietly = TRUE))
    install.packages(pkg, repos = "https://cloud.r-project.org")
  library(pkg, character.only = TRUE)
}

# ---- CLI arguments (identical to generation_unified.R) ----
option_list <- list(
  make_option(c("-f", "--file"),            type = "character", default = "ninth"),
  make_option(c("-t", "--simulationTime"),  type = "double",    default = 300),
  make_option(c("-l", "--latency"),         type = "character", default = "5ms"),
  make_option(c("-b", "--bandwidth"),       type = "character", default = "120Mbps"),
  make_option(c("-a", "--dataRateAccess"),  type = "character", default = "10Mbps"),
  make_option(c("-o", "--packetSize"),      type = "integer",   default = 12000),
  make_option(c("-m", "--meanExpo"),        type = "double",    default = 0.5),
  make_option(c("-x", "--meanExpoPara"),    type = "double",    default = 0.5),
  make_option(c("-n", "--name"),            type = "character", default = "path"),
  make_option(c("-g", "--graph"),           type = "logical",   default = FALSE),
  make_option(c("-r", "--repertory"),       type = "character", default = "scratch/ninth"),
  make_option(c("-e", "--evolution"),       type = "logical",   default = FALSE),
  make_option(c("-i", "--trainonparasite"), type = "character", default = "60Mbps"),
  make_option(c("-d", "--trainondetour"),   type = "character", default = "0"),
  make_option(c("-p", "--trainonpath"),     type = "character", default = "0"),
  make_option(c("-c", "--comment"),         type = "character", default = ""),
  make_option(c("-q", "--do_queue"),        type = "logical",   default = FALSE)
)
opt <- parse_args(OptionParser(option_list = option_list))

# ---- Multi-detour mode (identical) ----
split_detour <- strsplit(opt$trainondetour, "_")[[1]]
multi_detour <- length(split_detour) > 1
local_nb_att <- as.integer(split_detour)
cat("[INFO] Mode:", opt$name, "| evolution:", opt$evolution,
    "| multi_detour:", multi_detour,
    "| detours:", paste(local_nb_att, collapse = ","), "\n")

# ---- Path prefixes (identical) ----
ipaddr     <- getip("internal")
pid_suffix <- Sys.getpid()

prefix_m <- paste0(
  opt$repertory, "/T", sprintf(opt$simulationTime, fmt = "%#.6f"),
  "s_L", opt$latency, "_B", opt$bandwidth, "_Ra", opt$dataRateAccess,
  "_P", opt$packetSize, "b_Ma", sprintf(opt$meanExpo, fmt = "%#.6f"),
  "_Me", sprintf(opt$meanExpoPara, fmt = "%#.6f"), "_merge_path"
)
path_parts       <- strsplit(prefix_m, "/")[[1]]
prefix_rep       <- sub(".*(scratch/.*)/[^/]+$", "\\1", prefix_m)
last_part        <- tail(path_parts, n = 1)
px               <- strsplit(last_part, "_")[[1]]
prefix_time        <- substring(px[1], 2)
prefix_latency     <- substring(px[2], 2)
prefix_bandwidth   <- substring(px[3], 2)
prefix_rateaccess  <- substring(px[4], 3)
prefix_packetlength <- substring(px[5], 2)
prefix_meanexp     <- substring(px[6], 3)
prefix_meanexppara <- substring(px[7], 3)
rm(px)

# ---- CSV loading (identical to generation_unified.R) ----
merge_stats <- fread(
  paste0(prefix_m, "_trace_all_output_stats.csv"),
  sep = ";", verbose = TRUE, showProgress = TRUE, fill = TRUE
)
cat("[INFO] Packets loaded:", nrow(merge_stats), "\n")

do_graph <- isTRUE(opt$graph)
do_queue <- FALSE
do_flow  <- FALSE
do_pdf   <- do_graph
do_print <- FALSE

df <- merge_stats[protocol %in% c("UDP", "17", "TCP")]
rm(merge_stats)

# ---- Iteration domains (identical) ----
src             <- "10.1.9.1"
l_proto         <- unique(df[["proto"]])
l_nb_hops       <- unique(df[, extra_router])
l_nb_att        <- unique(df[, extra_detour])
l_parasite_rate <- unique(df[, parasite_rate])

# if (opt$name %in% c("detour", "path"))
#   l_parasite_rate <- l_parasite_rate[l_parasite_rate %in% c("120Mbps", "60Mbps")]
# if (opt$name %in% c("detour", "parasite"))
#   l_nb_hops <- l_nb_hops[l_nb_hops %in% c(0, 5)]
# if (opt$name %in% c("path", "parasite"))
#   l_nb_att <- l_nb_att[l_nb_att %in% c(0, 1, 3, 5, 7, 9)]
if (multi_detour) {
  trainondetour_nb_att <- unique(df[extra_detour %in% local_nb_att, extra_detour])
  l_nb_att <- unique(df[, extra_detour])
}
if (opt$evolution) {
  l_parasite_rate <- unique(c(opt$trainonparasite, l_parasite_rate))
  l_nb_hops <- unique(c(as.integer(strsplit(opt$trainonpath, "_")[[1]]), l_nb_hops))
  l_nb_att  <- unique(c(local_nb_att, l_nb_att))
}
cat("[INFO] parasite_rate:", paste(l_parasite_rate, collapse = ","), "\n")
cat("[INFO] nb_hops      :", paste(l_nb_hops,       collapse = ","), "\n")
cat("[INFO] nb_att       :", paste(l_nb_att,         collapse = ","), "\n")

# ---- Helper build_a0_a1_local (identical to generation_unified.R) ----
build_a0_a1_local <- function(df_h, df_d, nb_hops_val, nb_att_val,
                              parasite_rate_val, proto_val) {
  prefix <- paste0(
    prefix_rep, "/T", prefix_time, "_h", nb_hops_val, "_a", nb_att_val,
    "_L", prefix_latency, "_B", prefix_bandwidth,
    "_Ra", prefix_rateaccess, "_Re", parasite_rate_val,
    "_P", prefix_packetlength, "_", proto_val,
    "_Ma", prefix_meanexp, "_Me", prefix_meanexppara, "_"
  )
  check_file <- function(dt, sfx) {
    sub <- dt[file == paste0(prefix, sfx)]
    if (nrow(sub) == 0) { cat("[WARN] Missing:", prefix, sfx, "\n"); return(NULL) }
    sub
  }
  a0_H <- check_file(df_h, "trace-access0-access_access0-0-0.pcap")
  a1_H <- check_file(df_h, "trace-dist1-access1-direct_access1-1-0.pcap")
  a0_D <- check_file(df_d, "trace-access0-access_access0-0-0.pcap")
  a1_D <- check_file(df_d, "trace-dist1-access1-detour_access1-1-1.pcap")
  if (is.null(a0_H)||is.null(a1_H)||is.null(a0_D)||is.null(a1_D)) return(NULL)
  
  n_H <- min(nrow(a1_H), nrow(a0_H))
  n_D <- min(nrow(a1_D), nrow(a0_D))
  a0_a1_H <- fusion_starttoend(end = a1_H[1:n_H], start = a0_H[1:n_H], "healthy")
  a0_a1_D <- fusion_starttoend(end = a1_D[1:n_D], start = a0_D[1:n_D], "detour")
  
  a0_a1 <- rbindlist(list(a0_a1_D, a0_a1_H))
  a0_a1[, c("start_file", "end_file", "source_file", "start_packet_num") := NULL]
  lkp <- c(t_start = "start_timestamp", packet_length = "length",
           attacked = "type", delay = "delay_path", t_end = "end_timestamp")
  old_n <- unname(lkp); new_n <- names(lkp)
  setnames(a0_a1, old = old_n[old_n %in% names(a0_a1)],
           new = new_n[old_n %in% names(a0_a1)])
  a0_a1[, attacked := fifelse(attacked == "detour", 1L, 0L)]
  a0_a1[, attacked := factor(attacked)]
  a0_a1
}


# ============================================================
#  SECTION 2 — ANALYSIS PARAMETERS
# ============================================================

ANALYSIS_GROUP <- 9L #342L #27L #9L    # flow window size used in production
PROP_ATT       <- 0.1   # attack proportion used in production
N_BOOTSTRAP    <- 300L  # bootstrap replications for criterion 1
SEED           <- 1997L # same seed as generation_unified.R
ALPHA          <- 0.05  # significance threshold

# ---- Scenario tag ----
# Built from the same CLI arguments used to identify a run in generation_unified.R.
# Components:
#   opt$name           : analysis mode (path | detour | parasite)
#   prefix_time        : simulation duration (seconds)
#   prefix_latency     : link propagation latency
#   prefix_bandwidth   : link bandwidth
#   prefix_rateaccess  : access link data rate
#   prefix_packetlength: packet size (bits)
#   opt$trainondetour  : number of detour routers used for training
#                        (underscores replaced with hyphens for multi-detour, e.g. "0-1-3-5-7-9")
#   opt$trainonparasite: parasite traffic rate used for training
#
# Example output folder:
#   feature_analysis_output/path_T300s_L5ms_B120Mbps_Ra10Mbps_P12000b_d0_i60Mbps/
print(paste0("[DEBUG] length comment (",opt$comment, "): ", nchar(opt$comment)))
if (nchar(opt$comment) == 15)
{
  start_time <- opt$comment
}else{
  start_time <- format(Sys.time(), "%Y%m%d_%H%M%S") 
}

scenario_tag <- paste0(
  opt$name,
  "_T",  prefix_time,        "s",
  "_L",  prefix_latency,
  "_B",  prefix_bandwidth,
  "_Ra", prefix_rateaccess,
  "_P",  prefix_packetlength, "b",
  "_d",  gsub("_", "-", opt$trainondetour),
  "_i",  opt$trainonparasite,
  "_flow", ANALYSIS_GROUP,
  "_", start_time
)
cat("[INFO] Scenario tag:", scenario_tag, "\n")

ANA_OUTPUT_DIR <- file.path(".", "feature_analysis_output", scenario_tag)
dir.create(ANA_OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
set.seed(SEED)

# ---- Cache / checkpoint settings ----
# Each expensive analysis step saves its result to CACHE_DIR as an .rds file.
# On the next run, if the .rds exists AND the RECOMPUTE_* flag is FALSE,
# the cached result is loaded and the computation is skipped.
# This means you can fix a plot error and re-run without redoing any analysis.
#
# Dependency order:
#   RECOMPUTE_DATA      -> invalidates C1-C4 and families
#   RECOMPUTE_C3        -> invalidates families
#   Plots               -> always re-generated (no cache, fast)
#
# Quick cheatsheet:
#   Fix a plot only         -> keep all FALSE, re-run
#   Force one criterion     -> set that flag to TRUE
#   Full fresh run          -> RECOMPUTE_ALL <- TRUE
RECOMPUTE_ALL      <- TRUE   # master switch: overrides all individual flags
RECOMPUTE_DATA     <- FALSE   # re-collect all_flows + all_packets from NS-3
RECOMPUTE_C1       <- TRUE   # re-run criterion 1 (reliability)
RECOMPUTE_C2       <- TRUE   # re-run criterion 2 (separation / AUC)
RECOMPUTE_C3       <- TRUE   # re-run criterion 3 (Spearman correlation)
RECOMPUTE_C4       <- TRUE   # re-run criterion 4 (robustness)
RECOMPUTE_FAMILIES <- TRUE   # re-derive data-driven feature families

if (isTRUE(RECOMPUTE_ALL)) {
  RECOMPUTE_DATA <- RECOMPUTE_C1 <- RECOMPUTE_C2 <- RECOMPUTE_C3 <-
    RECOMPUTE_C4   <- RECOMPUTE_FAMILIES <- TRUE
}

CACHE_DIR <- file.path(ANA_OUTPUT_DIR, "cache")
dir.create(CACHE_DIR, recursive = TRUE, showWarnings = FALSE)

# Helper: load from .rds OR compute + save
load_or_compute <- function(name, compute_fn, force = FALSE) {
  path <- file.path(CACHE_DIR, paste0(name, ".rds"))
  if (!isTRUE(force) && file.exists(path)) {
    cat("[CACHE] '", name, "' loaded from cache\n", sep = "")
    return(readRDS(path))
  }
  cat("[COMPUTE] '", name, "' — running...\n", sep = "")
  t0     <- proc.time()["elapsed"]
  result <- compute_fn()
  elapsed <- round(proc.time()["elapsed"] - t0, 1)
  saveRDS(result, path)
  cat("[CACHE] '", name, "' saved (", elapsed, "s)\n", sep = "")
  result
}


# ============================================================
#  SECTION 3 — FEATURE CATALOG
#  Each entry: name, short label, family group, models that use
#  the feature (Table 3.1), formal definition, physical hypothesis
#  explaining why it should separate attacked from benign flows.
# ============================================================

FEATURE_CATALOG <- list(
  
  # ── A. Central tendency ──────────────────────────────────────────────────
  list(name = "fmedian_delay",      label = "fmedian_delay", #"Median", 
       group = "A",
       family = "Central tendency",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Median of the per-packet delays within the 9-packet flow.",
       hypothesis = "The detour adds a constant extra propagation delay through additional hops; the median captures this shift even under high background load because it is robust to outliers."),
  
  list(name = "fmean_delay",        label = "fmean_delay", #"Mean",
       group = "A",
       family = "Central tendency",
       models = "REG_LOG, SVM, VAE, DAE", #"SVM, VAE, DAE",
       definition = "Arithmetic mean of per-packet delays.",
       hypothesis = "More sensitive than the median to episodic queueing bursts on the detour path; provides a complementary signal under heavy load."),
  
  list(name = "fmeanTRIM10_delay",  label = "fmeanTRIM10_delay",#"TrimMean10",   
       group = "A",
       family = "Central tendency",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "10%-trimmed mean: excludes the lowest and highest 10% of delays before averaging.",
       hypothesis = "A compromise between the robustness of the median and the sensitivity of the mean; confirms the central shift without being biased by isolated spikes."),
  
  # ── B. Quantiles ─────────────────────────────────────────────────────────
  list(name = "fIQR_delay",         label = "fIQR_delay",   #"IQR",          
       group = "B",
       family = "Quantiles",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Interquartile range [Q75 - Q25].",
       hypothesis = "Multiple queues on the detour path widen the delay distribution, increasing IQR even when the median shift is small."),
  
  list(name = "fQ095_delay",        label = "fQ095_delay",  #"Q95",          
       group = "B",
       family = "Quantiles",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "95th percentile of per-packet delays.",
       hypothesis = "Captures latency spikes caused by bursts at the additional routers on the detour path."),
  
  list(name = "fQ095_Q005",         label = "fQ095_Q005",  #"Q95-Q5",      
       group = "B",
       family = "Quantiles",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Quantile spread [Q90 - Q5]: distribution width without the absolute extremes.",
       hypothesis = "Summarises overall variability while being robust to a single extreme outlier."),
  
  list(name = "fQ005_delay",        label = "fQ005_delay", #"Q5",           
       group = "B",
       family = "Quantiles",
       models = "REG_LOG, SVM, VAE, DAE", #"SVM",
       definition = "5th percentile of per-packet delays.",
       hypothesis = "Approximates the minimum propagation delay; structurally larger on the detour even at zero background load."),
  
  list(name = "fmin_delay",         label = "fmin_delay",  #"Min",         
       group = "B",
       family = "Quantiles",
       models = "REG_LOG, SVM, VAE, DAE", #"SVM",
       definition = "Minimum delay within the flow.",
       hypothesis = "Reflects pure propagation delay; consistently higher on the detour path regardless of load."),
  
  list(name = "fmax_delay",         label = "fmax_delay", #"Max",         
       group = "B",
       family = "Quantiles",
       models = "REG_LOG, SVM, VAE, DAE", #"SVM",
       definition = "Maximum delay within the flow.",
       hypothesis = "Captures the worst-case latency peak; amplified by queueing on the detour."),
  
  # ── C. Dispersion ─────────────────────────────────────────────────────────
  list(name = "fCV_delay",          label = "fCV_delay",   #"CV",         
       group = "C",
       family = "Dispersion",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Coefficient of variation: sigma / mu. Dimensionless relative variability.",
       hypothesis = "Queues on the detour introduce load-proportional variability that is normalised by the mean delay."),
  
  list(name = "fmad_delay",         label = "fmad_delay",  #"MAD",        
       group = "C",
       family = "Dispersion",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Median Absolute Deviation: median(|d_i - median(d)|). Highly robust dispersion estimator.",
       hypothesis = "Complements the CV in high-parasite-traffic scenarios where a few packets experience extreme delays."),
  
  list(name = "fsd_delay",          label = "fsd_delay",  #"SD",          
       group = "C",
       family = "Dispersion",
       models = "REG_LOG, SVM, VAE, DAE", #"SVM",
       definition = "Standard deviation of per-packet delays.",
       hypothesis = "Classical dispersion measure; provides an additional dimension for the SVM kernel."),
  
  # ── D. Jitter (inter-packet delay variation) ──────────────────────────────
  list(name = "fMASD_delay",        label = "fMASD_delay",  #"MASD",       
       group = "D",
       family = "Jitter",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Mean Absolute Successive Difference: E[|d_{i+1} - d_i|].",
       hypothesis = "Non-deterministic queues at the extra hops create packet-to-packet delay variability absent on the direct path."),
  
  list(name = "fRMSJ_delay",        label = "fRMSJ_delay",  #"RMSJ",        
       group = "D",
       family = "Jitter",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Root Mean Square Jitter: sqrt(E[(d_{i+1} - d_i)^2]).",
       hypothesis = "Same intuition as MASD but penalises large inter-packet jumps; more sensitive under severe congestion."),
  
  list(name = "fsd_diff_delay",     label = "fsd_diff_delay", #"SD_diff",    
       group = "D",
       family = "Jitter",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Standard deviation of successive delay differences.",
       hypothesis = "Measures jitter regularity; a multi-queue detour path produces more irregular jitter."),
  
  list(name = "fIPDV_pos_delay",    label = "fIPDV_pos_delay", #"IPDV+",   
       group = "D",
       family = "Jitter",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Positive inter-packet delay variation: E[max(d_{i+1} - d_i, 0)].",
       hypothesis = "Queue fill events on the detour create upward delay spikes that are absent on the direct path."),
  
  list(name = "fIPDV_neg_delay",    label = "fIPDV_neg_delay", #"IPDV-",   
       group = "D",
       family = "Jitter",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Negative inter-packet delay variation: E[max(d_i - d_{i+1}, 0)].",
       hypothesis = "The asymmetry between IPDV+ and IPDV- is a signature of the congestion profile specific to each path."),
  
  # ── E. Autocorrelation ───────────────────────────────────────────────────
  list(name = "facf_lag1",          label = "ACF_lag1",  
       group = "E",
       family = "Autocorrelation",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Autocorrelation coefficient at lag 1: cor(d_i, d_{i+1}).",
       hypothesis = "Queues create short-term memory between consecutive packets (runs of fast or slow packets)."),
  
  list(name = "facf_lag2",          label = "ACF_lag2", 
       group = "E",
       family = "Autocorrelation",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Autocorrelation coefficient at lag 2: cor(d_i, d_{i+2}).",
       hypothesis = "Two-step memory; complements lag-1 when congestion events span more than one inter-packet gap."),
  
  list(name = "fACF_sum",           label = "ACF_sum", 
       group = "E",
       family = "Autocorrelation",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Sum of |ACF(k)| for k = 1..10.",
       hypothesis = "Quantifies the total temporal memory of the delay process; more queues imply longer memory."),
  
  # ── F. Trends and non-stationarity ───────────────────────────────────────
  list(name = "fslope_t",           label = "fslope_t",  #"Slope",    
       group = "F",
       family = "Trends",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Slope of the linear regression of delay on packet index.",
       hypothesis = "Progressive queue build-up on the detour produces a positive slope; the direct path gives a near-zero slope."),
  
  list(name = "fCUSUM_max",         label = "fCUSUM_max",#"CUSUM",    
       group = "F",
       family = "Trends",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Maximum of the normalised CUSUM statistic over the delay sequence.",
       hypothesis = "The detour introduces an abrupt level shift in the delay series that is detectable by the CUSUM."),
  
  list(name = "fearly_diff",        label = "fearly_diff", #"EarlyDiff", 
       group = "F",
       family = "Trends",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "median(first half) - median(second half) of the flow.",
       hypothesis = "Captures within-flow regime changes, e.g. when queues progressively fill during the observation window."),
  
  # ── G. Delay ~ packet-length regression ───────────────────────────────────
  list(name = "alpha_hat",          label = "alpha_hat", #"alpha",     
       group = "G",
       family = "Regression",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Intercept of the linear regression delay ~ packet_length.",
       hypothesis = "Corresponds to the size-independent propagation baseline; structurally larger on the detour due to additional hops."),
  
  list(name = "beta_hat",           label = "beta_hat", #"beta",      
       group = "G",
       family = "Regression",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Slope of the linear regression delay ~ packet_length.",
       hypothesis = "Reflects link capacity sensitivity; altered by the different link capacities or loads on the detour path."),
  
  list(name = "r2",                 label = "R2",        
       group = "G",
       family = "Regression",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Coefficient of determination of the regression delay ~ packet_length.",
       hypothesis = "High R2 on the uncongested direct path; lower R2 on the detour where random queueing adds unexplained variance."),
  
  list(name = "sigma_eps",          label = "sigma_eps",  #"ResidSD",    
       group = "G",
       family = "Regression",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Residual standard error of the regression (unexplained variability).",
       hypothesis = "Stochastic queueing on the detour produces larger residuals than the relatively stable direct path."),
  
  list(name = "rho_tilde",          label = "rho_tilde",  #"rho",        
       group = "G",
       family = "Regression",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Estimated traffic intensity: lambda_hat x beta_hat x packet_length.",
       hypothesis = "Proxy for load on the traversed path; differs between detour and direct due to capacity/load differences."),
  
  # ── H. Distribution shape ────────────────────────────────────────────────
  list(name = "fskew_delay",        label = "Skewness",  
       group = "H",
       family = "Shape",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Skewness of the delay distribution.",
       hypothesis = "Queueing on the detour creates a right tail (extreme delay events), increasing positive skewness."),
  
  list(name = "fkurtosis_delay",    label = "Kurtosis",  
       group = "H",
       family = "Shape",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Excess kurtosis of the delay distribution.",
       hypothesis = "Queueing bursts produce heavy tails; the detour exhibits higher kurtosis than the direct path."),
  
  list(name = "fhill",              label = "Hill",     
       group = "H",
       family = "Shape",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Hill estimator: tail index of extreme delays (power-law tail).",
       hypothesis = "The detour alters the tail behaviour of delays through jitter accumulation across multiple queues."),
  
  # ── I. Spectral ──────────────────────────────────────────────────────────
  list(name = "fSpec_peak_freq",    label = "fSpec_peak_freq", #"SpecPeakFreq", 
       group = "I",
       family = "Spectral",
       models = "REG_LOG, SVM, VAE, DAE", #"SVM",
       definition = "Peak frequency of the power spectrum of successive delay differences.",
       hypothesis = "A periodic scheduler on the detour path may imprint a characteristic frequency on the delay process."),
  
  list(name = "fSpec_entropy",      label = "fSpec_entropy", #"SpecEntropy", 
       group = "I",
       family = "Spectral",
       models = "REG_LOG, SVM, VAE, DAE", #"SVM",
       definition = "Spectral entropy of the delay difference series.",
       hypothesis = "Specific scheduling policies on the detour alter the frequency-domain complexity of the delay signal."),
  
  # ── J. Flow-level features ────────────────────────────────────────────────
  list(name = "delay",              label = "FlowDelay",  
       group = "J",
       family = "Flow-level",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Total flow duration: t_end - t_start (first to last packet).",
       hypothesis = "The detour lengthens the end-to-end transit time of the entire flow."),
  
  list(name = "flow_size",          label = "flow_size", #"FlowSize",   
       group = "J",
       family = "Flow-level",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Number of packets in the flow (= 9 by construction in our pipeline).",
       hypothesis = "Control variable; identical across classes by construction. Serves as a calibration reference."),
  
  list(name = "lambda_hat",         label = "lambda_hat",    #"Lambda",    
       group = "J",
       family = "Flow-level",
       models = "REG_LOG, SVM, VAE, DAE",
       definition = "Estimated arrival rate: flow_size / delay.",
       hypothesis = "The detour lengthens inter-packet reception gaps, yielding a lower lambda_hat at the destination."),
  
  # ── K. Temporal position ──────────────────────────────────────────────────
  list(name = "t_start",            label = "t_start",   
       group = "K",
       family = "Temporal",
       models = "REG_LOG, SVM, VAE, DAE", #"SVM, VAE, DAE",
       definition = "Emission timestamp of the first packet in the flow.",
       hypothesis = "Encodes the position within the simulation; allows models to compensate for background traffic drift over time."),
  
  list(name = "t_end",              label = "t_end",     
       group = "K",
       family = "Temporal",
       models = "REG_LOG, SVM, VAE, DAE", #"SVM, VAE, DAE",
       definition = "Reception timestamp of the last packet in the flow.",
       hypothesis = "Complements t_start; encodes the absolute traversal duration."),
  
  # ── L. Activity (duty cycle) ──────────────────────────────────────────────
  list(name = "duty",               label = "Duty",      
       group = "L",
       family = "Activity",
       models = "REG_LOG, SVM, VAE, DAE", #"VAE, DAE",
       definition = "Fraction of the flow duration during which at least one packet is in transit.",
       hypothesis = "The detour increases per-packet transit time, raising the active fraction of the observation window."),
  
  list(name = "run_max",            label = "run_max", #"RunMax",    
       group = "L",
       family = "Activity",
       models = "REG_LOG, SVM, VAE, DAE", #"VAE, DAE",
       definition = "Maximum duration of a continuous active run within the flow.",
       hypothesis = "Additional hops stretch packets further apart in time, producing longer active runs."),
  
  # ── M. Baseline deviation features (REG_LOG) ─────────────────────────────
  list(name = "d_alpha",            label = "d_alpha",   
       group = "M",
       family = "Baseline deviation",
       models = "REG_LOG, SVM, VAE, DAE", #"REG_LOG",
       definition = "alpha_hat - median(alpha_hat) over benign training flows.",
       hypothesis = "A positive deviation of the propagation baseline from the reference signals a longer path."),
  
  list(name = "d_masd",             label = "d_masd",    
       group = "M",
       family = "Baseline deviation",
       models = "REG_LOG, SVM, VAE, DAE", #"REG_LOG",
       definition = "fMASD_delay - median(fMASD_delay) over benign training flows.",
       hypothesis = "An increase in short-term jitter above the reference level indicates extra queues on the path."),
  
  list(name = "d_cv",               label = "d_cv",     
       group = "M",
       family = "Baseline deviation",
       models = "REG_LOG, SVM, VAE, DAE", #"REG_LOG",
       definition = "fCV_delay - median(fCV_delay) over benign training flows.",
       hypothesis = "Elevated relative variability above the reference signals congestion not seen during training."),
  
  list(name = "d_beta",             label = "d_beta",    
       group = "M",
       family = "Baseline deviation",
       models = "REG_LOG, SVM, VAE, DAE", #"REG_LOG",
       definition = "beta_hat - median(beta_hat) over benign training flows.",
       hypothesis = "A shift in the delay-vs-size sensitivity indicates that a different link is being traversed."),

  # ============================================================
  #  EXTENSION : variables fournies aux modeles mais jusqu'ici
  #  absentes du catalogue de la section 3.2. Elles sont ajoutees
  #  pour que l'analyse des quatre criteres porte sur la totalite
  #  du jeu effectivement utilise par les classifieurs.
  # ============================================================

  # ── B(bis). Quantiles complementaires ────────────────────────────────────
  list(name = "fQ01_delay",         label = "fQ01_delay",
       group = "B", family = "Quantiles", models = "---",
       definition = "First percentile of the per-packet delays within the flow.",
       hypothesis = "Lower tail of the delay distribution; approximates the unqueued propagation time of the path, which the detour shifts upward."),

  list(name = "fFstQ_delay",        label = "fFstQ_delay",
       group = "B", family = "Quantiles", models = "SVM, VAE, DAE",
       definition = "First quartile (Q25) of the per-packet delays.",
       hypothesis = "Robust lower-central estimate of the delay level, less sensitive than the median to queueing bursts."),

  list(name = "fTrdQ_delay",        label = "fTrdQ_delay",
       group = "B", family = "Quantiles", models = "SVM, VAE, DAE",
       definition = "Third quartile (Q75) of the per-packet delays.",
       hypothesis = "Upper-central estimate of the delay level; jointly with Q25 it defines the interquartile range."),

  list(name = "fQ09_delay",         label = "fQ09_delay",
       group = "B", family = "Quantiles", models = "---",
       definition = "Ninetieth percentile of the per-packet delays.",
       hypothesis = "Upper tail of the delay distribution, driven by the deepest queue traversed along the path."),

  list(name = "fminmax_delay",      label = "fminmax_delay",
       group = "B", family = "Quantiles", models = "---",
       definition = "Range: fmax_delay - fmin_delay.",
       hypothesis = "Total spread of the delays within the flow; grows with the number of independent queues crossed, but is driven by two order statistics only and is therefore unstable at n = 9."),

  # ── C(bis). Dispersion complementaire ────────────────────────────────────
  list(name = "fvar_delay",         label = "fvar_delay",
       group = "C", family = "Dispersion", models = "---",
       definition = "Variance of the per-packet delays.",
       hypothesis = "Same quantity as fsd_delay up to a monotone transform; retained only to document the redundancy."),

  list(name = "fsderror_delay",     label = "fsderror_delay",
       group = "C", family = "Dispersion", models = "---",
       definition = "Standard error of the mean delay: fsd_delay / sqrt(n).",
       hypothesis = "Deterministic rescaling of fsd_delay at fixed flow size; carries no additional information when n is constant."),

  # ── E(bis). Autocorrelation, lags superieurs ─────────────────────────────
  list(name = "facf_lag0",          label = "ACF_lag0",
       group = "E", family = "Autocorrelation", models = "REG_LOG, SVM",
       definition = "Sample autocorrelation of the delay series at lag 0.",
       hypothesis = "None: the autocorrelation at lag 0 equals 1 by definition. This variable is constant and carries no information; it is kept in the analysis to document that fact."),

  list(name = "facf_lag3",          label = "ACF_lag3",
       group = "E", family = "Autocorrelation", models = "REG_LOG, SVM",
       definition = "Sample autocorrelation of the delay series at lag 3.",
       hypothesis = "Persistence of the queueing state beyond the immediate neighbours; the extra queues of the detour lengthen the correlation time."),

  list(name = "facf_lag4",          label = "ACF_lag4",
       group = "E", family = "Autocorrelation", models = "REG_LOG, SVM",
       definition = "Sample autocorrelation of the delay series at lag 4.",
       hypothesis = "Same mechanism as lag 3, at a longer horizon; estimated from n - 4 pairs only, hence a high sampling variance at n = 9."),

  list(name = "facf_lag5",          label = "ACF_lag5",
       group = "E", family = "Autocorrelation", models = "REG_LOG, SVM",
       definition = "Sample autocorrelation of the delay series at lag 5.",
       hypothesis = "Long-horizon memory of the queueing process; at n = 9 it rests on four pairs and is essentially noise."),

  list(name = "facf_lag6",          label = "ACF_lag6",
       group = "E", family = "Autocorrelation", models = "REG_LOG, SVM",
       definition = "Sample autocorrelation of the delay series at lag 6.",
       hypothesis = "As above; three pairs at n = 9."),

  list(name = "facf_lag7",          label = "ACF_lag7",
       group = "E", family = "Autocorrelation", models = "REG_LOG, SVM",
       definition = "Sample autocorrelation of the delay series at lag 7.",
       hypothesis = "As above; two pairs at n = 9."),

  list(name = "facf_lag8",          label = "ACF_lag8",
       group = "E", family = "Autocorrelation", models = "REG_LOG, SVM",
       definition = "Sample autocorrelation of the delay series at lag 8.",
       hypothesis = "Maximum lag available at n = 9, estimated from a single pair of observations."),

  list(name = "facf_lag9",          label = "ACF_lag9",
       group = "E", family = "Autocorrelation", models = "REG_LOG, SVM",
       definition = "Sample autocorrelation at lag 9.",
       hypothesis = "None: stats::acf caps the maximum lag at n - 1, so this variable is undefined for every 9-packet flow."),

  list(name = "facf_lag10",         label = "ACF_lag10",
       group = "E", family = "Autocorrelation", models = "REG_LOG, SVM",
       definition = "Sample autocorrelation at lag 10.",
       hypothesis = "None: undefined at n = 9 for the same reason as lag 9."),

  list(name = "facf_last",          label = "ACF_last",
       group = "E", family = "Autocorrelation", models = "---",
       definition = "Sample autocorrelation at the largest lag available for the flow.",
       hypothesis = "At a fixed flow size of 9 packets the largest available lag is 8, so this variable duplicates facf_lag8 exactly.")
)

FEAT_NAMES <- sapply(FEATURE_CATALOG, `[[`, "name")
cat("[INFO] Catalog:", length(FEAT_NAMES), "features defined.\n")


# ============================================================
#  SECTION 4 — MAIN DATA COLLECTION LOOP
#  Structure identical to generation_unified.R.
#  The model loop is replaced by:
#    (a) flow-level data collection via mix_to_flow_fast (group=9)
#    (b) packet-level data collection for bootstrap (criterion 1)
# ============================================================

# Wrapped in load_or_compute: re-run only if RECOMPUTE_DATA = TRUE
data_cache <- load_or_compute(
  name       = "collected_data",
  force      = RECOMPUTE_DATA,
  compute_fn = function() {
    
    
    all_flows   <- data.table()   # flow-level features (criteria 2, 3, 4)
    all_packets <- data.table()   # raw packet data (criterion 1 bootstrap)
    
    for (proto in l_proto) {
      cat("\n[PROTO]", proto, "\n")
      tmp_proto <- df[proto == proto]
      if (nrow(tmp_proto) == 0) next
      
      for (nb_hops in l_nb_hops) {
        tmp_hop <- tmp_proto[extra_router == nb_hops]
        if (nrow(tmp_hop) == 0) next
        
        # att_plans: identical to generation_unified.R
        if (multi_detour) {
          att_plans <- list(list(label = opt$trainondetour, att_vec = trainondetour_nb_att))
          if (opt$evolution) {
            for (a in setdiff(l_nb_att, trainondetour_nb_att))
              att_plans <- c(att_plans, list(list(label = as.character(a),
                                                  att_vec = as.integer(a))))
          }
        } else {
          att_plans <- lapply(l_nb_att, function(a)
            list(label = as.character(a), att_vec = as.integer(a)))
        }
        
        for (plan in att_plans) {
          nb_att_label    <- plan$label
          current_att_vec <- plan$att_vec
          
          tmp_att <- tmp_hop[extra_detour %in% current_att_vec]
          if (nrow(tmp_att) == 0) next
          
          for (parasite_rate in l_parasite_rate) {
            tmp_rate <- tmp_att[parasite_rate == parasite_rate]
            if (nrow(tmp_rate) == 0) next
            
            df_healthy <- tmp_rate[src_ip == src & dst_ip == "10.1.2.1"]
            df_detour  <- tmp_rate[src_ip == src & dst_ip == "10.1.3.1"]
            if (nrow(df_healthy) == 0 || nrow(df_detour) == 0) next
            
            # ---- Build a0_a1 (identical to generation_unified.R) ----
            recap <- data.table()
            for (att_val in current_att_vec) {
              dt <- build_a0_a1_local(df_healthy, df_detour,
                                      nb_hops, att_val, parasite_rate, proto)
              if (!is.null(dt) && nrow(dt) > 0) recap <- rbind(recap, dt, fill = TRUE)
            }
            if (nrow(recap) == 0) next
            a0_a1 <- recap; rm(recap); gc()
            
            # ---- (b) Keep raw packets for criterion 1 bootstrap ----
            pkt_sub <- a0_a1[, .(delay, t_start, t_end, packet_length, attacked,
                                 sc_proto = proto,      sc_hops = nb_hops,
                                 sc_att   = nb_att_label, sc_rate = parasite_rate)]
            all_packets <- rbindlist(list(all_packets, pkt_sub), fill = TRUE)
            rm(pkt_sub)
            
            # ---- (a) Build ANALYSIS_GROUP-packet flows ----
            #  Identical to the "Build flow dataset" block in generation_unified.R
            if (nrow(a0_a1[attacked == 0]) == 0 || nrow(a0_a1[attacked == 1]) == 0) next
            
            if (multi_detour) {
              dtf <- data.table()
              for (att_val in current_att_vec) {
                d0 <- a0_a1[attacked == 0 & extra_detour == att_val]
                d1 <- a0_a1[attacked == 1 & extra_detour == att_val]
                if (d0[, .N] == 0 || d1[, .N] == 0) next
                chunk <- tryCatch(
                  mix_to_flow_fast(dtf_att0 = d0, dtf_attn = d1,
                                   prop = PROP_ATT, ANALYSIS_GROUP),
                  error = function(e) {
                    cat("[WARN mix_to_flow]", conditionMessage(e), "\n"); NULL
                  }
                )
                if (!is.null(chunk) && nrow(chunk) > 0)
                  dtf <- rbind(dtf, chunk, fill = TRUE)
              }
            } else {
              dtf <- tryCatch(
                mix_to_flow_fast(dtf_att0 = a0_a1[attacked == 0],
                                 dtf_attn = a0_a1[attacked == 1],
                                 prop = PROP_ATT, ANALYSIS_GROUP),
                error = function(e) {
                  cat("[WARN mix_to_flow]", conditionMessage(e), "\n"); NULL
                }
              )
            }
            if (is.null(dtf) || nrow(dtf) == 0) next
            if (abs(dtf[, mean(attacked == 1)] - PROP_ATT) > 0.01) next
            
            # Attach explicit scenario metadata (needed for criterion 4)
            dtf[, sc_proto := proto]
            dtf[, sc_hops  := nb_hops]
            dtf[, sc_att   := nb_att_label]
            dtf[, sc_rate  := parasite_rate]
            
            # Baseline deviation features used by REG_LOG (d_alpha, d_masd, d_cv, d_beta)
            D_BASE_FRAC <- 0.70
            n_base <- max(1L, floor(nrow(dtf) * D_BASE_FRAC))
            base_rows <- seq_len(n_base)
            for (pair in list(
              list(new_col = "d_alpha", src_col = "alpha_hat"),
              list(new_col = "d_masd",  src_col = "fMASD_delay"),
              list(new_col = "d_cv",    src_col = "fCV_delay"),
              list(new_col = "d_beta",  src_col = "beta_hat")
            )) {
              if (pair$src_col %in% names(dtf)) {
                #ref <- median(dtf[attacked == 0, get(pair$src_col)], na.rm = TRUE)
                ref <- median(dtf[base_rows][attacked == 0, get(pair$src_col)],
                              na.rm = TRUE)
                if (!is.finite(ref))
                  ref <- median(dtf[attacked == 0, get(pair$src_col)], na.rm = TRUE)
                dtf[, (pair$new_col) := get(pair$src_col) - ref]
              }
            }
            
            all_flows <- rbindlist(list(all_flows, dtf), fill = TRUE)
            cat("[COLLECT]", proto, "hops=", nb_hops, "att=", nb_att_label,
                "rate=", parasite_rate, "->", nrow(dtf),
                "flows (total:", nrow(all_flows), ")\n")
            rm(a0_a1, dtf); gc()
          }
        }
      }
    }
    
    cat("\n[INFO] Collection complete:",
        nrow(all_flows), "flow-level records,",
        nrow(all_packets), "raw packets.\n")
    if (nrow(all_flows) == 0) stop("[ERROR] No flows collected. Check the input data.")
    
    list(all_flows = all_flows, all_packets = all_packets)
  }) # end load_or_compute "collected_data"

all_flows   <- data_cache$all_flows
all_packets <- data_cache$all_packets
rm(data_cache)

# ============================================================
#  SECTION 4b — PERIMETRE DE L'ANALYSE
#
#  L'analyse porte desormais sur la TOTALITE des colonnes
#  numeriques produites par le pipeline, et non sur le seul
#  catalogue redige a la main. Deux consequences :
#
#   (1) toute colonne numerique absente du catalogue recoit une
#       entree automatique (famille "Unclassified") et est
#       signalee en console : elle doit etre soit documentee dans
#       FEATURE_CATALOG, soit retiree des listes de variables des
#       modeles ;
#   (2) un ecran de degenerescence est applique en amont des
#       quatre criteres. Une variable constante, toujours NA, ou
#       strictement identique a une autre n'est pas un cas de
#       redondance statistique : c'est un defaut de definition a
#       la taille de flux consideree, et il doit etre rapporte
#       comme tel plutot que dilue dans les correlations.
# ============================================================

META_COLS <- c("attacked", "index", "group", "group_num", "run_id", "seed",
               "sc_proto", "sc_hops", "sc_att", "sc_rate",
               "extra_router", "extra_detour", "parasite_rate",
               "src_ip", "dst_ip", "file", "proto", "protocol",
               "nb_packets", "packet_size", "packet_length",
               "simulation_time"
               # --- Artefacts exclus de l'analyse (voir note ci-dessous) ---
               # Ports : discriminent le detour via le sous-reseau, pas via le delai.
               ,"src_port", "dst_port",
               # Statistiques numeriquement degenerees a 9 paquets (CV ~ 1e17).
               "diff_mean", "diff_median", "diff_min", "diff_max",
               "fmean_mean", "fmedian_median")

numeric_cols <- names(all_flows)[vapply(all_flows, is.numeric, logical(1))]
numeric_cols <- setdiff(numeric_cols, META_COLS)

# ---- (1) Completion automatique du catalogue ----
uncatalogued <- setdiff(numeric_cols, FEAT_NAMES)
if (length(uncatalogued)) {
  cat("[SCOPE] ", length(uncatalogued),
      " colonne(s) numerique(s) hors catalogue, ajoutee(s) en famille",
      " 'Unclassified' :\n", sep = "")
  cat("        ", paste(uncatalogued, collapse = ", "), "\n")
  cat("        -> a documenter dans FEATURE_CATALOG ou a retirer des",
      " listes de model_function.R\n")
  FEATURE_CATALOG <- c(FEATURE_CATALOG, lapply(uncatalogued, function(nm)
    list(name = nm, label = nm, group = "Z", family = "Unclassified",
         models = "---",
         definition = "Not documented in the feature catalog.",
         hypothesis = "None stated; included so that the analysis covers every variable supplied to the models.")))
  FEAT_NAMES <- sapply(FEATURE_CATALOG, `[[`, "name")
}

catalogued_missing <- setdiff(FEAT_NAMES, names(all_flows))
if (length(catalogued_missing))
  cat("[SCOPE] Variables du catalogue absentes des donnees :",
      paste(catalogued_missing, collapse = ", "), "\n")

# ---- (2) Ecran de degenerescence ----
scope_feats <- intersect(FEAT_NAMES, numeric_cols)

degeneracy <- rbindlist(lapply(scope_feats, function(fn) {
  v  <- suppressWarnings(as.numeric(all_flows[[fn]]))
  ok <- is.finite(v)
  data.table(feature      = fn,
             frac_finite  = round(mean(ok), 4),
             n_unique     = length(unique(v[ok])),
             constant     = sum(ok) > 0L && length(unique(v[ok])) <= 1L,
             always_na    = sum(ok) == 0L)
}))

# Doublons exacts : on compare les vecteurs sur les lignes finies communes
dup_of <- setNames(rep(NA_character_, length(scope_feats)), scope_feats)
usable <- degeneracy[constant == FALSE & always_na == FALSE, feature]
if (length(usable) > 1L) {
  sig <- lapply(usable, function(fn) {
    v <- suppressWarnings(as.numeric(all_flows[[fn]]))
    v[!is.finite(v)] <- NA_real_
    v
  })
  names(sig) <- usable
  for (i in seq_along(usable)) {
    if (!is.na(dup_of[[usable[i]]])) next
    for (j in seq_len(i - 1L)) {
      if (!is.na(dup_of[[usable[j]]])) next
      a <- sig[[i]]; b <- sig[[j]]
      if (isTRUE(all.equal(a, b, tolerance = 1e-12, check.attributes = FALSE))) {
        dup_of[[usable[i]]] <- usable[j]
        break
      }
    }
  }
}
degeneracy[, duplicate_of := dup_of[feature]]
degeneracy[, degenerate := constant | always_na | !is.na(duplicate_of)]
fwrite(degeneracy, file.path(ANA_OUTPUT_DIR, "feature_degeneracy.csv"), sep = ";")

deg <- degeneracy[degenerate == TRUE]
if (nrow(deg)) {
  cat("[SCOPE] ", nrow(deg), " variable(s) degeneree(s) a ",
      ANALYSIS_GROUP, " paquets, exclue(s) des criteres :\n", sep = "")
  for (i in seq_len(nrow(deg))) {
    r <- deg[i]
    why <- if (r$always_na) "toujours indefinie"
           else if (r$constant) "constante"
           else paste0("identique a ", r$duplicate_of)
    cat(sprintf("        %-20s %s\n", r$feature, why))
  }
}

avail_feats  <- degeneracy[degenerate == FALSE, feature]
feat_catalog <- Filter(function(f) f$name %in% avail_feats, FEATURE_CATALOG)
cat("[INFO]", length(avail_feats), "/", length(scope_feats),
    "features retained for the four-criteria analysis",
    "(", length(scope_feats) - length(avail_feats), "degenerate ).\n")


# ============================================================
#  SECTION 5 — FOUR-CRITERIA ANALYSIS FUNCTIONS
# ============================================================

# ─────────────────────────────────────────────────────────────────
#  CRITERION 1 — Reliability at n = ANALYSIS_GROUP packets
#
#  Part A: within-class CV on all_flows
#    Every row of all_flows is already a 9-packet flow.
#    The CV of feature f among benign flows directly measures
#    how stably f can be estimated from 9 packets.
#
#  Part B: packet-level bootstrap
#    Draw N_BOOTSTRAP consecutive windows of 9 raw packets from
#    all_packets (benign only), recompute each feature per window,
#    measure the CV across replications.
#    This is the direct empirical stability test at n = 9.
# ─────────────────────────────────────────────────────────────────

# Helper: compute all features on a single 9-packet window
# Uses the same internal functions as variation_generator_function_optimized.R
feat_on_window <- function(d, pl) {
  n <- length(d)
  if (n < 2) return(setNames(rep(NA_real_, length(avail_feats)), avail_feats))
  fmean <- mean(d, na.rm = TRUE)
  fsd   <- sd(d,   na.rm = TRUE)
  fit   <- tryCatch(lm(d ~ pl), error = function(e) NULL)
  
  out <- list(
    fmedian_delay     = median(d, na.rm = TRUE),
    fmean_delay       = fmean,
    fmeanTRIM10_delay = mean(d, trim = 0.1, na.rm = TRUE),
    fIQR_delay        = IQR(d, na.rm = TRUE),
    fQ095_delay       = quantile(d, 0.95, na.rm = TRUE),
    fQ09_Q005         = quantile(d, 0.90, na.rm = TRUE) - quantile(d, 0.05, na.rm = TRUE),
    fQ005_delay       = quantile(d, 0.05, na.rm = TRUE),
    fmin_delay        = min(d, na.rm = TRUE),
    fmax_delay        = max(d, na.rm = TRUE),
    fCV_delay         = if (!is.na(fsd) && fmean != 0) fsd/fmean else NA_real_,
    fmad_delay        = mad(d, na.rm = TRUE),
    fsd_delay         = fsd,
    fMASD_delay       = if (n > 1) mean(abs(diff(d)),          na.rm = TRUE) else NA_real_,
    fRMSJ_delay       = if (n > 1) sqrt(mean(diff(d)^2,        na.rm = TRUE)) else NA_real_,
    fsd_diff_delay    = if (n > 1) sd(diff(d),                 na.rm = TRUE) else NA_real_,
    fIPDV_pos_delay   = if (n > 1) mean(pmax(diff(d),  0),     na.rm = TRUE) else NA_real_,
    fIPDV_neg_delay   = if (n > 1) mean(pmax(-diff(d), 0),     na.rm = TRUE) else NA_real_,
    facf_lag1 = tryCatch(acf(d, lag.max = 1, plot = FALSE,
                             na.action = na.exclude)$acf[2], error = function(e) NA_real_),
    facf_lag2 = tryCatch(acf(d, lag.max = 2, plot = FALSE,
                             na.action = na.exclude)$acf[3], error = function(e) NA_real_),
    fACF_sum  = tryCatch({
      a <- acf(d, lag.max = min(5, n-1), plot = FALSE, na.action = na.exclude)$acf
      sum(abs(a[-1]), na.rm = TRUE)
    }, error = function(e) NA_real_),
    fslope_t    = if (n > 1) tryCatch(coef(lm(d ~ seq_len(n)))[2],
                                      error = function(e) NA_real_) else NA_real_,
    fCUSUM_max  = .cusum_max(d),
    fearly_diff = .early_late_diff(d),
    alpha_hat   = if (!is.null(fit)) unname(coef(fit)[1]) else NA_real_,
    beta_hat    = if (!is.null(fit)) unname(coef(fit)[2]) else NA_real_,
    r2          = if (!is.null(fit)) summary(fit)$r.squared else NA_real_,
    sigma_eps   = if (!is.null(fit)) sigma(fit) else NA_real_,
    fskew_delay     = if (n > 2) tryCatch(e1071::skewness(d, na.rm = TRUE),
                                          error = function(e) NA_real_) else NA_real_,
    fkurtosis_delay = if (n > 2) tryCatch(e1071::kurtosis(d, na.rm = TRUE),
                                          error = function(e) NA_real_) else NA_real_,
    fhill           = .hill_index(d),
    fSpec_peak_freq = .spec_feats(d)$fSpec_peak_freq,
    fSpec_entropy   = .spec_feats(d)$fSpec_entropy,
    delay      = diff(range(d, na.rm = TRUE)),
    flow_size  = n,
    lambda_hat = n / max(diff(range(d, na.rm = TRUE)), 1e-10),
    rho_tilde  = NA_real_,
    t_start = NA_real_, t_end = NA_real_,
    duty    = NA_real_, run_max = NA_real_,
    d_alpha = NA_real_, d_masd = NA_real_, d_cv = NA_real_, d_beta = NA_real_
  )
  # rho_tilde requires lambda_hat and beta_hat
  if (!is.na(out$lambda_hat) && !is.na(out$beta_hat))
    out$rho_tilde <- out$lambda_hat * out$beta_hat * mean(pl, na.rm = TRUE)
  
  vapply(avail_feats, function(fn) {
    v <- out[[fn]]; if (is.null(v)) NA_real_ else as.numeric(v[1])
  }, numeric(1))
}

analyze_c1 <- function() {
  # -- Part A --
  cat("[C1] Part A: within-class CV on",
      nrow(all_flows[attacked == 0]), "benign flows...\n")
  ben <- all_flows[attacked == 0]
  res_A <- rbindlist(lapply(avail_feats, function(fn) {
    v  <- ben[[fn]]; v <- v[is.finite(v)]
    if (length(v) < 5) return(data.table(feature = fn, cv_flow = NA_real_, n_flow = 0L))
    mu <- mean(v)
    data.table(feature = fn,
               cv_flow = if (mu != 0) round(sd(v)/abs(mu), 4) else NA_real_,
               n_flow  = length(v))
  }))
  
  # -- Part B --
  cat("[C1] Part B: packet-level bootstrap (", N_BOOTSTRAP,
      "windows of", ANALYSIS_GROUP, "packets)...\n")
  pkt_ben <- all_packets[attacked == 0][order(sc_rate, sc_hops, sc_att, t_start)]
  n_pkt   <- nrow(pkt_ben)
  res_B   <- data.table(feature = avail_feats, cv_boot = NA_real_, iqr_boot = NA_real_)
  
  if (n_pkt >= ANALYSIS_GROUP) {
    boot_mat <- matrix(NA_real_, nrow = N_BOOTSTRAP, ncol = length(avail_feats))
    colnames(boot_mat) <- avail_feats
    for (b in seq_len(N_BOOTSTRAP)) {
      i0  <- sample(seq_len(n_pkt - ANALYSIS_GROUP + 1), 1)
      idx <- i0:(i0 + ANALYSIS_GROUP - 1)
      boot_mat[b, ] <- feat_on_window(pkt_ben$delay[idx], pkt_ben$packet_length[idx])
    }
    res_B <- rbindlist(lapply(avail_feats, function(fn) {
      v  <- boot_mat[, fn]; v <- v[is.finite(v)]
      mu <- mean(v, na.rm = TRUE)
      data.table(feature  = fn,
                 cv_boot  = if (!is.na(mu) && mu != 0)
                   round(sd(v, na.rm = TRUE)/abs(mu), 4) else NA_real_,
                 iqr_boot = round(IQR(v, na.rm = TRUE), 6))
    }))
  }
  
  res <- merge(res_A, res_B, by = "feature", all.x = TRUE)
  # Reliable if within-class CV < 0.5 (variability < 50% of the mean)
  res[, reliable := !is.na(cv_flow) & cv_flow < 0.5]
  res
}

# ─────────────────────────────────────────────────────────────────
#  CRITERION 2 — Separation: attacked vs. benign
# ─────────────────────────────────────────────────────────────────

analyze_c2 <- function() {
  cat("[C2] AUC-ROC and Wilcoxon test on", nrow(all_flows), "flows...\n")
  rbindlist(lapply(avail_feats, function(fn) {
    v0 <- all_flows[attacked == 0, get(fn)]; v0 <- v0[is.finite(v0)]
    v1 <- all_flows[attacked == 1, get(fn)]; v1 <- v1[is.finite(v1)]
    if (length(v0) < 5 || length(v1) < 5)
      return(data.table(feature = fn, mean_benign = NA, mean_attack = NA,
                        auc = NA, p_wilcox = NA, cohen_d = NA,
                        direction = NA, separates = FALSE))
    
    wt  <- tryCatch(wilcox.test(v1, v0, alternative = "two.sided"),
                    error = function(e) list(p.value = NA_real_))
    auc <- tryCatch({
      r <- pROC::roc(c(rep(1, length(v1)), rep(0, length(v0))),
                     c(v1, v0), quiet = TRUE)
      max(as.numeric(r$auc), 1 - as.numeric(r$auc))
    }, error = function(e) NA_real_)
    
    mu0 <- mean(v0); mu1 <- mean(v1)
    sp  <- sqrt(((length(v0) - 1)*var(v0) + (length(v1) - 1)*var(v1)) /
                  (length(v0) + length(v1) - 2))
    d   <- if (is.finite(sp) && sp > 0) abs(mu1 - mu0)/sp else NA_real_
    
    data.table(feature     = fn,
               mean_benign = round(mu0, 6),
               mean_attack = round(mu1, 6),
               auc         = round(auc, 4),
               p_wilcox    = round(wt$p.value, 6),
               cohen_d     = round(d, 3),
               direction   = if (mu1 > mu0) "+" else "-",
               separates   = !is.na(auc)        && auc >= 0.60 &&
                 !is.na(wt$p.value) && wt$p.value < ALPHA)
  }))
}

# ─────────────────────────────────────────────────────────────────
#  CRITERION 3 — Informational contribution (non-redundancy)
# ─────────────────────────────────────────────────────────────────

analyze_c3 <- function() {
  cat("[C3] Spearman correlation matrix...\n")
  feat_ok <- avail_feats[sapply(avail_feats, function(fn) {
    v <- all_flows[[fn]]
    is.numeric(v) && mean(is.finite(v)) > 0.5 &&
      !is.na(var(v, na.rm = TRUE)) && var(v, na.rm = TRUE) > 0
  })]
  num_dt  <- all_flows[, ..feat_ok][, lapply(.SD, as.numeric)]
  cor_mat <- tryCatch(
    cor(num_dt, use = "pairwise.complete.obs", method = "spearman"),
    error = function(e) {
      warning("Spearman correlation failed: ", conditionMessage(e))
      matrix(NA_real_, length(feat_ok), length(feat_ok),
             dimnames = list(feat_ok, feat_ok))
    }
  )
  rho_max <- sapply(feat_ok, function(fn) {
    cors <- cor_mat[fn, setdiff(feat_ok, fn)]
    max(abs(cors), na.rm = TRUE)
  })
  res <- data.table(feature     = feat_ok,
                    rho_max     = round(rho_max, 3),
                    unique_info = rho_max < 0.85)
  list(result = res, cor_matrix = cor_mat)
}

# ─────────────────────────────────────────────────────────────────
#  CRITERION 4 — Robustness across NS-3 scenarios
# ─────────────────────────────────────────────────────────────────

analyze_c4 <- function() {
  sc_cols   <- intersect(c("sc_proto","sc_hops","sc_att","sc_rate"), names(all_flows))
  scenarios <- unique(all_flows[, ..sc_cols])
  cat("[C4]", nrow(scenarios), "distinct scenarios.\n")
  
  auc_summary <- rbindlist(lapply(avail_feats, function(fn) {
    sc_aucs <- vapply(seq_len(nrow(scenarios)), function(s) {
      cond <- rep(TRUE, nrow(all_flows))
      for (col in sc_cols) cond <- cond & (all_flows[[col]] == scenarios[[col]][s])
      sub <- all_flows[cond]
      v0 <- sub[attacked == 0, get(fn)]; v0 <- v0[is.finite(v0)]
      v1 <- sub[attacked == 1, get(fn)]; v1 <- v1[is.finite(v1)]
      if (length(v0) < 3 || length(v1) < 3) return(NA_real_)
      tryCatch({
        r <- pROC::roc(c(rep(1, length(v1)), rep(0, length(v0))),
                       c(v1, v0), quiet = TRUE)
        max(as.numeric(r$auc), 1 - as.numeric(r$auc))
      }, error = function(e) NA_real_)
    }, numeric(1))
    sc_aucs <- sc_aucs[is.finite(sc_aucs)]
    data.table(feature     = fn,
               auc_mean    = round(mean(sc_aucs), 4),
               auc_sd      = round(sd(sc_aucs),   4),
               auc_min     = round(min(sc_aucs),   4),
               auc_max     = round(max(sc_aucs),   4),
               n_scenarios = length(sc_aucs),
               robust      = length(sc_aucs) > 0 &&
                 !is.na(sd(sc_aucs)) && sd(sc_aucs) < 0.10 &&
                 mean(sc_aucs) > 0.65)
  }))
  
  # Detailed AUC per feature x scenario (used for Figure C4)
  auc_detail <- rbindlist(lapply(avail_feats, function(fn) {
    rbindlist(lapply(seq_len(nrow(scenarios)), function(s) {
      cond <- rep(TRUE, nrow(all_flows))
      for (col in sc_cols) cond <- cond & (all_flows[[col]] == scenarios[[col]][s])
      sub <- all_flows[cond]
      v0 <- sub[attacked == 0, get(fn)]; v0 <- v0[is.finite(v0)]
      v1 <- sub[attacked == 1, get(fn)]; v1 <- v1[is.finite(v1)]
      if (length(v0) < 3 || length(v1) < 3) return(NULL)
      auc_v <- tryCatch({
        r <- pROC::roc(c(rep(1, length(v1)), rep(0, length(v0))),
                       c(v1, v0), quiet = TRUE)
        max(as.numeric(r$auc), 1 - as.numeric(r$auc))
      }, error = function(e) NA_real_)
      cbind(data.table(feature = fn), scenarios[s], data.table(auc = auc_v))
    }), fill = TRUE)
  }), fill = TRUE)
  
  list(summary = auc_summary, detail = auc_detail)
}

# ── Run / load all four criteria ────────────────────────────────────────────
cat("\n[ANALYSIS] Running / loading four-criteria analysis...\n")
c1     <- load_or_compute("c1", analyze_c1, force = RECOMPUTE_C1)
c2     <- load_or_compute("c2", analyze_c2, force = RECOMPUTE_C2)
c3_out <- load_or_compute("c3", analyze_c3, force = RECOMPUTE_C3)
c3     <- c3_out$result;  cor_matrix <- c3_out$cor_matrix
c4_out <- load_or_compute("c4", analyze_c4, force = RECOMPUTE_C4)
c4     <- c4_out$summary; c4_det     <- c4_out$detail


# ============================================================
#  SECTION 5b — AUTOMATIC FEATURE FAMILY DERIVATION
#
#  Instead of manually labelling families (A, B, C…), we derive
#  them from the data using hierarchical clustering on the Spearman
#  correlation distance matrix computed in Criterion 3.
#
#  Distance used  : d(f, g) = 1 - |rho(f, g)|
#    → two features that are strongly correlated (positively or
#      negatively) are placed close together; independent features
#      are far apart.
#
#  Linkage method : Ward D2  (minimises within-cluster variance;
#                             produces compact, well-separated clusters)
#
#  Number of clusters k : selected automatically by maximising the
#    average silhouette width over k = K_MIN..K_MAX.
#    Silhouette s(i) ∈ [-1, 1] measures how well object i fits its
#    own cluster versus the nearest neighbouring cluster.
#    Higher average → better-defined, more cohesive families.
#
#  OUTPUT : column `data_family` in summary_dt  (e.g. "F1", "F2"…)
#           clusters are labelled F1 (highest mean AUC) → Fk (lowest)
#           so that the most discriminative family is always F1.
# ============================================================

K_MIN <- 3L   # minimum number of data-driven families to test
K_MAX <- 30L  # maximum number of data-driven families to test

derive_families <- function(cor_mat, auc_vec = NULL,
                            k_range = K_MIN:K_MAX) {
  feat_in <- rownames(cor_mat)
  d_mat   <- as.dist(1 - abs(cor_mat[feat_in, feat_in]))
  hc      <- hclust(d_mat, method = "ward.D2")
  
  # Silhouette score for each candidate k
  sil_scores <- vapply(k_range, function(k) {
    cl <- cutree(hc, k = k)
    if (length(unique(cl)) < 2) return(NA_real_)
    s <- cluster::silhouette(cl, d_mat)
    mean(s[, "sil_width"], na.rm = TRUE)
  }, numeric(1))
  names(sil_scores) <- k_range
  
  k_opt  <- k_range[which.max(sil_scores)]
  cl_raw <- cutree(hc, k = k_opt)    # integer cluster id per feature
  
  # Label clusters by decreasing mean AUC so that F1 is the most
  # discriminative family (makes results easier to read in the manuscript)
  if (!is.null(auc_vec) && length(auc_vec) == length(feat_in)) {
    names(auc_vec) <- feat_in
    cl_auc <- tapply(auc_vec[feat_in], cl_raw, mean, na.rm = TRUE)
    rank_order  <- rank(-cl_auc, ties.method = "first")
    cl_labeled  <- paste0("F", rank_order[as.character(cl_raw)])
  } else {
    cl_labeled <- paste0("F", cl_raw)
  }
  names(cl_labeled) <- feat_in
  
  list(hc          = hc,
       clusters    = cl_labeled,
       k           = k_opt,
       sil_scores  = sil_scores,
       d_mat       = d_mat,
       feat_names  = feat_in)
}

# Run derivation (requires cor_matrix from C3 and auc from C2)
cat("[FAMILIES] Deriving data-driven feature families\n")
cat("[FAMILIES]   Linkage : Ward D2  |  Distance : 1 - |Spearman rho|\n")
cat("[FAMILIES]   Testing k =", K_MIN, "to", K_MAX, "clusters...\n")

auc_lookup <- setNames(c2$auc, c2$feature)

fam_res <- load_or_compute(
  name       = "families",
  force      = RECOMPUTE_FAMILIES,
  compute_fn = function()
    derive_families(
      cor_mat = cor_matrix,
      auc_vec = auc_lookup[intersect(names(auc_lookup), rownames(cor_matrix))],
      k_range = K_MIN:K_MAX
    )
)
cat(sprintf("[FAMILIES]   Optimal k = %d  (mean silhouette = %.3f)\n",
            fam_res$k, max(fam_res$sil_scores, na.rm = TRUE)))
cat("[FAMILIES]   Silhouette by k:\n")
for (k in K_MIN:K_MAX) {
  s  <- fam_res$sil_scores[as.character(k)]
  mk <- if (!is.na(s) && k == fam_res$k) " <-- selected" else ""
  cat(sprintf("               k = %2d : %.3f%s\n", k, s, mk))
}
cat("[FAMILIES]   Cluster sizes:\n")
print(sort(table(fam_res$clusters)))




# ============================================================
#  SECTION 6 — SUMMARY TABLE
# ============================================================

catalog_dt <- rbindlist(lapply(feat_catalog, function(f)
  data.table(feature = f$name, label = f$label,
             group   = f$group, family = f$family,
             models  = f$models)))

summary_dt <- Reduce(function(a, b) merge(a, b, by = "feature", all.x = TRUE),
                     list(catalog_dt, c1, c2, c3, c4))
summary_dt[, n_ok := (as.integer(isTRUE(reliable))    +
                        as.integer(isTRUE(separates))   +
                        as.integer(isTRUE(unique_info)) +
                        as.integer(isTRUE(robust)))]
# Merge data-driven family assignments into summary_dt
fam_dt <- data.table(feature     = names(fam_res$clusters),
                     data_family = fam_res$clusters)
summary_dt <- merge(summary_dt, fam_dt, by = "feature", all.x = TRUE)

out_cols <- c("feature", "label", "group", "family", "data_family", "models",
              "cv_flow", "cv_boot", "reliable",
              "mean_benign", "mean_attack", "auc", "p_wilcox", "cohen_d",
              "direction", "separates",
              "rho_max", "unique_info",
              "auc_mean", "auc_sd", "auc_min", "auc_max", "n_scenarios", "robust",
              "n_ok")
fwrite(summary_dt[, intersect(out_cols, names(summary_dt)), with = FALSE],
       file.path(ANA_OUTPUT_DIR, "feature_summary.csv"), sep = ";")
cat("[OUT] feature_summary.csv written.\n")

# ============================================================
#  SECTION 6b — FAMILY-LEVEL AGGREGATION (both schemes)
#
#  The per-feature C1–C4 scores are computed once and do not
#  change with the family assignment.  What differs between the
#  manual scheme (A–M) and the data-driven scheme (F1–Fk) is
#  how features are *grouped* for reporting.
#
#  Here we aggregate the per-feature scores within each family
#  under BOTH schemes so the two groupings can be compared:
#    • manual_family_summary.csv   — criteria aggregated by manual family
#    • datadriven_family_summary.csv — criteria aggregated by data family
#    • family_mapping.csv          — cross-tabulation (manual x data-driven)
# ============================================================

aggregate_by_family <- function(dt, family_col) {
  dt[!is.na(get(family_col)), .(
    n_features    = .N,
    # C1 — Reliability
    mean_cv_flow  = round(mean(cv_flow,     na.rm = TRUE), 3),
    pct_reliable  = round(mean(reliable == TRUE, na.rm = TRUE) * 100, 1),
    # C2 — Separation
    mean_auc      = round(mean(auc,         na.rm = TRUE), 3),
    mean_cohen_d  = round(mean(cohen_d,     na.rm = TRUE), 3),
    pct_separates = round(mean(separates == TRUE, na.rm = TRUE) * 100, 1),
    # C3 — Informational contribution
    mean_rho_max  = round(mean(rho_max,     na.rm = TRUE), 3),
    pct_unique    = round(mean(unique_info == TRUE, na.rm = TRUE) * 100, 1),
    # C4 — Robustness
    mean_auc_mean = round(mean(auc_mean,    na.rm = TRUE), 3),
    mean_auc_sd   = round(mean(auc_sd,      na.rm = TRUE), 3),
    pct_robust    = round(mean(robust == TRUE, na.rm = TRUE) * 100, 1),
    # Global
    mean_n_ok     = round(mean(n_ok,        na.rm = TRUE), 2),
    features_list = paste(sort(label), collapse = ", ")
  ), by = family_col]
}

# Manual families  (A–M, from the feature catalog)
manual_agg <- aggregate_by_family(summary_dt, "family")
setnames(manual_agg, "family", "family_id")
manual_agg[, scheme := "Manual"]
setcolorder(manual_agg, c("scheme", "family_id"))

# Data-driven families  (F1–Fk, from hierarchical clustering)
data_agg <- aggregate_by_family(summary_dt, "data_family")
setnames(data_agg, "data_family", "family_id")
data_agg[, scheme := paste0("Data-driven (k=", fam_res$k, ")")]
setcolorder(data_agg, c("scheme", "family_id"))

fwrite(manual_agg, file.path(ANA_OUTPUT_DIR, "manual_family_summary.csv"),   sep = ";")
fwrite(data_agg,   file.path(ANA_OUTPUT_DIR, "datadriven_family_summary.csv"), sep = ";")
cat("[OUT] manual_family_summary.csv + datadriven_family_summary.csv written.\n")

# ============================================================
#  SECTION 6c — TABLEAUX LATEX DU MANUSCRIT
#
#  Les tableaux de la section 3.2 sont desormais generes depuis
#  les resultats et non recopies a la main : leur contenu depend
#  du perimetre analyse, qui vient de changer.
#    • feature_classification_analysis.tex : familles data-driven
#    • feature_degeneracy.tex              : variables degenerees
#    • feature_catalog_extra.tex           : variables nouvellement
#                                            documentees
# ============================================================

tex_esc <- function(x) gsub("_", "\\_", x, fixed = TRUE)
tt      <- function(x) paste0("\\texttt{", tex_esc(x), "}")

TEX_DIR <- file.path(ANA_OUTPUT_DIR, "tex")
dir.create(TEX_DIR, recursive = TRUE, showWarnings = FALSE)

# ---- (a) Familles data-driven ------------------------------------------
fam_order <- data_agg[order(-mean_auc)]
rows <- vapply(seq_len(nrow(fam_order)), function(i) {
  r     <- fam_order[i]
  members <- summary_dt[data_family == r$family_id, sort(feature)]
  dom   <- summary_dt[data_family == r$family_id,
                      names(sort(table(family), decreasing = TRUE))[1]]
  sprintf("    %s & %d & %.2f & %s & %s \\\\",
          r$family_id, r$n_features, r$mean_auc,
          if (is.na(dom)) "---" else tex_esc(dom),
          paste(vapply(members, tt, character(1)), collapse = ", "))
}, character(1))

tex_fam <- c(
  "% Genere par feature_analysis_section32.R. Ne pas editer a la main.",
  "\\begin{table}[t]",
  "  \\centering",
  sprintf("  \\caption{The %d candidate features grouped by the %d data-driven families",
          length(avail_feats), fam_res$k),
  "  obtained by hierarchical clustering (Ward linkage on the $1-|\\rho|$ Spearman",
  "  distance, $k$ selected by silhouette maximisation). Families are labelled by",
  sprintf("  decreasing mean AUC (mean silhouette~$%.2f$). Features that are degenerate at",
          max(fam_res$sil_scores, na.rm = TRUE)),
  sprintf("  a flow size of %d packets are excluded; they are listed separately in", ANALYSIS_GROUP),
  "  Table~\\ref{tab:features-degenerate}.}",
  "  \\label{tab:features-data-families}",
  "\\resizebox{\\columnwidth}{!}{",
  "  \\begin{tabular}{@{}l r c p{3.6cm} p{5.6cm}@{}}",
  "    \\toprule",
  "    \\textbf{Family} & $n$ & \\textbf{Mean AUC} & \\textbf{Dominant content} & \\textbf{Features} \\\\",
  "    \\midrule",
  rows,
  "    \\bottomrule",
  "  \\end{tabular}",
  "}",
  "\\end{table}"
)
writeLines(tex_fam, file.path(TEX_DIR, "feature_classification_analysis.tex"))

# ---- (b) Variables degenerees ------------------------------------------
if (nrow(deg)) {
  deg_rows <- vapply(seq_len(nrow(deg)), function(i) {
    r   <- deg[i]
    why <- if (r$always_na) "Undefined for every flow"
           else if (r$constant) "Constant"
           else paste0("Identical to ", tt(r$duplicate_of))
    # mdl <- summary_dt[feature == r$feature, models]
    ent <- Filter(function(f) f$name == r$feature, FEATURE_CATALOG)
    mdl <- if (length(ent)) ent[[1]]$models else NA_character_
    sprintf("    %s & %s & %s \\\\", tt(r$feature), why,
            if (!is.na(mdl) && nzchar(mdl)) tex_esc(mdl) else "---")
  }, character(1))
} else {
  deg_rows <- "    \\multicolumn{3}{c}{None} \\\\"
}
tex_deg <- c(
  "% Genere par feature_analysis_section32.R. Ne pas editer a la main.",
  "\\begin{table}[t]",
  "  \\centering",
  sprintf("  \\caption{Features that are degenerate at a flow size of %d packets. They are",
          ANALYSIS_GROUP),
  "  supplied to the models but cannot carry information at this window size, and are",
  "  therefore excluded from the four-criteria analysis.}",
  "  \\label{tab:features-degenerate}",
  "  \\begin{tabular}{@{}l l l@{}}",
  "    \\toprule",
  "    \\textbf{Feature} & \\textbf{Reason} & \\textbf{Declared users} \\\\",
  "    \\midrule",
  deg_rows,
  "    \\bottomrule",
  "  \\end{tabular}",
  "\\end{table}"
)
writeLines(tex_deg, file.path(TEX_DIR, "feature_degeneracy.tex"))

# ---- (c) Variables nouvellement documentees ----------------------------
core_44 <- c("fmedian_delay","fmean_delay","fmeanTRIM10_delay","fIQR_delay",
             "fQ095_delay","fQ095_Q005","fQ005_delay","fmin_delay","fmax_delay",
             "fCV_delay","fmad_delay","fsd_delay","fMASD_delay","fRMSJ_delay",
             "fsd_diff_delay","fIPDV_pos_delay","fIPDV_neg_delay","facf_lag1",
             "facf_lag2","fACF_sum","fslope_t","fCUSUM_max","fearly_diff",
             "alpha_hat","beta_hat","r2","sigma_eps","rho_tilde","fskew_delay",
             "fkurtosis_delay","fhill","fSpec_peak_freq","fSpec_entropy","delay",
             "flow_size","lambda_hat","t_start","t_end","duty","run_max",
             "d_alpha","d_masd","d_cv","d_beta")
new_feats <- setdiff(intersect(FEAT_NAMES, names(all_flows)), core_44)
if (length(new_feats)) {
  new_rows <- vapply(new_feats, function(fn) {
    e <- Filter(function(f) f$name == fn, FEATURE_CATALOG)[[1]]
    sprintf("    %s & %s \\\\", tt(fn), tex_esc(e$definition))
  }, character(1))
  tex_new <- c(
    "% Genere par feature_analysis_section32.R. Ne pas editer a la main.",
    "\\begin{table}[t]",
    "  \\centering",
    "  \\caption{Features supplied to the classifiers that were not described in",
    "  Table~\\ref{table:delayfeature}. They are included in the analysis so that its",
    "  scope matches the input of the models.}",
    "  \\label{tab:features-extra}",
    "\\resizebox{\\columnwidth}{!}{",
    "  \\begin{tabular}{@{}l p{10cm}@{}}",
    "    \\toprule",
    "    \\textbf{Feature} & \\textbf{Description} \\\\",
    "    \\midrule",
    unname(new_rows),
    "    \\bottomrule",
    "  \\end{tabular}",
    "}",
    "\\end{table}"
  )
  writeLines(tex_new, file.path(TEX_DIR, "feature_catalog_extra.tex"))
}
cat("[OUT] LaTeX tables written to", TEX_DIR, "\n")

# Cross-tabulation : which manual families feed into which data-driven families?
if ("data_family" %in% names(summary_dt) && "family" %in% names(summary_dt)) {
  mapping_wide <- dcast(
    summary_dt[!is.na(data_family)],
    family ~ data_family,
    fun.aggregate = length,
    value.var     = "feature"
  )
  fwrite(mapping_wide, file.path(ANA_OUTPUT_DIR, "family_mapping.csv"), sep = ";")
  cat("[OUT] family_mapping.csv (manual x data-driven cross-table) written.\n")
}


# ============================================================
#  SECTION 7 — FIGURES
# ============================================================

# Colour palette — one colour per feature family (A–M)
FAMILY_COLORS <- c(
  "Central tendency" = "#2166AC", Quantiles = "#4393C3", Dispersion = "#92C5DE",
  Jitter = "#F4A582", Autocorrelation = "#D6604D", Trends = "#B2182B",
  Regression = "#762A83", Shape = "#9970AB", Spectral = "#C2A5CF",
  "Flow-level" = "#4DAC26", Temporal = "#7FBC41", Activity = "#B8E186", 
  "Baseline deviation" = "#A6DBA0", Unclassified = "#BDBDBD"
)
GROUP_COLORS <- c(
  A = "#2166AC", B = "#4393C3", C = "#92C5DE",
  D = "#F4A582", E = "#D6604D", F = "#B2182B",
  G = "#762A83", H = "#9970AB", I = "#C2A5CF",
  J = "#4DAC26", K = "#7FBC41", L = "#B8E186", M = "#A6DBA0"
)
TH <- theme_minimal(base_size = 15) +
  theme(legend.position  = "bottom",
        panel.grid.minor = element_blank())

merge_labels <- function(dt_sum)
  merge(dt_sum, catalog_dt[, .(feature, label, group)],
        by = c("feature", "label", "group"), all.x = TRUE)

# ---- Figure C1: within-class CV and bootstrap ----
cat("[PLOT] Figure C1 (Reliability)...\n")
p1_dt <- merge_labels(summary_dt)[!is.na(cv_flow)][order(group, cv_flow)]
p1_dt[, lbl := factor(label, levels = rev(unique(label)))]

p_c1 <- ggplot(p1_dt, aes(x = lbl, y = cv_flow, fill = family)) +
  geom_col(alpha = 0.85) +
  geom_point(aes(y = cv_boot), shape = 21, color = "black",
             fill = "white", size = 1.8, stroke = 0.8, na.rm = TRUE) +
  geom_hline(yintercept = 0.5, linetype = "dashed",
             color = "red", linewidth = 0.5) +
  coord_flip() +
  scale_fill_manual(values = FAMILY_COLORS, name = "Feature family") +
  labs(
    title    = "Criterion 1 — Reliability at n = 9 packets",
    subtitle = paste0(
      "Bars: within-class CV (benign flows) over ", nrow(all_flows),
      " flow-level records (each = 9 packets).\n",
      "Dots: bootstrap CV over ", N_BOOTSTRAP,
      " windows of 9 consecutive raw NS-3 packets (",
      nrow(all_packets), " packets total).\n",
      "Red dashed line: CV = 0.5 threshold (feature considered reliable below this line)."
    ),
    x = NULL,
    y = "Coefficient of Variation (CV)"
  ) + TH
ggsave(file.path(ANA_OUTPUT_DIR, "criterion1_reliability.pdf"), p_c1,
       width = 10, height = max(7, 0.28 * nrow(p1_dt)), units = "in")
cat("[PLOT] criterion1_reliability.pdf written.\n")

# ---- Figure C2: AUC-ROC ----
cat("[PLOT] Figure C2 (Separation)...\n")
p2_dt <- merge_labels(summary_dt)[!is.na(auc)][order(group, -auc)]
p2_dt[, lbl := factor(label, levels = rev(unique(label)))]

p_c2 <- ggplot(p2_dt, aes(x = lbl, y = auc, fill = family)) +
  geom_col(alpha = 0.85) +
  geom_hline(yintercept = 0.60, linetype = "dashed",
             color = "red",    linewidth = 0.5) +
  geom_hline(yintercept = 0.50, linetype = "dotted",
             color = "gray50", linewidth = 0.4) +
  coord_flip() +
  scale_fill_manual(values = FAMILY_COLORS, name = "Feature family") +
  scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.1)) +
  labs(
    title    = "Criterion 2 — Discriminative power (AUC-ROC)",
    subtitle = paste0(
      nrow(all_flows), " flows of ", ANALYSIS_GROUP, " packets each. ",
      "\nRed dashed line: AUC = 0.60 (minimum threshold). ",
      "\nDotted line: random classifier (AUC = 0.50)."
    ),
    x = NULL,
    y = "AUC-ROC"
  ) + 
  theme_minimal(base_size = 25) +
  theme(axis.text.y = element_text(size = 25),
        legend.position  = "bottom",
        panel.grid.minor = element_blank())
ggsave(file.path(ANA_OUTPUT_DIR, "criterion2_separation.pdf"), p_c2,
       width = 20, height = max(25, 0.5 * nrow(p2_dt)), units = "in")
cat("[PLOT] criterion2_separation.pdf written.\n")

# ---- Figure C3: Spearman correlation heatmap ----
# Features are ordered by DATA-DRIVEN family (fam_res$clusters) so that
# the block structure of the heatmap mirrors the automatic grouping.
cat("[PLOT] Figure C3 (Correlation)...\n")
if (!all(is.na(cor_matrix))) {
  # Order features by data-driven family then by mean AUC within family
  feat_fam_dt <- data.table(
    feature     = names(fam_res$clusters),
    data_family = fam_res$clusters
  )
  feat_fam_dt <- merge(feat_fam_dt,
                       c2[, .(feature, auc)],
                       by = "feature", all.x = TRUE)
  feat_fam_dt <- feat_fam_dt[order(data_family, -auc)]
  feat_ord    <- feat_fam_dt[feature %in% rownames(cor_matrix), feature]
  cor_sub     <- cor_matrix[feat_ord, feat_ord]
  p_c3 <- ggcorrplot::ggcorrplot(
    cor_sub,
    method        = "square",
    type          = "upper", # "full", #lower",
    lab           = FALSE,
    colors        = c("#2166AC", "white", "#D6604D"),
    outline.color = "gray90",
    tl.cex        = 18
  ) +
    labs(
      title    = "Criterion 3 — Spearman correlation between features",
      subtitle = paste0(
        "Features ordered by data-driven family (k = ", fam_res$k,
        " clusters, Ward D2 on |Spearman rho| distance). ",
        "|rho| > 0.85 indicates redundancy. \n",
        sum(c3$unique_info, na.rm = TRUE), "/", nrow(c3),
        " features with max |rho| < 0.85."
      ),
      fill = "Spearman rho"
    ) +
    TH + theme_minimal(base_size = 20) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 20),
          axis.text.y = element_text(size = 20))
  ggsave(file.path(ANA_OUTPUT_DIR, "criterion3_correlation.pdf"), p_c3,
         width = 25, height = 23, units = "in")
  cat("[PLOT] criterion3_correlation.pdf written.\n")
}

# ---- Figure: Feature families dendrogram ----
# The dendrogram shows the full hierarchical structure; colored boxes
# mark the k = fam_res$k clusters selected by silhouette optimisation.
cat("[PLOT] Figure: Feature families dendrogram...\n")
if (!is.null(fam_res$hc)) {
  # # Colour palette for clusters (one colour per family)
  # n_fam       <- fam_res$k
  # fam_palette <- colorRampPalette(c(
  #   "#2166AC","#F4A582","#B2182B","#762A83","#4DAC26","#B8E186",
  #   "#D6604D","#92C5DE","#9970AB","#7FBC41","#E6F5C9","#A6DBA0"
  # ))(n_fam)
  # Colour palette for clusters — hcl.colors guarantees k distinct,
  # saturated, readable colours for any k (no pale tones)
  n_fam       <- fam_res$k
  fam_palette <- grDevices::hcl.colors(n_fam, palette = "Dark 3")
  
  # Silhouette curve
  sil_dt <- data.table(
    k   = as.integer(names(fam_res$sil_scores)),
    sil = fam_res$sil_scores
  )
  p_sil <- ggplot(sil_dt[!is.na(sil)], aes(x = k, y = sil)) +
    geom_line(color = "steelblue", linewidth = 0.8) +
    geom_point(color = "steelblue", size = 2.5) +
    geom_point(data  = sil_dt[k == fam_res$k],
               color = "red", size = 4, shape = 18) +
    scale_x_continuous(breaks = sil_dt$k) +
    labs(
      title    = "Silhouette-based selection of the number of families",
      subtitle = paste0("Optimal k = ", fam_res$k,
                        "  (red diamond). Higher silhouette = better cluster cohesion."),
      x = "Number of families (k)", y = "Mean silhouette width"
    ) + TH
  
  # ---- Dendrogram ----
  # NOTE: rect.hclust() only works for VERTICAL dendrograms — with
  # horiz = TRUE it draws boxes in the wrong coordinate system.
  # dendextend::rect.dendrogram(horiz = TRUE) computes them correctly,
  # and colouring branches/labels per cluster makes the grouping
  # readable even for singleton families.
  
  dend <- as.dendrogram(fam_res$hc)
  
  # Cluster membership (hclust integer ids), then re-expressed in the
  # order the leaves appear on the plotted dendrogram, so that boxes,
  # branch colours, and the legend all follow the same visual order.
  cl_cut     <- cutree(fam_res$hc, k = n_fam)     # named by feature
  cl_by_leaf <- cl_cut[labels(dend)]              # cluster id per leaf, plot order
  cl_order   <- unique(cl_by_leaf)                # distinct clusters, plot order
  
  # One palette colour per cluster, assigned in dendrogram order
  col_by_cluster <- setNames(fam_palette[seq_along(cl_order)], cl_order)
  
  # hclust integer id -> our F-label (F1 = highest mean AUC, ..., Fk)
  id_to_flabel <- vapply(
    split(fam_res$clusters[names(cl_cut)], cl_cut),
    function(x) unique(x)[1], character(1)
  )
  
  # Colour branches and leaf labels by cluster (dendrogram order)
  # dend <- dendextend::color_branches(dend, k = n_fam,
  #                                    col = unname(col_by_cluster))
  dend <- dendextend::color_labels(dend, k = n_fam,
                                   col = unname(col_by_cluster))
  dend <- dendextend::set(dend, "labels_cex",  2)
  dend <- dendextend::set(dend, "branches_lwd", 2)
  
  dendro_file <- file.path(ANA_OUTPUT_DIR, "feature_families_dendrogram.pdf")
  pdf(dendro_file, width = 28, height = 28)
  par(mar = c(4, 1, 4, 12))
  plot(dend, horiz = TRUE,
       main = paste0(
         "Feature Families - Hierarchical Clustering\n",
         "Ward D2 linkage on 1 - |Spearman rho| distance  |  k = ",
         n_fam, " families  |  mean silhouette = ",
         round(max(fam_res$sil_scores, na.rm = TRUE), 3)),
       cex.main = 1, cex = 2,cex.axis=2,
       xlab = "Height (1 - |Spearman rho|)")
  
  # Boxes computed correctly for horizontal dendrograms
  dendextend::rect.dendrogram(dend, k = n_fam, horiz = TRUE,
                              border = unname(col_by_cluster),
                              lty = 1, lwd = 2,
                              lower_rect = -0.31)
  
  # Legend in the same visual (dendrogram) order as boxes and branches
  leg_labels <- id_to_flabel[as.character(cl_order)]
  leg_sizes  <- table(cl_by_leaf)[as.character(cl_order)]
  legend("topleft",
         legend = paste0(leg_labels, " (n=", leg_sizes, ")"),
         fill   = unname(col_by_cluster),
         title  = "Family", cex = 2, bty = "n")
  dev.off()
  cat("[PLOT] feature_families_dendrogram.pdf written.\n")
  
  # Silhouette plot saved alongside
  ggsave(file.path(ANA_OUTPUT_DIR, "feature_families_silhouette.pdf"),
         p_sil, width = 7, height = 4, units = "in")
  cat("[PLOT] feature_families_silhouette.pdf written.\n")
}


# ---- Figure C4: AUC per feature x scenario ----
#
# HOW TO READ THESE PLOTS:
#  * One POINT  = the AUC of one feature in ONE full scenario
#    (a specific combination of parasite rate x path length x
#    detour length). At a given x value there is therefore one
#    point per combination of the OTHER parameters — the vertical
#    spread of the points shows how sensitive the feature is to
#    those other axes.
#  * One LINE   = the MEAN AUC of one feature at each x value,
#    i.e. its trend along this axis averaged over the other
#    parameters. A flat line above the threshold = robust feature.
#
# (Drawing geom_line directly on the raw points would connect
#  points that share the same x, producing meaningless vertical
#  strokes — the lines must be drawn on per-x aggregates.)
cat("[PLOT] Figure C4 (Robustness)...\n")
if (!is.null(c4_det) && nrow(c4_det) > 0) {
  top20  <- c4[order(-auc_mean)][1:min(7, .N), feature]
  top20 <- c(top20, "fsd_diff_delay", "fRMSJ_delay", "fMASD_delay", "d_masd", "duty")
  print(top20)
  c4_top <- c4_det[feature %in% top20]
  c4_top <- merge(c4_top, catalog_dt[, .(feature, label, family)], by = "feature")
  c4_top <- c4_top[!is.na(auc)]
  c4_top$sc_hops <- c4_top$sc_hops +4
  c4_top <- c4_top[sc_hops %in% c(4,6,8,10,12,14),]
  c4_top$sc_att <- as.numeric(c4_top$sc_att) +1
  c4_top <- c4_top[sc_att %in% c(1,2,4,6,8,10),]
  
  # Helper: robustness plot along one scenario axis
  plot_robustness_axis <- function(dt_in, x_ax, x_label, out_suffix) {
    dt <- copy(dt_in)
    
    # Order x-axis levels numerically ("10Mbps" < "40Mbps" < "120Mbps")
    x_vals   <- unique(dt[[x_ax]])
    x_nums   <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", as.character(x_vals))))
    x_levels <- if (all(!is.na(x_nums))) x_vals[order(x_nums)] else sort(x_vals)
    dt[, (x_ax) := factor(get(x_ax), levels = x_levels)]
    
    # One trend line per feature: mean AUC at each x value,
    # averaged over the other scenario parameters
    dt_line <- dt[, .(auc = mean(auc, na.rm = TRUE)),
                  by = c("label", "family", x_ax)]
    
    p <- ggplot(dt, aes_string(x = x_ax, y = "auc", color = "family")) +
      geom_point(alpha = 0.30, size = 1.0,
                 position = position_jitter(width = 0.15, height = 0)) +
      geom_line(data = dt_line,
                aes_string(x = x_ax, y = "auc",
                           color = "family", group = "label"),
                linewidth = 0.7, alpha = 0.9) +
      geom_hline(yintercept = 0.65, linetype = "dashed",
                 color = "red", linewidth = 0.4) +
      scale_color_manual(values = FAMILY_COLORS, name = "Feature family") +
      scale_y_continuous(limits = c(0.4, 1), breaks = seq(0.4, 1, 0.1)) +
      labs(
        title    = "Criterion 4 — Robustness across NS-3 scenarios (Top 20 features)",
        subtitle = paste0(
          "Points: per-scenario AUC (one point = one combination of the other parameters).\n",
          "Lines: mean AUC of each feature at each value of this axis. ",
          "Red dashed line: AUC = 0.65.\n",
          sum(c4$robust, na.rm = TRUE), "/", nrow(c4),
          " features robust (AUC SD < 0.10 and mean AUC > 0.65)."
        ),
        x = x_label,
        y = "AUC-ROC per scenario"
      ) +
      TH +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
    
    ggsave(file.path(ANA_OUTPUT_DIR,
                     paste0("criterion4_robustness_", out_suffix, ".pdf")),
           p, width = 10, height = 6, units = "in")
    cat("[PLOT] criterion4_robustness_", out_suffix, ".pdf written.\n", sep = "")
  }

  # x_vals   <- unique(c4_top[[x_ax]])
  # x_nums   <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", x_vals)))
  # x_levels <- if (all(!is.na(x_nums))) x_vals[order(x_nums)] else sort(x_vals)
  # c4_top[, (x_ax) := factor(get(x_ax), levels = x_levels)]
  # if (nrow(c4_top) > 0) {
  #   p_c4 <- ggplot(c4_top,
  #                  aes_string(x = x_ax, y = "auc",
  #                             color = "family", group = "label")) +
  #     geom_line(alpha  = 0.5, linewidth = 0.5) +
  #     geom_point(alpha = 0.8, size = 1.4) +
  #     geom_hline(yintercept = 0.65, linetype = "dashed",
  #                color = "red", linewidth = 0.4) +
  #     scale_color_manual(values = FAMILY_COLORS, name = "Feature family") +
  #     scale_y_continuous(limits = c(0.4, 1), breaks = seq(0.4, 1, 0.1)) +
  #     labs(
  #       title    = "Criterion 4 — Robustness across NS-3 scenarios (Top 20 features)",
  #       subtitle = paste0(
  #         "Each line = one feature across all scenario conditions. ",
  #         "Red dashed line: AUC = 0.65. ",
  #         "\nFlat lines indicate robust features. \n",
  #         sum(c4$robust, na.rm = TRUE), "/", nrow(c4),
  #         " features robust (AUC SD < 0.10 and mean AUC > 0.65)."
  #       ),
  #       x = "Parasite rate (Mbps)",
  #       y = "AUC-ROC per scenario"
  #     ) +
  #     TH +
  #     theme(axis.text.x = element_text(angle = 45, hjust = 1))
  #   ggsave(file.path(ANA_OUTPUT_DIR, "criterion4_robustness_rate.pdf"), p_c4,
  #          width = 10, height = 6, units = "in")
  #   cat("[PLOT] criterion4_robustness_rate.pdf written.\n")
  # }
  # x_ax <- if ("sc_att" %in% names(c4_top)) "sc_att"
  # else if ("sc_rate" %in% names(c4_top)) "sc_rate"
  # else names(c4_top)[1]
  # # ---- Order x-axis levels numerically ----
  # # Values like "10Mbps", "120Mbps", "40Mbps" are character strings.
  # # Sort them by extracting the leading numeric part so the axis reads
  # # 10 Mbps -> 40 Mbps -> 80 Mbps -> 120 Mbps instead of alphabetically.
  # # Falls back to alphabetical sort when no numeric prefix is found.
  # x_vals   <- unique(c4_top[[x_ax]])
  # x_nums   <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", x_vals)))
  # x_levels <- if (all(!is.na(x_nums))) x_vals[order(x_nums)] else sort(x_vals)
  # c4_top[, (x_ax) := factor(get(x_ax), levels = x_levels)]
  # if (nrow(c4_top) > 0) {
  #   p_c4 <- ggplot(c4_top,
  #                  aes_string(x = x_ax, y = "auc",
  #                             color = "family", group = "label")) +
  #     geom_line(alpha  = 0.5, linewidth = 0.5) +
  #     geom_point(alpha = 0.8, size = 1.4) +
  #     geom_hline(yintercept = 0.65, linetype = "dashed",
  #                color = "red", linewidth = 0.4) +
  #     scale_color_manual(values = FAMILY_COLORS, name = "Feature family") +
  #     scale_y_continuous(limits = c(0.4, 1), breaks = seq(0.4, 1, 0.1)) +
  #     labs(
  #       title    = "Criterion 4 — Robustness across NS-3 scenarios (Top 20 features)",
  #       subtitle = paste0(
  #         "Each line = one feature across all scenario conditions. ",
  #         "\nRed dashed line: AUC = 0.65. ",
  #         "\nFlat lines indicate robust features. \n",
  #         sum(c4$robust, na.rm = TRUE), "/", nrow(c4),
  #         " features robust (AUC SD < 0.10 and mean AUC > 0.65)."
  #       ),
  #       x = "Number of additional on-detour router",
  #       y = "AUC-ROC per scenario"
  #     ) +
  #     TH +
  #     theme() #axis.text.x = element_text(angle = 45, hjust = 1))
  #   ggsave(file.path(ANA_OUTPUT_DIR, "criterion4_robustness_detour.pdf"), p_c4,
  #          width = 10, height = 6, units = "in")
  #   cat("[PLOT] criterion4_robustness_detour.pdf written.\n")
  # }
  # 
  # x_ax <- if ("sc_hops" %in% names(c4_top)) "sc_hops"
  # else if ("sc_att" %in% names(c4_top)) "sc_att"
  # else names(c4_top)[1]
  # # ---- Order x-axis levels numerically ----
  # # Values like "10Mbps", "120Mbps", "40Mbps" are character strings.
  # # Sort them by extracting the leading numeric part so the axis reads
  # # 10 Mbps -> 40 Mbps -> 80 Mbps -> 120 Mbps instead of alphabetically.
  # # Falls back to alphabetical sort when no numeric prefix is found.
  # x_vals   <- unique(c4_top[[x_ax]])
  # x_nums   <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", x_vals)))
  # x_levels <- if (all(!is.na(x_nums))) x_vals[order(x_nums)] else sort(x_vals)
  # c4_top[, (x_ax) := factor(get(x_ax), levels = x_levels)]
  # if (nrow(c4_top) > 0) {
  #   p_c4 <- ggplot(c4_top,
  #                  aes_string(x = x_ax, y = "auc",
  #                             color = "family", group = "label")) +
  #     geom_line(alpha  = 0.5, linewidth = 0.5) +
  #     geom_point(alpha = 0.8, size = 1.4) +
  #     geom_hline(yintercept = 0.65, linetype = "dashed",
  #                color = "red", linewidth = 0.4) +
  #     scale_color_manual(values = FAMILY_COLORS, name = "Feature family") +
  #     scale_y_continuous(limits = c(0.4, 1), breaks = seq(0.4, 1, 0.1)) +
  #     labs(
  #       title    = "Criterion 4 — Robustness across NS-3 scenarios (Top 20 features)",
  #       subtitle = paste0(
  #         "Each line = one feature across all scenario conditions. ",
  #         "\nRed dashed line: AUC = 0.65. ",
  #         "\nFlat lines indicate robust features. \n",
  #         sum(c4$robust, na.rm = TRUE), "/", nrow(c4),
  #         " features robust (AUC SD < 0.10 and mean AUC > 0.65)."
  #       ),
  #       x = "Path length (Number of router)",
  #       y = "AUC-ROC per scenario"
  #     ) +
  #     TH +
  #     theme()#axis.text.x = element_text(angle = 45, hjust = 1))
  #   ggsave(file.path(ANA_OUTPUT_DIR, "criterion4_robustness_path.pdf"), p_c4,
  #          width = 10, height = 6, units = "in")
  #   cat("[PLOT] criterion4_robustness_path.pdf written.\n")
  # }
  if (nrow(c4_top) > 0) {
    if ("sc_rate" %in% names(c4_top))
      plot_robustness_axis(c4_top, "sc_rate",
                           "Parasite rate (Mbps)",                 "rate")
    if ("sc_hops" %in% names(c4_top))
      plot_robustness_axis(c4_top, "sc_hops",
                           "Path length (Number of routers)",       "path")
    if ("sc_att" %in% names(c4_top))
      plot_robustness_axis(c4_top, "sc_att",
                           "Number of additional on-detour routers", "detour")
  }
}
# ---- Figure: AUC distribution per family — both schemes ----
cat("[PLOT] Figure: AUC per family, both schemes...\n")
{
  # Long-format data with both family schemes stacked for comparison
  dt_manual <- summary_dt[!is.na(auc) & !is.na(family),
                          .(feature, label, auc, n_ok,
                            family_id = family,
                            scheme    = "Manual families (A\u2013M)")]
  dt_data   <- summary_dt[!is.na(auc) & !is.na(data_family),
                          .(feature, label, auc, n_ok,
                            family_id = data_family,
                            scheme    = paste0("Data-driven families (k = ", fam_res$k, ")"))]
  dt_both   <- rbindlist(list(dt_manual, dt_data), fill = TRUE)
  
  # Order families by median AUC within each scheme
  dt_both[, family_id := factor(
    family_id,
    levels = dt_both[, .(med = median(auc, na.rm = TRUE)), by = .(scheme, family_id)
    ][order(scheme, -med), family_id]
  )]
  
  p_fam_auc <- ggplot(dt_both,
                      aes(x = family_id, y = auc, color = factor(n_ok))) +
    geom_hline(yintercept = 0.60, linetype = "dashed",
               color = "gray40", linewidth = 0.4) +
    geom_jitter(width = 0.18, size = 2.2, alpha = 0.8) +
    stat_summary(fun = median, geom = "crossbar",
                 width = 0.5, linewidth = 0.5, color = "black") +
    facet_wrap(~ scheme, scales = "free_x", nrow = 2) +
    scale_color_manual(
      values = c("0" = "#d73027", "1" = "#fc8d59",
                 "2" = "#fee090", "3" = "#91bfdb", "4" = "#4575b4"),
      name   = "Score (criteria met)",
      labels = c("0/4","1/4","2/4","3/4","4/4")
    ) +
    scale_y_continuous(limits = c(0.4, 1), breaks = seq(0.4, 1, 0.1)) +
    labs(
      title    = "AUC-ROC per feature, grouped by family \u2014 Manual vs. Data-driven",
      subtitle = paste0(
        "Each dot = one feature. Black crossbar = median AUC within family. ",
        "Dashed line: AUC = 0.60. ",
        "Dot colour = number of criteria satisfied (0\u20134)."
      ),
      x = "Family", y = "AUC-ROC"
    ) +
    TH +
    theme(axis.text.x  = element_text(angle = 30, hjust = 1),
          strip.text    = element_text(face = "bold"),
          legend.position = "right")
  
  ggsave(file.path(ANA_OUTPUT_DIR, "comparison_auc_per_family.pdf"),
         p_fam_auc, width = 12, height = 10, units = "in")
  cat("[PLOT] comparison_auc_per_family.pdf written.\n")
}

# ---- Figure: Four-criteria heatmap per family — both schemes ----
cat("[PLOT] Figure: Four-criteria heatmap, both schemes...\n")
{
  make_criteria_long <- function(agg_dt, scheme_label) {
    rbindlist(list(
      agg_dt[, .(family_id, criterion = "C1 Reliable (%)",    value = pct_reliable,  scheme = scheme_label)],
      agg_dt[, .(family_id, criterion = "C2 Separates (%)",   value = pct_separates, scheme = scheme_label)],
      agg_dt[, .(family_id, criterion = "C3 Unique (%)",      value = pct_unique,    scheme = scheme_label)],
      agg_dt[, .(family_id, criterion = "C4 Robust (%)",      value = pct_robust,    scheme = scheme_label)],
      agg_dt[, .(family_id, criterion = "Mean AUC",
                 value = mean_auc * 100,  scheme = scheme_label)]
    ))
  }
  
  
  crit_long <- rbindlist(list(
    make_criteria_long(manual_agg, "Manual (A\u2013M)"),
    make_criteria_long(data_agg,   paste0("Data-driven (k=", fam_res$k, ")"))
  ))
  
  p_crit_heat <- ggplot(crit_long,
                        aes(x = family_id, y = criterion, fill = value)) +
    geom_tile(color = "white", linewidth = 0.4) +
    geom_text(aes(label = sprintf("%.0f", value)),
              size = 2.8, color = "gray10") +
    facet_wrap(~ scheme, scales = "free_x", nrow = 2) +
    scale_fill_gradient2(
      low  = "#d73027", mid = "#ffffbf", high = "#1a9850",
      midpoint = 50, limits = c(0, 100),
      name = "% features\n(or AUC×100)"
    ) +
    labs(
      title    = "Four criteria aggregated by family \u2014 Manual vs. Data-driven",
      subtitle = paste0(
        "Cell = % of features in the family satisfying each criterion ",
        "(or mean AUC \xd7 100). ",
        "Green = high performance, red = low."
      ),
      x = "Family", y = NULL
    ) +
    TH +
    theme(axis.text.x  = element_text(angle = 30, hjust = 1),
          strip.text    = element_text(face = "bold"),
          panel.grid    = element_blank())
  
  ggsave(file.path(ANA_OUTPUT_DIR, "comparison_criteria_heatmap.pdf"),
         p_crit_heat, width = 14, height = 10, units = "in")
  cat("[PLOT] comparison_criteria_heatmap.pdf written.\n")
}
# ---- Figure: Cross-tabulation mapping (manual x data-driven) ----
cat("[PLOT] Figure: Family mapping (manual x data-driven)...\n")
if ("data_family" %in% names(summary_dt)) {
  map_long <- summary_dt[!is.na(data_family) & !is.na(family),
                         .N, by = .(family, data_family)]
  map_long[, family      := factor(family,      levels = rev(sort(unique(family))))]
  map_long[, data_family := factor(data_family, levels = sort(unique(data_family)))]
  
  p_mapping <- ggplot(map_long,
                      aes(x = data_family, y = family, fill = N)) +
    geom_tile(color = "white", linewidth = 0.6) +
    geom_text(aes(label = ifelse(N > 0, N, "")),
              size = 3.5, color = "gray10") +
    scale_fill_gradient(low = "white", high = "#2166AC",
                        name = "Number of\nfeatures") +
    labs(
      title    = "Family mapping \u2014 Manual (rows) vs. Data-driven (columns)",
      subtitle = paste0(
        "Each cell = number of features shared between a manual family (A\u2013M) ",
        "and a data-driven family (F1\u2013F", fam_res$k, "). ",
        "Diagonal blocks indicate good agreement between the two schemes."
      ),
      x = paste0("Data-driven family (k = ", fam_res$k, ")"),
      y = "Manual family"
    ) +
    TH +
    theme(panel.grid = element_blank())
  
  ggsave(file.path(ANA_OUTPUT_DIR, "comparison_family_mapping.pdf"),
         p_mapping, width = 9, height = 8, units = "in")
  cat("[PLOT] comparison_family_mapping.pdf written.\n")
}


# ============================================================
#  SECTION 8 — MANUSCRIPT CATALOG (feature_catalog.md)
# ============================================================
cat("[OUT] Generating manuscript catalog...\n")

rates_str <- paste(sort(unique(all_flows$sc_rate)),  collapse = ", ")
hops_str  <- paste(sort(unique(all_flows$sc_hops)),  collapse = ", ")
atts_str  <- paste(sort(unique(all_flows$sc_att)),   collapse = ", ")

lines <- c(
  "# Feature Catalog — Section 3.2",
  "",
  paste0("**Data**: ", nrow(all_flows), " flows of ", ANALYSIS_GROUP,
         " packets each, generated with the same pipeline as `generation_unified.R`."),
  paste0("**NS-3 scenarios**: parasite traffic rate in {", rates_str, "}, ",
         "nb_hops in {", hops_str, "}, ",
         "nb_att (detour routers) in {", atts_str, "}."),
  paste0("**Attack proportion**: ", PROP_ATT * 100, "% of flows."),
  "",
  "## Evaluation Criteria",
  "",
  paste0("1. **Reliability (n=", ANALYSIS_GROUP, ")**: within-class CV (benign flows) < 0.5, ",
         "confirmed by bootstrap (N=", N_BOOTSTRAP, ") on raw NS-3 packets."),
  "2. **Separation**: AUC-ROC >= 0.60 and two-sided Wilcoxon test p < 0.05.",
  "3. **Informational contribution**: maximum Spearman correlation with any other feature |rho| < 0.85.",
  "4. **Robustness**: AUC standard deviation across scenarios < 0.10 and mean AUC > 0.65.",
  "",
  "---", ""
)

# ── Family comparison section in the markdown ──────────────────────────────
lines <- c(lines,
           "---", "",
           "## Family Comparison: Manual vs. Data-driven", "",
           paste0(
             "Features were grouped using two complementary schemes. ",
             "The **manual scheme** (columns A\u2013M in the feature catalog) reflects ",
             "a-priori domain knowledge about the mathematical nature of each estimator. ",
             "The **data-driven scheme** groups features by proximity in Spearman correlation ",
             "space (hierarchical clustering, Ward D2 linkage, k = ", fam_res$k,
             " families selected by maximum average silhouette width = ",
             round(max(fam_res$sil_scores, na.rm=TRUE), 3), "). ",
             "The two schemes are compared below; the cross-tabulation figure ",
             "(`comparison_family_mapping.pdf`) shows which manual families correspond to ",
             "which data-driven families."
           ),
           ""
)

# Manual family aggregate table in markdown
lines <- c(lines,
           "### Manual families — aggregated criteria", "",
           "| Family | n | C1 Reliable (%) | C2 Separates (%) | mean AUC | C3 Unique (%) | C4 Robust (%) | Mean score |",
           "|--------|:-:|:---------------:|:----------------:|:--------:|:-------------:|:-------------:|:----------:|"
)
for (i in seq_len(nrow(manual_agg))) {
  r <- manual_agg[i]
  lines <- c(lines, paste0(
    "| ", r$family_id,
    " | ", r$n_features,
    " | ", r$pct_reliable, "%",
    " | ", r$pct_separates, "%",
    " | ", r$mean_auc,
    " | ", r$pct_unique, "%",
    " | ", r$pct_robust, "%",
    " | ", r$mean_n_ok, "/4 |"
  ))
}

# Data-driven family aggregate table in markdown
lines <- c(lines,
           "", "### Data-driven families — aggregated criteria", "",
           "| Family | n | C1 Reliable (%) | C2 Separates (%) | mean AUC | C3 Unique (%) | C4 Robust (%) | Mean score | Features |",
           "|--------|:-:|:---------------:|:----------------:|:--------:|:-------------:|:-------------:|:----------:|---------|"
)
for (i in seq_len(nrow(data_agg))) {
  r <- data_agg[i]
  lines <- c(lines, paste0(
    "| ", r$family_id,
    " | ", r$n_features,
    " | ", r$pct_reliable, "%",
    " | ", r$pct_separates, "%",
    " | ", r$mean_auc,
    " | ", r$pct_unique, "%",
    " | ", r$pct_robust, "%",
    " | ", r$mean_n_ok, "/4",
    " | *", r$features_list, "* |"
  ))
}
lines <- c(lines, "", "---", "")


# Group entries by data-driven family (F1, F2, ...)
for (grp in sort(unique(summary_dt$data_family))) {
  feats_grp <- summary_dt[data_family == grp & !is.na(data_family)]
  if (nrow(feats_grp) == 0) next
  n_in_grp  <- nrow(feats_grp)
  mean_auc  <- round(mean(feats_grp$auc, na.rm = TRUE), 3)
  lines <- c(lines,
             paste0("## Data-driven family ", grp,
                    "  (n=", n_in_grp, " features, mean AUC=", mean_auc, ")"),
             "")
  for (i in seq_len(nrow(feats_grp))) {
    row <- feats_grp[i]
    fi  <- feat_catalog[[which(sapply(feat_catalog, `[[`, "name") == row$feature)[1]]]
    if (is.null(fi)) next
    
    ck  <- function(x) if (isTRUE(x)) "**Yes**" else "No"
    fmt <- function(x, f = "%.4f") if (is.na(x)) "N/A" else sprintf(f, x)
    
    lines <- c(lines,
               paste0("### `", row$feature, "`"),
               "",
               paste0("- **Models**: ", fi$models),
               paste0("- **Definition**: ", fi$definition),
               paste0("- **Physical rationale**: ", fi$hypothesis),
               "",
               "| Criterion | Status | Key value(s) |",
               "|-----------|:------:|-------------|",
               paste0("| (1) Reliability n=", ANALYSIS_GROUP, " | ", ck(row$reliable),
                      " | CV_flow=", fmt(row$cv_flow, "%.3f"),
                      ", CV_boot=", fmt(row$cv_boot, "%.3f"), " |"),
               paste0("| (2) Separation | ", ck(row$separates),
                      " | AUC=", fmt(row$auc, "%.3f"),
                      ", Cohen d=", fmt(row$cohen_d, "%.2f"),
                      " — mu_benign=", fmt(row$mean_benign, "%.5f"),
                      ", mu_detour=", fmt(row$mean_attack, "%.5f"),
                      " (", if (!is.na(row$direction)) row$direction else "?", ") |"),
               paste0("| (3) Unique information | ", ck(row$unique_info),
                      " | rho_max=", fmt(row$rho_max, "%.3f"), " |"),
               paste0("| (4) Robustness | ", ck(row$robust),
                      " | mean AUC=", fmt(row$auc_mean, "%.3f"),
                      " +/- ", fmt(row$auc_sd, "%.3f"),
                      " [", fmt(row$auc_min, "%.3f"), ", ", fmt(row$auc_max, "%.3f"), "] |"),
               "",
               paste0("> **Summary**: ", row$n_ok, "/4 criteria met — ",
                      paste(Filter(Negate(is.null), list(
                        if (isTRUE(row$reliable))    "reliable",
                        if (isTRUE(row$separates))   "discriminative",
                        if (isTRUE(row$unique_info)) "non-redundant",
                        if (isTRUE(row$robust))      "robust"
                      )), collapse = ", "),
                      if (row$n_ok == 0) "no criterion met." else "."),
               ""
    )
  }
}

# Global summary table
lines <- c(lines, "---", "", "## Summary Table", "",
           "| Feature | Manual family | Data family | C1 Reliable | C2 Separation (AUC) | C3 Unique | C4 Robust | Score |",
           "|---------|:-------------:|:-----------:|:-----------:|:-------------------:|:---------:|:---------:|:-----:|"
)
for (i in seq_len(nrow(summary_dt))) {
  r <- summary_dt[i]
  a <- if (!is.na(r$auc)) sprintf("%.2f", r$auc) else "N/A"
  lines <- c(lines, paste0(
    "| `", r$feature, "` | ", r$family,
    " | ", if (!is.na(r$data_family)) r$data_family else "—",
    " | ", if (isTRUE(r$reliable))    "Yes" else "No",
    " | ", if (isTRUE(r$separates))   paste0("Yes (", a, ")") else paste0("No (", a, ")"),
    " | ", if (isTRUE(r$unique_info)) "Yes" else "No",
    " | ", if (isTRUE(r$robust))      "Yes" else "No",
    " | **", r$n_ok, "/4** |"
  ))
}

# Methodology notes
lines <- c(lines,
           "", "---", "", "## Methodology Notes", "",
           paste0("### Criterion 1 — Reliability at n = ", ANALYSIS_GROUP, " packets"),
           "",
           paste0(
             "Each flow-level record in `all_flows` aggregates exactly ", ANALYSIS_GROUP,
             " consecutive raw packets using `mix_to_flow_fast()` with `group = ", ANALYSIS_GROUP,
             "`, which is identical to the production pipeline in `generation_unified.R`. ",
             "The **within-class coefficient of variation** (CV = sigma/mu) is computed ",
             "on benign flows. A CV below 0.5 indicates that the feature fluctuates by ",
             "less than 50% of its mean value across independent 9-packet windows, ",
             "making it estimable reliably from a single short observation window. ",
             "This constraint is critical for early detection: the classifier should be ",
             "able to make a decision as soon as the first 9 packets of a flow arrive. ",
             "A complementary bootstrap analysis draws ", N_BOOTSTRAP,
             " consecutive windows of ", ANALYSIS_GROUP,
             " raw packets from the NS-3 packet trace, recomputes each feature, ",
             "and measures the CV of the result."
           ),
           "",
           "### Criterion 2 — Separation",
           "",
           paste0(
             "Discriminative power is measured by the **AUC-ROC** (area under the Receiver ",
             "Operating Characteristic curve), which equals the normalised Mann-Whitney-Wilcoxon ",
             "statistic P(f_detour > f_benign). AUC = 0.5 corresponds to a random classifier; ",
             "AUC = 1.0 to perfect separation. The symmetric AUC (max(AUC, 1-AUC) >= 0.5) is ",
             "used because some features decrease rather than increase under attack ",
             "(e.g., lambda_hat). The AUC threshold is set at 0.60: even a moderately ",
             "discriminative feature can contribute meaningfully when combined with others in ",
             "a multi-feature kernel or logistic model. The two-sided Wilcoxon test (alpha = ",
             ALPHA, ") and Cohen's d (d >= 0.2 small, 0.5 medium, 0.8 large) are also reported."
           ),
           "",
           "### Criterion 3 — Informational contribution",
           "",
           paste0(
             "Redundancy is assessed by **Spearman rank correlation** (non-parametric, robust ",
             "to the skewed delay distributions). For each feature, its maximum absolute ",
             "Spearman correlation with any other feature (rho_max) is computed. ",
             "A feature is considered to provide unique information if rho_max < 0.85. ",
             "Within-family correlations (e.g. among the various jitter estimators) are ",
             "expected to be high; cross-family correlations should remain low, confirming ",
             "that the families capture complementary aspects of the delay process."
           ),
           "",
           "### Criterion 4 — Robustness across NS-3 scenarios",
           "",
           paste0(
             "The AUC of each feature is computed separately for every combination of ",
             "simulation parameters (parasite traffic rate x nb_hops x nb_att), yielding ",
             "a distribution of AUC values across scenarios. A feature is considered robust ",
             "if its **AUC standard deviation across scenarios** is below 0.10 **and** its ",
             "mean AUC remains above 0.65. This double condition ensures that the feature ",
             "maintains adequate discriminative power and consistent performance across the ",
             "varied network conditions simulated in NS-3, which is a prerequisite for ",
             "generalisation to unseen scenarios."
           ),
           ""
)

writeLines(lines, file.path(ANA_OUTPUT_DIR, "feature_catalog.md"))
cat("[OUT] feature_catalog.md written.\n")


# ============================================================
#  SECTION 9 — CONSOLE SUMMARY
# ============================================================
cat("\n", strrep("=", 65), "\n")
cat("  FEATURE ANALYSIS — SECTION 3.2 SUMMARY\n")
cat(strrep("=", 65), "\n\n")
cat(sprintf("  Pipeline         : generation_unified.R (identical)\n"))
cat(sprintf("  Scenario tag     : %s\n", scenario_tag))
cat(sprintf("  Input CSV        : %s_trace_all_output_stats.csv\n", prefix_m))
cat(sprintf("  Cache directory  : %s\n", CACHE_DIR))
cache_files <- c("collected_data", "c1", "c2", "c3", "c4", "families")
cat("  Cache status:\n")
for (cf in cache_files) {
  p  <- file.path(CACHE_DIR, paste0(cf, ".rds"))
  sz <- if (file.exists(p)) sprintf("%.1f MB", file.size(p)/1e6) else "--- missing ---"
  cat(sprintf("    %-18s : %s\n", cf, sz))
}
cat(sprintf(
  "  RECOMPUTE flags  : DATA=%s C1=%s C2=%s C3=%s C4=%s FAM=%s\n",
  RECOMPUTE_DATA, RECOMPUTE_C1, RECOMPUTE_C2,
  RECOMPUTE_C3,   RECOMPUTE_C4, RECOMPUTE_FAMILIES))
cat(sprintf("  Flows analysed   : %d  (group = %d packets each)\n",
            nrow(all_flows), ANALYSIS_GROUP))
cat(sprintf("  Raw packets kept : %d  (for bootstrap)\n", nrow(all_packets)))
cat(sprintf("  Features defined : %d  (%d available in data)\n",
            length(FEAT_NAMES), length(avail_feats)))
cat("\n")
cat(sprintf("  C1 Reliability   (CV < 0.50)      : %d / %d\n",
            sum(c1$reliable == TRUE, na.rm = TRUE), length(avail_feats)))
cat(sprintf("  C2 Separation    (AUC >= 0.60)    : %d / %d\n",
            sum(c2$separates == TRUE, na.rm = TRUE), length(avail_feats)))
cat(sprintf("  C3 Non-redundant (rho_max < 0.85) : %d / %d\n",
            sum(c3$unique_info == TRUE, na.rm = TRUE), length(avail_feats)))
cat(sprintf("  C4 Robust        (SD_AUC < 0.10)  : %d / %d\n",
            sum(c4$robust == TRUE, na.rm = TRUE), length(avail_feats)))

cat("\n  Top features by overall score (then AUC):\n")
top <- summary_dt[order(-n_ok, -auc)][seq_len(min(15, .N))]
for (k in seq_len(nrow(top))) {
  r <- top[k]
  cat(sprintf("  %2d. %-24s  %d/4  AUC=%-6s  CV=%-6s  rho_max=%-5s\n",
              k, r$feature, r$n_ok,
              if (!is.na(r$auc))     sprintf("%.3f", r$auc)     else "N/A",
              if (!is.na(r$cv_flow)) sprintf("%.3f", r$cv_flow) else "N/A",
              if (!is.na(r$rho_max)) sprintf("%.3f", r$rho_max) else "N/A"))
}

cat("\n  Output directory:", ANA_OUTPUT_DIR, "\n")
cat("    feature_summary.csv\n")
cat("    criterion1_reliability.pdf\n")
cat("    criterion2_separation.pdf\n")
cat("    criterion3_correlation.pdf\n")
cat("    criterion4_robustness_{rate,path,detour}.pdf\n")
cat("    feature_families_dendrogram.pdf\n")
cat("    feature_families_silhouette.pdf\n")
cat("    manual_family_summary.csv\n")
cat("    datadriven_family_summary.csv\n")
cat("    family_mapping.csv\n")
cat("    comparison_auc_per_family.pdf\n")
cat("    comparison_criteria_heatmap.pdf\n")
cat("    comparison_family_mapping.pdf\n")
cat("    feature_catalog.md\n\n")
# Print data-driven family assignments
cat("  Data-driven families (k =", fam_res$k,
    ", mean silhouette =",
    round(max(fam_res$sil_scores, na.rm=TRUE), 3), "):\n")
for (fam in sort(unique(summary_dt$data_family))) {
  members <- summary_dt[data_family == fam & !is.na(data_family),
                        paste(label, collapse=", ")]
  n_mem   <- summary_dt[data_family == fam & !is.na(data_family), .N]
  m_auc   <- summary_dt[data_family == fam & !is.na(data_family),
                        round(mean(auc, na.rm=TRUE), 3)]
  cat(sprintf("    %s (n=%d, AUC=%.3f): %s\n",
              fam, n_mem, m_auc, members))
}

cat(strrep("=", 65), "\n")
cat("[DONE] Analysis complete.\n")



# # ---- Instruction E — Réduction du jeu de variables ----
# library(data.table); library(dendextend); library(pROC)
# 
# # 1. Matrice de correlation de Spearman, comme en section 3.2
# feat <- setdiff(names(dtf_feat), c(remove_col, "t_start", "t_end"))
# M    <- cor(dtf_feat[, ..feat], method = "spearman", use = "pairwise.complete.obs")
# d    <- as.dist(1 - abs(M))
# hc   <- hclust(d, method = "average")
# 
# # 2. AUC individuelle de chaque variable
# auc_one <- sapply(feat, function(f) {
#   v <- dtf_feat[[f]]
#   if (length(unique(v[!is.na(v)])) <= 1) return(NA_real_)
#   as.numeric(pROC::auc(pROC::roc(dtf_feat$attacked, v, quiet = TRUE)))
# })
# 
# # 3. Un representant par groupe : la plus forte AUC
# for (k in c(8, 12, 15)) {
#   grp  <- cutree(hc, k = k)
#   reps <- sapply(split(names(grp), grp), function(g) {
#     a <- auc_one[g]; if (all(is.na(a))) return(NA_character_)
#     names(which.max(abs(a - 0.5)))     # AUC la plus eloignee du hasard
#   })
#   reps <- reps[!is.na(reps)]
#   cat("k =", k, ":", paste(reps, collapse = ", "), "\n")
#   saveRDS(reps, sprintf("reduced_features_k%d.rds", k))
# }