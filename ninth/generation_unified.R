# ============================================================
#  generation_unified.R
#  Remplace generation.R, generation_ondetour.R, generation_ondetour_evolution.R
#  Mode sélectionné par le paramètre -n (detour | path | parasite)
#  et le flag -e (évolution) + -d (trainondetour)
#
#  GAINS:
#   - 3 fichiers de ~1200 lignes → 1 fichier de ~600 lignes
#   - Maintenance en un seul point
#   - Corrections de bugs appliquées une seule fois
# ============================================================

# ---- Setup ----
directory <- "./scratch/ninth/"
source(file = paste0(directory, "real_data.R"))
source(file = paste0(directory, "variation_generator_function.R"))
# --- Uncomment to use the optimized version instead: ---
source(file = paste0(directory, "variation_generator_function_optimized.R"))
source(file = paste0(directory, "model_function.R"))
source(file = paste0(directory, "setup_function.R"))
source(file = paste0(directory, "setup_param.R"))

library(data.table); setDTthreads(percent = 65)
library(cluster); library(digest); library(DescTools); library(e1071)
library(FactoMineR); library(getip); library(ggplot2); library(igraph)
library(isotree); library(tensorflow, exclude = c("shape", "set_random_seed"))
library(keras3); library(magrittr); library(optparse); library(patchwork)
library(randomForest); library(readr); library(rpart); library(sads)
library(stringr); library(xgboost); library(zeallot); library(caret)
library(glmnet)
cat("debug 4")
# ---- Command-line arguments ----
option_list <- list(
  make_option(c("-f", "--file"),            type = "character", default = "ninth"),
  make_option(c("-t", "--simulationTime"),   type = "double",    default = 300),
  make_option(c("-l", "--latency"),          type = "character", default = "5ms"),
  make_option(c("-b", "--bandwidth"),        type = "character", default = "120Mbps"),
  make_option(c("-a", "--dataRateAccess"),   type = "character", default = "10Mbps"),
  make_option(c("-o", "--packetSize"),       type = "integer",   default = 12000),
  make_option(c("-m", "--meanExpo"),         type = "double",    default = 0.5),
  make_option(c("-x", "--meanExpoPara"),     type = "double",    default = 0.5),
  make_option(c("-n", "--name"),             type = "character", default = "path"),
  make_option(c("-g", "--graph"),            type = "logical",   default = FALSE),
  make_option(c("-r", "--repertory"),        type = "character", default = "scratch/ninth"),
  make_option(c("-e", "--evolution"),        type = "logical",   default = FALSE),
  make_option(c("-i", "--trainonparasite"),  type = "character", default = "60Mbps"),
  make_option(c("-d", "--trainondetour"),    type = "character", default = "0"),
  make_option(c("-p", "--trainonpath"),      type = "character", default = "0"),
  make_option(c("-c", "--comment"),          type = "character", default = ""),
  make_option(c("-q", "--do_queue"),         type = "logical", default = FALSE),
  make_option("--trainRepertories",       type = "character", default = "",
              help = "Repertoires supplementaires utilises pour l'entrainement (separes par des virgules). Si non vide, active le mode cross-seed."),
  make_option("--use_temporal_covariates", type = "logical", default = TRUE,
              help = "Ablation des covariables (TRUE  = comportement actuel (t_start et t_end conservés), FALSE = ablation)"),
  make_option("--reducedFeatures", type = "character", default = "",
              help = "Chemin d'un fichier reduced_features_k<k>.rds produit par feature_reduction.R (instruction E). Vide = jeu de variables complet.")
)
cat("debug 2")
opt <- parse_args(OptionParser(option_list = option_list))
cat("debg 1")
use_temporal_covariates <- opt$use_temporal_covariates

# ---- Instruction E : jeu de variables reduit ----------------------------
# La ligne CLI prime sur la valeur eventuellement fixee dans setup_param.R.
# `reduced_feature_set` doit exister (NULL par defaut) ; les fonctions
# do_reg_log(), do_svm(), do_vae() et do_dae() l'appliquent par intersect().
if (!exists("reduced_feature_set")) reduced_feature_set <- NULL
feature_set_tag <- "full"
if (nzchar(opt$reducedFeatures)) {
  if (!file.exists(opt$reducedFeatures))
    stop("[ERROR] --reducedFeatures : fichier introuvable : ", opt$reducedFeatures)
  reduced_feature_set <- readRDS(opt$reducedFeatures)
  if (!is.character(reduced_feature_set) || length(reduced_feature_set) == 0L)
    stop("[ERROR] --reducedFeatures : le RDS ne contient pas un vecteur de noms de variables.")
  feature_set_tag <- sub("\\.rds$", "", basename(opt$reducedFeatures))
  cat("[INFO] Jeu de variables reduit :", feature_set_tag, "|",
      length(reduced_feature_set), "variables :",
      paste(reduced_feature_set, collapse = ", "), "\n")
} else if (!is.null(reduced_feature_set)) {
  feature_set_tag <- "reduced_setup_param"
  cat("[INFO] Jeu de variables reduit herite de setup_param.R :",
      length(reduced_feature_set), "variables\n")
}

cat("[DEBUG] reduced_feature_set:", reduced_feature_set, "\n")
cat ("debug 3")
# ---- Determine mode ----
# Mode "multi_detour" si trainondetour contient "_" (ex: "0_1_3_5_7_9")
split_detour <- strsplit(opt$trainondetour, "_")[[1]]
multi_detour <- length(split_detour) > 1
local_nb_att <- as.integer(split_detour)

cat("[INFO] Mode:", opt$name, "| evolution:", opt$evolution,
    "| multi_detour:", multi_detour, "| detours:", paste(local_nb_att, collapse=","), "\n")

# ---- Paths and prefixes ----
ipaddr <- getip("internal")
pid_suffix <- Sys.getpid()
output_dir <- paste0("./", ipaddr, "/_pid", pid_suffix,"/")
if (!dir.exists(output_dir)) dir.create(output_dir, showWarnings = FALSE)
dir.create(paste0(directory, "model/"), showWarnings = FALSE)

prefix_m <- paste0(
  opt$repertory, "/T", sprintf(opt$simulationTime, fmt = '%#.6f'),
  "s_L", opt$latency, "_B", opt$bandwidth, "_Ra", opt$dataRateAccess,
  "_P", opt$packetSize, "b_Ma", sprintf(opt$meanExpo, fmt = '%#.6f'),
  "_Me", sprintf(opt$meanExpoPara, fmt = '%#.6f'), "_merge_path"
)

path_parts <- strsplit(prefix_m, "/")[[1]]
prefix_rep <- sub(".*(scratch/.*)/[^/]+$", "\\1", prefix_m)
last_part <- tail(path_parts, n = 1)
px <- strsplit(last_part, "_")[[1]]
prefix_time        <- substring(px[1], 2)
prefix_latency     <- substring(px[2], 2)
prefix_bandwidth   <- substring(px[3], 2)
prefix_rateaccess  <- substring(px[4], 3)
prefix_packetlength <- substring(px[5], 2)
prefix_meanexp     <- substring(px[6], 3)
prefix_meanexppara <- substring(px[7], 3)
rm(px)

# ---- Load data ----
merge_stats <- fread(paste0(prefix_m, "_trace_all_output_stats.csv"), sep = ";", verbose = TRUE, showProgress = TRUE, fill = TRUE)
cat("[INFO] Packets:", nrow(merge_stats), "\n")

do_graph  <- isTRUE(opt$graph)
do_queue  <- opt$do_queue  # Activated only when explicitly needed
do_flow   <- opt$do_queue
do_pdf    <- do_graph  # Génère les PDF quand les graphes sont activés
do_print  <- FALSE     # Affichage interactif (FALSE en batch)

if (do_queue) {
  merge_queue     <- fread(paste0(prefix_m, "_queue.csv"), sep = ";", verbose = TRUE, fill = TRUE)
  merge_bandwidth <- fread(paste0(prefix_m, "_bandwidth.csv"), sep = ";", verbose = TRUE, fill = TRUE)
  merge_bandwidth[, hop := factor(hop, levels = ordered_hop, ordered = TRUE)]
}

df <- merge_stats[protocol %in% c("UDP", "17", "TCP")]
rm(merge_stats)
df[, run_id := opt$repertory]    # exécution de test

# cross_seed <- nzchar(opt$trainRepertories)
# if (cross_seed) {
#   #a0_a1[, run_id := opt$repertory]          # exécution de test
#   for (rep_train in strsplit(opt$trainRepertories, ",")[[1]]) {
#     prefix_train <- sub(opt$repertory, rep_train, prefix_m, fixed = TRUE)
#     ms_train <- fread(paste0(prefix_train, "_trace_all_output_stats.csv"),
#                       sep = ";", fill = TRUE)
#     df_train <- ms_train[protocol %in% c("UDP", "17", "TCP")]
#     rm (ms_train)
#     df_train[, run_id := rep_train]
#     df <- rbind (df, df_train)
#     rm (df_train)
#     # a0_a1_train <- build_a0_a1_local(ms_train)    # meme traitement que pour le repertoire courant
#     # a0_a1_train[, run_id := rep_train]
#     # a0_a1 <- rbind(a0_a1, a0_a1_train, fill = TRUE)
#   }
#   current_param$cross_seed  <- TRUE
#   current_param$test_run_id <- opt$repertory
# }


# ---- Build iteration domains ----
src <- "10.1.9.1"
l_proto <- unique(df[["proto"]])
l_nb_hops <- unique(df[, extra_router])
l_nb_att <- unique(df[, extra_detour])
l_parasite_rate <- unique(df[, parasite_rate])

# Filter domains based on scenario name (-n)
if (opt$name %in% c("detour", "path")) {
  l_parasite_rate <- l_parasite_rate[l_parasite_rate %in% c("120Mbps")] #,"60Mbps")] #, "40Mbps")]
}
if (opt$name %in% c("detour", "parasite")) {
  l_nb_hops <- l_nb_hops[l_nb_hops %in% c(0)] #, 5)]
}
if (opt$name %in% c("path", "parasite")) {
  l_nb_att <- l_nb_att[l_nb_att %in% c(0, 1, 3, 5, 7, 9)]
}



# In multi-detour mode, restrict l_nb_att to those specified in -d
if (multi_detour) {
  trainondetour_nb_att <- unique(df[extra_detour %in% local_nb_att, extra_detour])
  l_nb_att <- unique(df[, extra_detour])  # iterate over ALL for test
}

if (opt$evolution) {
  l_parasite_rate <- unique(c(opt$trainonparasite, l_parasite_rate))
  l_nb_hops <- unique(c(as.integer(strsplit(opt$trainonpath, "_")[[1]]), l_nb_hops))
  l_nb_att <- unique(c(local_nb_att, l_nb_att))
}

if (opt$reducedFeatures!= "") {
  l_parasite_rate <- c("120Mbps")
  l_nb_hops <- c(0)
  l_nb_att <- c(0)
}

cat("[INFO] parasite_rate:", paste(l_parasite_rate, collapse=","), "\n")
cat("[INFO] nb_hops:", paste(l_nb_hops, collapse=","), "\n")
cat("[INFO] nb_att:", paste(l_nb_att, collapse=","), "\n")

# ---- Models & params ----
set.seed(1997)
models <- models_list[c(8, 10, 15, 16, 22, 23)]

main_params <- list(
  prop_att = c(0.1), 
  models = models, 
  do_pca = FALSE,
  store_test = FALSE, 
  testattheend = TRUE,
  my_seed = opt$repertory, 
  do_evolution = opt$evolution,
  trainonparasite = opt$trainonparasite,
  trainondetour = opt$trainondetour,
  trainonpath = opt$trainonpath,
  comment = opt$comment
)
prop_att <- main_params$prop_att
size_group <- c(9) #,27, 342) # 342, 27, 
output_sim <- paste0(output_dir, "_sim", prefix_time, "_/")
dir.create(output_sim, showWarnings = FALSE)

# ============================================================
#  HELPER: build a0_a1 dataset for a given nb_att value
# ============================================================
build_a0_a1_local <- function(df_h, df_d, nb_hops_val, nb_att_val, parasite_rate_val, proto_val, prefix_a0a1 = prefix_rep) {
  prefix <- paste0(
    prefix_a0a1, "/T", prefix_time, "_h", nb_hops_val, "_a", nb_att_val,
    "_L", prefix_latency, "_B", prefix_bandwidth,
    "_Ra", prefix_rateaccess, "_Re", parasite_rate_val,
    "_P", prefix_packetlength, "_", proto_val,
    "_Ma", prefix_meanexp, "_Me", prefix_meanexppara, "_"
  )
  
  check_file <- function(dt, file_suffix) {
    subset <- dt[file == paste0(prefix, file_suffix)]
    if (nrow(subset) == 0) {
      cat("[WARN] Missing:", prefix, file_suffix, "\n")
      return(NULL)
    }
    subset
  }
  
  a0_H <- check_file(df_h, "trace-access0-access_access0-0-0.pcap")
  a1_H <- check_file(df_h, "trace-dist1-access1-direct_access1-1-0.pcap")
  a0_D <- check_file(df_d, "trace-access0-access_access0-0-0.pcap")
  a1_D <- check_file(df_d, "trace-dist1-access1-detour_access1-1-1.pcap")
  
  if (is.null(a0_H) || is.null(a1_H) || is.null(a0_D) || is.null(a1_D)) return(NULL)
  
  n_H <- min(nrow(a1_H), nrow(a0_H))
  n_D <- min(nrow(a1_D), nrow(a0_D))
  
  cat ("[URGENT] difference in dataset healthy size:", nrow(a1_H)- nrow(a0_H), "\n")
  cat ("[URGENT] difference in dataset detour size:", nrow(a1_D)- nrow(a0_D), "\n")
  
  a0_a1_H <- fusion_starttoend(end = a1_H[1:n_H], start = a0_H[1:n_H], "healthy")
  a0_a1_D <- fusion_starttoend(end = a1_D[1:n_D], start = a0_D[1:n_D], "detour")
  
  a0_a1 <- rbindlist(list(a0_a1_D, a0_a1_H))
  a0_a1[, c("start_file", "end_file", "source_file", "start_packet_num") := NULL]
  
  lookup <- c(t_start = "start_timestamp", packet_length = "length",
              attacked = "type", delay = "delay_path", t_end = "end_timestamp")
  old_n <- unname(lookup); new_n <- names(lookup)
  setnames(a0_a1, old = old_n[old_n %in% names(a0_a1)], new = new_n[old_n %in% names(a0_a1)])
  a0_a1[, attacked := fifelse(attacked == "detour", 1L, 0L)]
  a0_a1[, attacked := factor(attacked)]
  a0_a1
}

# ============================================================
#  HELPER: Graphiques de délais et queues → PDF
# ============================================================
generate_delay_graphs <- function(a0_a1, graph_prefix, 
                                  local_proto, local_nb_hops, local_nb_att, local_parasite_rate) {
  
  cat("[GRAPH] Génération des graphes pour", graph_prefix, "\n")
  
  # ---- Delay scatter plots ----
  delaya0a1 <- ggplot(a0_a1, aes(x = t_start, y = delay, color = attacked, shape = attacked)) +
    geom_point(size = 1) +
    labs(title = paste0(graph_prefix, "\nDelay between A0 and A1"),
         x = "Timestamps (s)", y = "Delay (s)", color = "attacked") +
    ylim(c(0, max(a0_a1$delay))) +
    xlim(c(0, max(a0_a1$t_start))) +
    scale_color_manual(values = c("1" = "#D55E00", "0" = "#56B4E9")) +
    scale_shape_manual(values = c("1" = 3, "0" = 4)) +
    theme_minimal()
  
  logdelaya0a1 <- ggplot(a0_a1, aes(x = t_start, y = log10(delay), color = attacked, shape = attacked)) +
    geom_point(size = 1) +
    labs(title = paste0(graph_prefix, "\nLog Delay between A0 and A1"),
         x = "Timestamps (s)", y = "Log10(delay)", color = "attacked") +
    ylim(c(min(log10(a0_a1$delay)), max(log10(a0_a1$delay)))) +
    xlim(c(0, max(a0_a1$t_start))) +
    scale_color_manual(values = c("1" = "#D55E00", "0" = "#56B4E9")) +
    scale_shape_manual(values = c("1" = 3, "0" = 4)) +
    theme_minimal()
  
  # ---- Queue plots (si do_queue et données disponibles) ----
  queued0d1 <- queued0d2 <- queuea1_d1_direct <- queuea1_d1_detour <- NULL
  queued1_a1_direct <- queued1_a1_detour <- grate <- queued2d1 <- NULL
  
  if (do_queue && exists("merge_queue", envir = .GlobalEnv)) {
    mq <- get("merge_queue", envir = .GlobalEnv)
    tmp_rate_queue <- mq[proto == local_proto & extra_router == local_nb_hops & 
                           extra_detour == local_nb_att & parasite_rate == local_parasite_rate]
    
    if (nrow(tmp_rate_queue) > 0) {
      max_inqueue <- max(tmp_rate_queue[hop %in% c("D0 - linked D1", "D0 - linked D2", "D1 - linked A1", "D2 - linked D1"), nb_inqueue], na.rm = TRUE)
      
      q_d0_d1 <- tmp_rate_queue[hop == "D0 - linked D1"]
      if (nrow(q_d0_d1) > 0) {
        queued0d1 <- ggplot(q_d0_d1, aes(x = time, y = nb_inqueue)) +
          geom_line(linewidth = 0.2) + geom_point(shape = 4, size = 0.5) +
          labs(title = paste0(graph_prefix, "\nQueue D0→D1"), x = "Timestamps (s)", y = "Queue size (number fo packets)") +
          xlim(c(0, max(q_d0_d1$time))) + ylim(0, max_inqueue) + theme_minimal()
      }
      
      q_d0_d2 <- tmp_rate_queue[hop == "D0 - linked D2"]
      if (nrow(q_d0_d2) > 0) {
        queued0d2 <- ggplot(q_d0_d2, aes(x = time, y = nb_inqueue)) +
          geom_line(linewidth = 0.2) + geom_point(shape = 4, size = 0.5) +
          labs(title = paste0(graph_prefix, "\nQueue D0→D2"), x = "Timestamps (s)", y = "Queue size (number fo packets)") +
          xlim(c(0, max(q_d0_d2$time))) + ylim(0, max_inqueue) + theme_minimal()
      }
      
      q_d2_d1 <- tmp_rate_queue[hop == "D2 - linked D1"]
      if (nrow(q_d2_d1) > 0) {
        queued2d1 <- ggplot(q_d2_d1, aes(x = time, y = nb_inqueue)) +
          geom_line(linewidth = 0.2) + geom_point(shape = 4, size = 0.5) +
          labs(title = paste0(graph_prefix, "\nQueue D2→D1"), x = "Timestamps (s)", y = "Queue size (number fo packets)") +
          xlim(c(0, max(q_d2_d1$time))) + ylim(0, max_inqueue) + theme_minimal()
      }
      
      q_a1_d1 <- tmp_rate_queue[hop == "A1 - linked D1"]
      q_a1_d1_dir <- q_a1_d1[path == "direct"]
      if (nrow(q_a1_d1_dir) > 0) {
        queuea1_d1_direct <- ggplot(q_a1_d1_dir, aes(x = time, y = nb_inqueue)) +
          geom_line(linewidth = 0.2) + geom_point(shape = 4, size = 0.5) +
          labs(title = paste0(graph_prefix, "\nQueue A1→D1 (direct)"), x = "Timestamps (s)", y = "Queue size (number fo packets)") +
          xlim(c(0, max(q_a1_d1_dir$time))) + ylim(0, max_inqueue) + theme_minimal()
      }
      q_a1_d1_det <- q_a1_d1[path == "detour"]
      if (nrow(q_a1_d1_det) > 0) {
        queuea1_d1_detour <- ggplot(q_a1_d1_det, aes(x = time, y = nb_inqueue)) +
          geom_line(linewidth = 0.2) + geom_point(shape = 4, size = 0.5) +
          labs(title = paste0(graph_prefix, "\nQueue A1→D1 (detour)"), x = "Timestamps (s)", y = "Queue size (number fo packets)") +
          xlim(c(0, max(q_a1_d1_det$time))) + ylim(0, max_inqueue) + theme_minimal()
      }
      
      q_d1_a1 <- tmp_rate_queue[hop == "D1 - linked A1"]
      q_d1_a1_dir <- q_d1_a1[path == "direct"]
      if (nrow(q_d1_a1_dir) > 0) {
        queued1_a1_direct <- ggplot(q_d1_a1_dir, aes(x = time, y = nb_inqueue)) +
          geom_line(linewidth = 0.2) + geom_point(shape = 4, size = 0.5) +
          labs(title = paste0(graph_prefix, "\nQueue D1→A1 (direct)"), x = "Timestamps (s)", y = "Queue size (number fo packets)") +
          xlim(c(0, max(q_d1_a1_dir$time))) + ylim(0, max_inqueue) + theme_minimal()
      }
      q_d1_a1_det <- q_d1_a1[path == "detour"]
      if (nrow(q_d1_a1_det) > 0) {
        queued1_a1_detour <- ggplot(q_d1_a1_det, aes(x = time, y = nb_inqueue)) +
          geom_line(linewidth = 0.2) + geom_point(shape = 4, size = 0.5) +
          labs(title = paste0(graph_prefix, "\nQueue D1→A1 (detour)"), x = "Timestamps (s)", y = "Queue size (number fo packets)") +
          xlim(c(0, max(q_d1_a1_det$time))) + ylim(0, max_inqueue) + theme_minimal()
      }
    }
    
    # ---- Data rate plot ----
    if (exists("merge_bandwidth", envir = .GlobalEnv)) {
      mb <- get("merge_bandwidth", envir = .GlobalEnv)
      tmp_rate_bw <- mb[proto == local_proto & extra_router == local_nb_hops &
                          extra_detour == local_nb_att & parasite_rate == local_parasite_rate]
      if (nrow(tmp_rate_bw) > 0) {
        grate <- ggplot(tmp_rate_bw, aes(x = hop, y = data_rate_bps, color = path)) +
          geom_point(shape = 4, size = 1) + geom_path(group = tmp_rate_bw$path) +
          labs(title = paste0(graph_prefix, "\nData Rate by hops"), x = "Hop", y = "Data Rate (Mbps)") +
          theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1))
      }
    }
  }
  
  # ---- Flowchart (si activé) ----
  gflowchart <- NULL
  if (do_flow && exists("merge_bandwidth", envir = .GlobalEnv)) {
    mb <- get("merge_bandwidth", envir = .GlobalEnv)
    tmp_rate_bw <- mb[proto == local_proto & extra_router == local_nb_hops &
                        extra_detour == local_nb_att & parasite_rate == local_parasite_rate]
    if (nrow(tmp_rate_bw) > 0) {
      gflowchart <- tryCatch(do_flowchart(tmp_rate_bw, local_nb_hops, local_nb_att), error = function(e) NULL)
    }
  }
  
  # ---- Affichage interactif ----
  if (do_print) {
    print(delaya0a1)
    print(logdelaya0a1)
    if (!is.null(queued0d1)) print(queued0d1)
    if (!is.null(queued0d2)) print(queued0d2)
    if (!is.null(grate)) print(grate)
    if (!is.null(gflowchart)) print(gflowchart)
  }
  
  # ---- Export PDF ----
  if (do_pdf) {
    # Page 1 : delay + queue D0
    if (do_queue && !is.null(queued0d2) && !is.null(queued0d1)) {
      page1 <- queued0d2 / delaya0a1 / queued0d1
    } else {
      page1 <- logdelaya0a1 / delaya0a1
    }
    
    # Page 2 : delay + queue D1-A1
    if (do_queue && !is.null(queued1_a1_detour) && !is.null(queued1_a1_direct)) {
      page2 <- queued1_a1_detour / logdelaya0a1 / queued1_a1_direct
    } else {
      page2 <- delaya0a1 / logdelaya0a1
    }
    
    # Page 3 : delay + queue A1-D1
    if (do_queue && !is.null(queuea1_d1_detour) && !is.null(queuea1_d1_direct)) {
      page3 <- queuea1_d1_detour / delaya0a1 / queuea1_d1_direct
    } else {
      page3 <- logdelaya0a1 / delaya0a1
    }
    # Page 4 : delay + queue D2-D1
    if (do_queue && !is.null(queued2d1) && !is.null(queued2d1)) {
      page4 <- queued2d1 / delaya0a1 / queued2d1
    } else {
      page4 <- logdelaya0a1 / delaya0a1
    }
    
    pdf_path <- paste0(graph_prefix, "page_synthese_graphes.pdf")
    pdf(pdf_path, width = 8.27, height = 11.69, compress = TRUE, pointsize = 5)
    print(page1)
    print(page2)
    print(page3)
    print(page4)
    if (!is.null(grate))      print(grate)
    if (!is.null(gflowchart)) print(gflowchart)
    dev.off()
    cat("[GRAPH] PDF sauvegardé:", pdf_path, "\n")
  }
}


# ============================================================
#  MAIN LOOPS
# ============================================================
for (proto in l_proto) {
  cat("\n[PROTO]", proto, "\n")
  local_proto <- proto
  tmp_proto <- df[proto == local_proto]
  if (nrow(tmp_proto) == 0) next
  
  for (nb_hops in l_nb_hops) {
    cat("[PROTO]", proto, " [HOPS]", nb_hops, "\n")
    local_nb_hops <- nb_hops
    tmp_hop <- tmp_proto[extra_router == local_nb_hops]
    if (nrow(tmp_hop) == 0) next
    
    # Determine which att values to iterate over
    if (multi_detour) {
      att_plans <- list(list(label = opt$trainondetour, att_vec = trainondetour_nb_att))
      # In evolution mode, also test each individual att value
      if (opt$evolution) {
        for (a in setdiff(l_nb_att, trainondetour_nb_att)) {
          att_plans <- c(att_plans, list(list(label = as.character(a), att_vec = as.integer(a))))
        }
      }
    } else {
      att_plans <- lapply(l_nb_att, function(a) list(label = as.character(a), att_vec = as.integer(a)))
    }
    print(paste("att_plans: ",att_plans))
    for (plan in att_plans) {  # ca a l'air d'etre bon.
      nb_att_label <- plan$label
      current_att_vec <- plan$att_vec
      cat("[PROTO]", proto, " [HOPS]", nb_hops, " [ATT]", nb_att_label, "\n")
      
      tmp_att <- tmp_hop[extra_detour %in% current_att_vec]
      if (nrow(tmp_att) == 0) next
      
      for (parasite_rate in l_parasite_rate) {
        cat("[PROTO]", proto, " [HOPS]", nb_hops, " [ATT]", nb_att_label, " [RATE]", parasite_rate, "\n")
        local_parasite_rate <- parasite_rate
        tmp_rate <- tmp_att[parasite_rate == local_parasite_rate]
        if (nrow(tmp_rate) == 0) next
        
        df_healthy <- tmp_rate[src_ip == src & dst_ip == "10.1.2.1"]
        df_detour  <- tmp_rate[src_ip == src & dst_ip == "10.1.3.1"]
        if (nrow(df_healthy) == 0 || nrow(df_detour) == 0) next
        
        # ---- Build a0_a1 for each att value, then combine ----
        recap <- data.table()
        for (att_val in current_att_vec) { # ca a l'air d'etre bon.
          dt <- build_a0_a1_local(df_healthy, df_detour, nb_hops, att_val, parasite_rate, proto)
          if (!is.null(dt) && nrow(dt) > 0) recap <- rbind(recap, dt, fill = TRUE)
        }
        if (nrow(recap) == 0) next
        a0_a1 <- recap
        rm(recap); gc()
        
        # ---- Current params snapshot ----
        current_param <- list(
          simulation_time = unique(a0_a1[, simulation_time]),
          latency = unique(a0_a1[, latency]),
          bandwidth = unique(a0_a1[, bandwidth]),
          data_rate = unique(a0_a1[, data_rate]),
          parasite_rate = unique(a0_a1[, parasite_rate]),
          meanexp = unique(a0_a1[, meanexp]),
          parasite_meanexp = unique(a0_a1[, meanexppara]),
          nb_packets = nrow(df_healthy),
          nb_hops = nb_hops, nb_att = nb_att_label,
          prop = 0.1, group = 9, model = models[[1]]$name,
          proto = proto, do_pca = FALSE, testattheend = TRUE,
          comment = opt$comment, 
          my_seed = opt$repertory,
          do_evolution = opt$evolution,
          trainonparasite = opt$trainonparasite,
          trainondetour = opt$trainondetour,
          trainonpath = opt$trainonpath
        )
        
        
        
        
        
        # ---- Graphiques de délais (si -g TRUE) ----
        if (do_graph) {
          # Construire le prefix pour le nom du PDF (un par att_val en multi-detour, ou un seul)
          for (att_val_graph in current_att_vec) {
            graph_prefix <- paste0(
              prefix_rep, "/T", prefix_time, "_h", nb_hops, "_a", att_val_graph,
              "_L", prefix_latency, "_B", prefix_bandwidth,
              "_Ra", prefix_rateaccess, "_Re", parasite_rate,
              "_P", prefix_packetlength, "_", proto,
              "_Ma", prefix_meanexp, "_Me", prefix_meanexppara, "_"
            )
            # Subset a0_a1 pour cet att_val si multi-detour, sinon tout
            if (length(current_att_vec) > 1 && "extra_detour" %in% names(a0_a1)) {
              a0_a1_sub <- a0_a1[extra_detour == att_val_graph]
            } else {
              a0_a1_sub <- a0_a1
            }
            if (nrow(a0_a1_sub) > 0) {
              tryCatch(
                generate_delay_graphs(a0_a1_sub, graph_prefix,
                                      proto, nb_hops, att_val_graph, parasite_rate),
                error = function(e) cat("[GRAPH ERROR]", conditionMessage(e), "\n")
              )
            }
          }
        }
        
        
        
        # ---- Prop / Group / Model loops ----
        for (prop in prop_att) {
          current_param$prop <- prop
          if (!opt$evolution) {
            current_param$trainonparasite <- current_param$parasite_rate
            current_param$trainondetour   <- current_param$nb_att
            current_param$trainonpath     <- current_param$nb_hops
          }
          
          tmp_meta <- data.table(
            simulation_time = current_param$simulation_time,
            latency = current_param$latency, 
            bandwidth = current_param$bandwidth,
            data_rate = current_param$data_rate, 
            parasite_rate = current_param$parasite_rate,
            meanexp = current_param$meanexp, 
            parasite_meanexp = current_param$parasite_meanexp,
            prop_att = prop, 
            protocol = current_param$proto,
            do_evolution = current_param$do_evolution,
            trainonparasite = current_param$trainonparasite,
            trainondetour = current_param$trainondetour,
            trainonpath = current_param$trainonpath
          )
          cat ("[DEBUG] run_id in a0a1:", "run_id" %in% names(a0_a1), "\n")
          for (group in size_group) {
            current_param$group <- group
            cat("[PROTO]", proto, " [HOPS]", nb_hops, " [ATT]", nb_att_label, " [RATE]", parasite_rate, " [GROUP]", group, "\n")
            
            output_path <- paste0(output_dir, "_sim", prefix_time,
                                  "/_proto", proto, "/_hops", nb_hops,
                                  "/_att", nb_att_label, "/_rate", parasite_rate,
                                  "/_prop", prop, "/_group", group, "/")
            dir.create(output_path, recursive = TRUE, showWarnings = FALSE)
            
            # ---- Build flow dataset ----
            if (nrow(a0_a1[attacked == 0]) == 0 || nrow(a0_a1[attacked == 1]) == 0) next
            
            # If multi-detour, mix per detour value then combine
            if (multi_detour) {
              dtf <- data.table()
              for (att_val in current_att_vec) {
                d0 <- a0_a1[attacked == 0 & extra_detour == att_val]
                d1 <- a0_a1[attacked == 1 & extra_detour == att_val]
                if (d0[, .N] == 0 || d1[, .N] == 0) next
                dtf_chunk <- mix_to_flow_fast(dtf_att0 = d0, dtf_attn = d1, prop = prop, group)
                # Replace with: mix_to_flow(...) for optimized version instead of mix_to_flow
                dtf <- rbind(dtf, dtf_chunk)
              }
            } else {
              dtf <- mix_to_flow_fast(
                dtf_att0 = a0_a1[attacked == 0],
                dtf_attn = a0_a1[attacked == 1],
                prop = prop, group
              )
              # Replace with: mix_to_flow_fast(...) for optimized version instead of mix_to_flow
            }
            cat ("[DEBUG] run_id in dtf:", "run_id" %in% names(dtf), "\n")
            if (is.null(dtf) || nrow(dtf) == 0) next
            
            real_prop <- dtf[, mean(attacked == 1)]
            if (abs(real_prop - prop) > 0.01) next
            
            tmp_group <- copy(tmp_meta)
            tmp_group[, size_group := group]
            
            cross_seed <- nzchar(opt$trainRepertories)
            dtf[, run_id := opt$repertory]          # exécution de test
            
            # ---- Cross seed ----
            if (cross_seed) {
              
              for (rep_train in strsplit(opt$trainRepertories, ",")[[1]]) {
                prefix_train <- sub(opt$repertory, rep_train, prefix_m, fixed = TRUE)
                cat ("[CROSSSEED] chargement:", prefix_train, "\n")
                ms_train <- fread(paste0(prefix_train, "_trace_all_output_stats.csv"),
                                  sep = ";", fill = TRUE)
                df_train <- ms_train[protocol %in% c("UDP", "17", "TCP")]
                rm (ms_train)
                
                tmp_proto_train <- df_train[proto == local_proto]
                rm (df_train)
                if (nrow(tmp_proto_train) == 0) next
                tmp_hop_train <- tmp_proto_train[extra_router == local_nb_hops]
                rm (tmp_proto_train)
                if (nrow(tmp_hop_train) == 0) next
                tmp_att_train <- tmp_hop_train[extra_detour %in% current_att_vec]
                rm (tmp_hop_train)
                if (nrow(tmp_att_train) == 0) next
                tmp_rate_train <- tmp_att_train[parasite_rate == local_parasite_rate]
                rm (tmp_att_train)
                if (nrow(tmp_rate_train) == 0) next
                df_healthy_train <- tmp_rate_train[src_ip == src & dst_ip == "10.1.2.1"]
                df_detour_train  <- tmp_rate_train[src_ip == src & dst_ip == "10.1.3.1"]
                rm (tmp_rate_train)
                if (nrow(df_healthy_train) == 0 || nrow(df_detour_train) == 0) next
                recap_train <- data.table()
                for (att_val in current_att_vec) { # ca a l'air d'etre bon.
                  dt_train <- build_a0_a1_local(df_healthy_train, df_detour_train, nb_hops, att_val, parasite_rate, proto, prefix_a0a1 = sub(".*(scratch/.*)/[^/]+$", "\\1", prefix_train))
                  if (!is.null(dt_train) && nrow(dt_train) > 0) recap_train <- rbind(recap_train, dt_train, fill = TRUE)
                }
                rm (dt_train)
                if (nrow(recap_train) == 0) next
                a0_a1_train <- recap_train
                rm(recap_train); gc()
                #
                # a0_a1_train <- build_a0_a1_local(ms_train)    # meme traitement que pour le repertoire courant
                if (nrow(a0_a1_train[attacked == 0]) == 0 || nrow(a0_a1_train[attacked == 1]) == 0) next
                if (multi_detour) {
                  dtf_train <- data.table()
                  for (att_val in current_att_vec) {
                    d0_train <- a0_a1_train[attacked == 0 & extra_detour == att_val]
                    d1_train <- a0_a1_train[attacked == 1 & extra_detour == att_val]
                    if (d0_train[, .N] == 0 || d1_train[, .N] == 0) next
                    dtf_chunk_train <- mix_to_flow_fast(dtf_att0 = d0_train, dtf_attn = d1_train, prop = prop, group)
                    # Replace with: mix_to_flow(...) for optimized version instead of mix_to_flow
                    dtf_train <- rbind(dtf_train, dtf_chunk_train)
                  }
                } else {
                  dtf_train <- mix_to_flow_fast(
                    dtf_att0 = a0_a1_train[attacked == 0],
                    dtf_attn = a0_a1_train[attacked == 1],
                    prop = prop, group
                  )
                  # Replace with: mix_to_flow_fast(...) for optimized version instead of mix_to_flow
                }
                if (is.null(dtf_train) || nrow(dtf_train) == 0) next
                real_prop_train <- dtf_train[, mean(attacked == 1)]
                cat("[DEBUG] realprop train:", real_prop_train, "\n")
                dtf_train[, run_id := rep_train]
                
                dtf <- rbind(dtf, dtf_train, fill = TRUE)
                rm (dtf_train); gc()
                cat ("[CROSSSEED] fin chargement:", prefix_train, "\n")
              }
              current_param$cross_seed  <- TRUE
              current_param$test_run_id <- opt$repertory
              cat ("[CROSSSEED] fin\n")
            }else
            {
              current_param$cross_seed  <- FALSE
              current_param$test_run_id <- opt$repertory
            }
            
            cat ("[DEBUG] run_id in dtf:", "run_id" %in% names(dtf), "\n")
            cat ("[DEBUG] run_id in dtf:", unique(dtf$run_id), "\n")
            # ---- Model loop ----
            for (model in main_params$models) {
              current_param$model <- model$name
              cat("[PROTO]", proto, " [HOPS]", nb_hops, " [ATT]", nb_att_label, " [RATE]", parasite_rate, " [GROUP]", group, " [MODEL]", model$name, "\n")
              
              output_model <- paste0(output_path, "_model", model$name, "_/")
              dir.create(output_model, showWarnings = FALSE)
              
              local_dtf <- copy(dtf)
              if ((model$params)$is_timeserie) local_dtf <- copy(a0_a1)
              
              keep <- setdiff(names(local_dtf), remove_detail)
              if (isTRUE(current_param$cross_seed)) keep <- union(keep, "run_id")
              
              cat ("[DEBUG] run_id in keep:", "run_id" %in% keep, "\n")
              cat ("[DEBUG] run_id in local_dtf:", "run_id" %in% names(local_dtf), "\n")
              cat ("[DEBUG] run_id in local_dtf:", unique(local_dtf$run_id), "\n")
              current_param$do_pca <- FALSE
              current_param$do_0 <- FALSE
              
              # Partition: per-att if multi-detour, global otherwise
              if (multi_detour) {
                train_set <- data.table()
                test_set <- data.table()
                for (att_val in current_att_vec) {
                  subset <- local_dtf[extra_detour == att_val, ..keep]
                  if (nrow(subset) == 0) next
                  c(tr, te) %<-% partition(
                    dtf = subset,
                    unsupervised = (model$params)$unsupervised_partition,
                    p = (model$params)$p_partition,
                    do_pca = FALSE, is_timeserie = (model$params)$is_timeserie,
                    current_param = current_param
                  )
                  train_set <- rbind(train_set, tr)
                  test_set  <- rbind(test_set, te)
                }
              } else {
                c(train_set, test_set) %<-% partition(
                  dtf = local_dtf[, ..keep],
                  unsupervised = (model$params)$unsupervised_partition,
                  p = (model$params)$p_partition,
                  do_pca = FALSE, is_timeserie = (model$params)$is_timeserie,
                  current_param = current_param
                )
              }
              cat ("[DEBUG] fin partition\n")
              test_set  <- test_set[rowSums(is.na(test_set)) <= ncol(test_set) / 2]
              train_set <- train_set[rowSums(is.na(train_set)) <= ncol(train_set) / 2]
              if (nrow(test_set[attacked == 1]) == 0) { cat("[SKIP] no detour in test set\n"); next }
              
              
              c(tmp_score, test_set_model) %<-% model$model_function(train_set, test_set, current_param)
              
              dtf_err_model <- initialize_dtf()
              dtf_err_model <- rbindlist(list(dtf_err_model, cbind(tmp_group, tmp_score)),
                                        use.names = TRUE, fill = TRUE)
              dtf_err_model[, nb_packets := current_param$nb_packets]
              dtf_err_model[, packet_length := opt$packetSize]
              dtf_err_model[, testattheend := TRUE]
              dtf_err_model[, comment := opt$comment]
              dtf_err_model[, seed := current_param$my_seed]
              dtf_err_model[, temporal_cov := use_temporal_covariates]
              dtf_err_model[, cross_seed := isTRUE(current_param$cross_seed)]
              dtf_err_model[, feature_set := feature_set_tag]
              dtf_err_model[, n_features_reduced :=
                              if (is.null(reduced_feature_set)) NA_integer_
                            else length(reduced_feature_set)]
              #dtf_err_model[, feature_set := if (is.null(reduced_feature_set)) "full" else paste0("k", length(reduced_feature_set))]
              
              file_name <- paste0(output_model, "_error_model.csv")
              write.table(dtf_err_model, file_name, sep = ",", append = TRUE,
                          row.names = FALSE, col.names = !file.exists(file_name))
              
              if (main_params$store_test) {
                file_name_test <- paste0(output_model, "_error_test-set.csv")
                write.table(test_set_model, file_name_test, sep = ",", append = TRUE,
                            row.names = FALSE, col.names = !file.exists(file_name_test))
              }
              gc()
            } # model
            rm(dtf); gc()
          } # group
        } # prop
        
        rm(list = intersect(c("df_healthy", "df_detour", "a0_a1"), ls())); gc()
      } # parasite_rate
      rm(tmp_att)
    } # att plan
    rm(tmp_hop)
  } # nb_hops
  rm(tmp_proto)
} # proto

if (exists("merge_queue")) rm(merge_queue)
if (exists("merge_bandwidth")) rm(merge_bandwidth)
cat("\n[INFO] Terminé.\n")
