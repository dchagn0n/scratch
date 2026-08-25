#Rscript ./scratch/ninth/generation.R -t 60 -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n total 

#setwd("~/Documents/ns-3.45")
# set up directory ####
directory = "./scratch/ninth/"

# # Load common libraries and sources ####
# source(file = "./delay_function.R")
source(file = paste0(directory,"real_data.R"))
source(file = paste0(directory,"variation_generator_function.R"))
source(file = paste0(directory,"model_function.R"))
# source(file = "./main_function.R")
source(file = paste0(directory,"setup_function.R"))
source(file = paste0(directory,"setup_param.R"))


# library(dbscan)
# library(plyr)
library(data.table)
setDTthreads(percent = 65)
#library(dplyr)
library (cluster)
library(digest)
library(DescTools)
library(e1071)
library(FactoMineR) # PCA and HPC
library(getip) # getip address
library(ggplot2)
#
library(igraph)
library(isotree)
library(tensorflow, exclude = c("shape", "set_random_seed"))

library(keras3)
library(magrittr) # %>% operator
library(optparse)
library(patchwork)

# library("queuecomputer") # queue model
library(randomForest)
library(readr) # read_csv
library(rpart)
library(sads)
library(stringr)
#library(tidyverse)
library(xgboost) #for fitting the xgboost model
library(zeallot) # %<-% operator
# library(zoo)
library(caret) # createDataPartition
library(glmnet)

packages = c(
  'caret',
  #   'dbscan',
  #   'plyr',
  #'dplyr',
  'e1071',
  'FactoMineR',
  'getip',
  'ggplot2',
  'igraph',
  'isotree',
  'tensorflow',
  'keras3',
  #   'magrittr',
  #   "queuecomputer",
  'randomForest',
  'patchwork',
  'readr',
  'rpart',
  'sads',
  'stringr',
  'tidyverse',
  'xgboost'
  #   'zeallot',
  #   'zoo'
)

# Initialize necessary libraries for parallel processing
# library(doParallel)
# library(parallelly)
# library(foreach)
# # set up paralélisation ####
# num_cores <- parallelly::availableCores(omit = 5, constraints = "connections") #detectCores() # Détection du nombre de cœurs
# cl <- makeCluster(max (num_cores, 3), outfile="")# Créer un cluster
# registerDoParallel(cl)
# 
# # # Charger chaque fichier sur tous les nœuds
# # clusterEvalQ(cl, source("./delay_function.R"))
# clusterEvalQ(cl, source("./scratch/ninth/real_data.R"))
# clusterEvalQ(cl, source("./scratch/ninth/variation_generator_function.R"))
# clusterEvalQ(cl, source("./scratch/ninth/model_function.R"))
# # clusterEvalQ(cl, source("./main_function.R"))
# clusterEvalQ(cl, source("./scratch/ninth/setup_function.R"))
# clusterEvalQ(cl, source("./scratch/ninth/setup_param.R"))


# Define paths to save intermediate results ####
start_time <- as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M:%OS6"))  # Include microseconds
ipaddr <- getip("internal")
output_dir <- paste0("./", ipaddr, "/")
if (!dir.exists(output_dir)) dir.create(output_dir, showWarnings = FALSE)
dir.create(paste0(directory, "model/"), showWarnings = FALSE)  # Crée le dossier s'il n'existe pas



# parser of command lines ####
option_list <- list(
  make_option(c("-f", "--file"), type = "character", default = "ninth",
              help = "File name directpry", metavar = "FILE"),
  make_option(c("-t", "--simulationTime"), type = "double", default = 300,
              help = "Duration of the simulation", metavar = "SIMULATIONTIME"),
  make_option(c("-l", "--latency"), type = "character", default = "5ms",
              help = "Latency of the links", metavar = "LATENCY"),
  make_option(c("-b", "--bandwidth"), type = "character", default = "120Mbps",
              help = "Bandwidth of the links", metavar = "BANDWIDTH"),
  make_option(c("-a", "--dataRateAccess"), type = "character", default = "10Mbps",
              help = "Data rate of the links", metavar = "DATARATEACCESS"),
  # make_option(c("-e", "--dataRateExt"), type = "character", default = "10bps",
  #             help = "Data rate of the external links", metavar = "DATARATEEXT"),
  make_option(c("-o", "--packetSize"), type = "integer", default = 12000,
              help = "Packet size in bits", metavar = "PACKETSIZE"),
  make_option(c("-m", "--meanExpo"), type = "double", default = 0.5,
              help = "Mean of the exponential variable modeling inter-arrival time",
              metavar = "MEANEXPO"),
  make_option(c("-x", "--meanExpoPara"), type = "double", default = 0.5,
              help = "Mean of the exponential variable modeling inter-arrival time of parasite packets", 
              metavar = "MEANEXPOPARA"),
  make_option(c("-n", "--name"), type = "character", default = "path",
              help = "Name of the simalution scenario", 
              metavar = "NAME"),
  make_option(c("-g", "--graph"), type = "logical", default = FALSE,
              help = "Do the graph or not", 
              metavar = "GRAPH"),
  make_option(c("-r", "--repertory"), type = "character", default = "scratch/ninth",
              help = "Repertory containing data", metavar = "REPERTORY"),
  make_option(c("-e", "--evolution"), type = "logical", default = T,
              help = "Test on unknown scenarios", metavar = "EVOLUTION"),
  make_option(c("-i", "--trainonparasite"), type = "character", default = "60Mbps",
              help = "Parasite rate of the training set", metavar = "TRAINONPARASITE"),
  make_option(c("-d", "--trainondetour"), type = "character", default = "0_1_3_5_7_9",
              help = "Detour length of the training set", metavar = "TRAINONDETOUR"),
  make_option(c("-p", "--trainonpath"), type = "character", default = "0",
              help = "Path length of the training set", metavar = "TRAINONPATH"),
  make_option(c("-c", "--comment"), type = "character", default = "",
              help = "Any comment or precision about the simulation", metavar = "COMMENT"),
  make_option(c("-q", "--do_queue"),         type = "logical", default = FALSE),
  make_option(c("--trainRepertories"), type = "character", default = "",
              help = "Repertoires supplementaires utilises pour l'entrainement (separes par des virgules). 
              Si non vide, active le mode cross-seed."),
  make_option(c("--use_temporal_covariates"), type = "logical", default = FALSE,
              help = "Ablation des covariables 
              (TRUE  = comportement actuel (t_start et t_end conservés), FALSE = ablation)")
)

# Create the parser object
opt_parser <- OptionParser(option_list = option_list)
# Parse the arguments
opt <- parse_args(opt_parser)
use_temporal_covariates <- opt$use_temporal_covariates
print( ipaddr)
# if (ipaddr == "192.168.186.24")
# {

prefix_m = paste0(opt$repertory, "/T", sprintf(opt$simulationTime, fmt = '%#.6f'), "s_L", opt$latency, 
                  "_B", opt$bandwidth, "_Ra", opt$dataRateAccess, #"_Re", opt$dataRateExt,
                  "_P", opt$packetSize, "b_Ma" , sprintf(opt$meanExpo, fmt = '%#.6f') , 
                  "_Me", sprintf(opt$meanExpoPara, fmt = '%#.6f') , "_merge_path")#", opt$name)
# }else{
# prefix_m = "ninth/T2.000000s_L10ms_B100Mbps_Ra5Mbps_Re5Mbps_P12000b_Ma0.5_Me0.5_merge"
# prefix_m = "ninth/T2.000000s_L1ms_B100Mbps_Ra1Mbps_Re1Mbps_P12000b_Ma0.500000_Me0.500000_merge"
# }

print(prefix_m)


if ("testattheend" == opt$name)
{
  testattheend = T
}else{
  testattheend = F
}
testattheend = T

model_tmp = models_list[c(8,10,15,16,22,23)] #22,23,10,2,11,8,5,4,16,15,17,19,20)] #11,16,  19, 20, 2, 4, 5, 8,  15, 17,23,22, 13,14,10)] #  7)] #
models = model_tmp


# MAIN ####
main_params <- list(
  prop_att =  c(0.1) #, 0.025)#, 0.050,0.01, 0.075) # ,
  , models = models
  , do_pca = F #TRUE
  , store_test = F#TRUE
  , testattheend = testattheend
  , my_seed = opt$repertory # (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
  , do_evolution = opt$evolution
  ,trainonparasite = opt$trainonparasite
  ,trainondetour = opt$trainondetour
  ,trainonpath = opt$trainonpath
  , comment = opt$comment
  
)


# options ####
set.seed(1997)

prop_att = main_params$prop_att
prop = 0.1
group = 9
model = models[[1]]
pb_hops <- txtProgressBar(min = 1, max = max_TTL, style = 3)

simple = TRUE


do_graph = T
do_print = F
do_pdf = T
do_queue = T
do_flow = F
only_synthese = F #T
if (ipaddr == "192.168.186.24")
{
  do_graph = T #F#
  do_print = F
  do_pdf = T #F#
  do_queue = T #F#
  do_flow = F
  only_synthese = F #T #F#
}
if (ipaddr == "172.22.216.6")
{
  do_graph = F
  do_print = F
  do_pdf = F
  do_queue = F
  do_flow = F
  only_synthese = F
}
if (ipaddr == "172.22.216.4")
{
  do_graph = T#F
  do_print = F
  do_pdf = T#F
  do_queue =T#F
  do_flow = F
  only_synthese = T#F
}
if (ipaddr == "172.22.216.19")
{
  do_graph = T#F
  do_print = F
  do_pdf = T#F
  do_queue =T# F
  do_flow = F
  only_synthese = T#F
}


if ("TRUE" == toString(opt$graph))
{
  do_graph = T #F#
  do_print = F
  do_pdf = T #F#
  do_queue = T #T #F#
  do_flow = T
  only_synthese = F#T #F#
}else{
  do_graph = F#
  do_print = F
  do_pdf = F#
  do_queue = F#
  do_flow = F
  only_synthese = F#
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






src = "10.1.9.1"
#prefix_m = "ninth/T2.000000s_L10ms_B100Mbps_Ra5Mbps_Re5Mbps_P12000b_"
path_parts <- strsplit(prefix_m, "/")[[1]]
print(path_parts)
# prefix_rep <- paste(path_parts[-length(path_parts)], collapse = "/")
# print(prefix_rep)
prefix_rep <- sub(".*(scratch/.*)/[^/]+$", "\\1", prefix_m)
print(prefix_rep)

last_part <- tail(path_parts, n=1)
print(last_part)
prefix_split <- strsplit(last_part, "_")[[1]]
print(prefix_split)

prefix_time <- substring(prefix_split[1],2)
print(prefix_time)
prefix_latency <- (substring(prefix_split[2],2))
print(prefix_latency)
prefix_bandwidth <- (substring(prefix_split[3],2))
print(prefix_bandwidth)
prefix_rateaccess <- (substring(prefix_split[4],3))
print(prefix_rateaccess)
#prefix_rateparasite <- (substring(prefix_split[[1]][5],3))
prefix_packetlength <- (substring(prefix_split[5],2))
print(prefix_packetlength)
prefix_meanexp <- (substring(prefix_split[6],3))
print(prefix_meanexp)
prefix_meanexppara <- (substring(prefix_split[7],3))
print(prefix_meanexppara)
prefix_name <- (substring(prefix_split[9],1))
print(prefix_name)


rm(prefix_split)

print("before loading data")
#T60.000000s_h5_a0_L5ms_B120Mbps_Ra10Mbps_Re60Mbps_P12000b_Udp_Ma0.500000_Me0.500000_bandwidth.csv
#T60.000000s_h5_a0_L5ms_B120Mbps_Ra10Mbps_Re60Mbps_P12000b_Udp_Ma0.500000_Me0.500000_queue.csv
#T60.000000s_h5_a0_L5ms_B120Mbps_Ra10Mbps_Re60Mbps_P12000b_Udp_Ma0.500000_Me0.500000_trace_all_output_stats.csv

#prefix_m <- "ninth/T60.000000s_h2_a0_L5ms_B120Mbps_Ra10Mbps_Re60Mbps_P12000b_Udp_Ma0.500000_Me0.500000"
#do_queue = T

#merge_stats <- fread(paste0("scratch/", prefix_m, "_trace_all_output_stats.csv"), sep = ";", verbose = T, showProgress = TRUE)
merge_stats <- fread(paste0(prefix_m, "_trace_all_output_stats.csv"), sep = ";", 
                     verbose = T, showProgress = TRUE)
print(paste0("number of packets: ", nrow(merge_stats)))
print("after loading data")

if (do_queue)
{
  print("loading queue file")
  merge_queue <- fread(paste0(prefix_m, "_queue.csv"), sep = ";", verbose = T)
  merge_bandwidth <- fread(paste0(prefix_m, "_bandwidth.csv"), sep = ";", verbose = T)
  merge_bandwidth[, hop := factor(hop, levels = ordered_hop, ordered = TRUE)]
  #merge_bandwidth$hop = factor(merge_bandwidth$hop, levels = ordered_hop, ordered = T)
  print("end queue file")
}

# load data ####
df <- merge_stats[protocol %in% c("UDP", "17", "TCP")]
rm (merge_stats)
df[, run_id := opt$repertory]    # exécution de test

cross_seed <- nzchar(opt$trainRepertories)
df_train_list <- list()          # un df par répertoire d'entraînement

if (cross_seed) {
  for (rep_train in strsplit(opt$trainRepertories, ",")[[1]]) {
    prefix_train <- sub(opt$repertory, rep_train, prefix_m, fixed = TRUE)
    cat("[CROSSSEED] chargement:", prefix_train, "\n")
    ms_train <- fread(paste0(prefix_train, "_trace_all_output_stats.csv"),
                      sep = ";", fill = TRUE)
    df_train <- ms_train[protocol %in% c("UDP", "17", "TCP")]
    rm(ms_train)
    df_train[, run_id := rep_train]
    df_train_list[[rep_train]] <- df_train
    rm(df_train); gc()
  }
  cat("[CROSSSEED] ", length(df_train_list), " répertoires d'entraînement chargés\n")
}

df_healthy <- df[src_ip == src & dst_ip == "10.1.2.1"]

l_nb_hops <- unique(df[, extra_router])

# garder que ceux sur lesquels on entraine
split_detour <- strsplit(opt$trainondetour, "_")[[1]]
local_nb_att <- as.integer(split_detour)
trainondetour_nb_att <- unique(df[extra_detour %in% local_nb_att, extra_detour])
l_nb_att <- unique(df[, extra_detour])


l_proto = unique(df[["proto"]]) #c( "Udp", "Tcp")
l_parasite_rate = unique(df[, parasite_rate])
print(paste0("optname:", opt$name))

l_parasite_rate = l_parasite_rate[ l_parasite_rate %in%c("120Mbps")] #,"60Mbps")]
#l_nb_hops = l_nb_hops[ l_nb_hops %in%c(0,1,3,5,7,9,6)] #,5)]#,10, 30)]

print(main_params$do_evolution)
l_parasite_rate <- unique (c(main_params$trainonparasite, l_parasite_rate))
l_nb_hops <- unique (c(main_params$trainonpath, l_nb_hops))
l_nb_att <- unique (c(main_params$trainondetour, l_nb_att))

print(l_parasite_rate)
print(l_nb_hops)
print(l_nb_att)


proto = l_proto[1]
nb_hops = l_nb_hops[1]
nb_att = l_nb_att[1]
parasite_rate = l_parasite_rate [1]


nb_packets = df_healthy[ , .N]
current_param <- list(
  simulation_time = prefix_time,
  latency = prefix_latency, 
  bandwidth = prefix_bandwidth,
  data_rate = prefix_rateaccess, 
  parasite_rate = parasite_rate,
  meanexp = prefix_meanexp, 
  parasite_meanexp = prefix_meanexppara,
  nb_packets = nb_packets,
  nb_hops = nb_hops,
  nb_att = nb_att,
  prop = prop,
  group = group,
  model = model$name,
  proto = proto,
  do_pca = main_params$do_pca,
  testattheend = main_params$testattheend,
  comment = main_params$comment,
  my_seed = main_params$my_seed,
  do_evolution = main_params$do_evolution
  ,trainonparasite = main_params$trainonparasite
  ,trainondetour = main_params$trainondetour
  ,trainonpath = main_params$trainonpath
  ,cross_seed  = FALSE
  ,test_run_id = opt$repertory
)

prop_att = main_params$prop_att
output_sim <- paste0(output_dir, "_sim", prefix_time,"_/")
dir.create(output_sim, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas


build_a0_a1_from_df_1 <- function(df_src, prefix, src, parasite_rate,
                                  time, stepr) {
  df_healthy <- df_src[src_ip == src & dst_ip == "10.1.2.1"]
  df_detour  <- df_src[src_ip == src & dst_ip == "10.1.3.1"]
  if (nrow(df_healthy) == 0 || nrow(df_detour) == 0) return(NULL)
  
  ## ---- healthy path ----
  a0_output_H <- df_healthy[file == paste0(prefix, "trace-access0-access_access0-0-0.pcap")]
  a1_input_H  <- df_healthy[file == paste0(prefix, "trace-access1-access_access1-1-1.pcap")]
  # ⚠️ recopie ici EXACTEMENT les noms de fichiers PCAP de ton code actuel
  #    pour le chemin sain (a0_output_H, a1_input_H) : ils doivent être
  #    identiques à ceux déjà présents dans le fichier.
  if (identical(unique(a0_output_H[, file]), character(0))) return(NULL)
  if (identical(unique(a1_input_H[, file]), character(0))) return(NULL)
  
  a0_a1_H <- fusion_starttoend(
    end   = a1_input_H[1:min(nrow(a1_input_H), nrow(a0_output_H))],
    start = a0_output_H[1:min(nrow(a1_input_H), nrow(a0_output_H))],
    "healthy")
  
  ## ---- detour path ----
  a0_output_D <- df_detour[file == paste0(prefix, "trace-access0-access_access0-0-0.pcap")]
  a1_input_D  <- df_detour[file == paste0(prefix, "trace-dist1-access1-detour_access1-1-1.pcap")]
  if (identical(unique(a0_output_D[, file]), character(0))) return(NULL)
  if (identical(unique(a1_input_D[, file]), character(0))) return(NULL)
  
  a0_a1_D <- fusion_starttoend(
    end   = a1_input_D[1:min(nrow(a1_input_D), nrow(a0_output_D))],
    start = a0_output_D[1:min(nrow(a1_input_D), nrow(a0_output_D))],
    "detour")
  
  ## ---- fusion + renommage (identique à ton code) ----
  lookup <- c(t_start = "start_timestamp", packet_length = "length",
              attacked = "type", delay = "delay_path", t_end = "end_timestamp")
  a0_a1 <- rbindlist(list(a0_a1_D, a0_a1_H))
  a0_a1[, c("start_file", "end_file", "source_file", "start_packet_num") := NULL]
  old_names <- unname(lookup); new_names <- names(lookup)
  setnames(a0_a1, old = old_names[old_names %in% names(a0_a1)],
           new = new_names[old_names %in% names(a0_a1)])
  a0_a1[, attacked := factor(fifelse(attacked == "detour", 1L, 0L))]
  
  # propager le run_id de la source
  if ("run_id" %in% names(df_src)) a0_a1[, run_id := unique(df_src$run_id)[1]]
  return(a0_a1)
}

build_a0_a1_from_df <- function(df_healthy, df_detour, prefix) {
  cat ("[DEBUG] prefix:", prefix,"\n")
  ## ---- healthy path ----
  a0_output_H <- df_healthy[file == paste0(prefix, "trace-access0-access_access0-0-0.pcap")]
  a1_input_H  <- df_healthy[file == paste0(prefix, "trace-dist1-access1-direct_access1-1-0.pcap")]
  
  cat ("[DEBUG] a0_output_H:", nrow(a0_output_H),"\n")
  cat ("[DEBUG] a1_input_H:", nrow(a1_input_H),"\n")
  # ⚠️ recopie ici EXACTEMENT les noms de fichiers PCAP de ton code actuel
  #    pour le chemin sain (a0_output_H, a1_input_H) : ils doivent être
  #    identiques à ceux déjà présents dans le fichier.
  if (identical(unique(a0_output_H[, file]), character(0))) return(NULL)
  if (identical(unique(a1_input_H[, file]), character(0))) return(NULL)
  
  a0_a1_H <- fusion_starttoend(
    end   = a1_input_H[1:min(nrow(a1_input_H), nrow(a0_output_H))],
    start = a0_output_H[1:min(nrow(a1_input_H), nrow(a0_output_H))],
    "healthy")
  cat ("[DEBUG] a0_a1_H:", nrow(a0_a1_H),"\n")
  ## ---- detour path ----
  a0_output_D <- df_detour[file == paste0(prefix, "trace-access0-access_access0-0-0.pcap")]
  a1_input_D  <- df_detour[file == paste0(prefix, "trace-dist1-access1-detour_access1-1-1.pcap")]
  if (identical(unique(a0_output_D[, file]), character(0))) return(NULL)
  if (identical(unique(a1_input_D[, file]), character(0))) return(NULL)
  cat ("[DEBUG] a0_output_D:", nrow(a0_output_D),"\n")
  cat ("[DEBUG] a1_input_D:", nrow(a1_input_D),"\n")
  a0_a1_D <- fusion_starttoend(
    end   = a1_input_D[1:min(nrow(a1_input_D), nrow(a0_output_D))],
    start = a0_output_D[1:min(nrow(a1_input_D), nrow(a0_output_D))],
    "detour")
  cat ("[DEBUG] a0_a1_D:", nrow(a0_a1_D),"\n")
  ## ---- fusion + renommage (identique à ton code) ----
  lookup <- c(t_start = "start_timestamp", packet_length = "length",
              attacked = "type", delay = "delay_path", t_end = "end_timestamp")
  a0_a1 <- rbindlist(list(a0_a1_D, a0_a1_H))
  cat("[DEBUG] names(a0_a1):", names(a0_a1), "\n")
  a0_a1[, c("start_file", "end_file", "source_file", "start_packet_num") := NULL]
  old_names <- unname(lookup); new_names <- names(lookup)
  setnames(a0_a1, old = old_names[old_names %in% names(a0_a1)],
           new = new_names[old_names %in% names(a0_a1)])
  a0_a1[, attacked := factor(fifelse(attacked == "detour", 1L, 0L))]
  cat ("[DEBUG] a0_a1:", nrow(a0_a1),"\n")
  # propager le run_id de la source
  #if ("run_id" %in% names(df_healthy)) a0_a1[, run_id := unique(df_src$run_id)[1]]
  return(a0_a1)
}
## proto loop #####
#foreach(proto = l_proto, .combine = rbind, .packages = packages) %dopar%
for (proto in l_proto)
{
  current_param$proto = proto
  time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
  stepp = paste0("sim:", prefix_time, " proto:", proto)
  print(paste0(time, "- ", stepp))
  
  output_proto <- paste0(output_sim, "_proto", proto,"_/")
  dir.create(output_proto, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas
  local_proto <- proto
  tmp_proto_trace <- df[proto == local_proto]
  print("test proto:")
  print(unique(tmp_proto_trace[,proto]))
  print(local_proto)
  if (tmp_proto_trace[ , .N] == 0)
  {
    next
  }
  ### nb_hops loop ####
  #foreach(nb_hops = l_nb_hops, .combine = rbind, .packages = packages) %dopar%
  for (nb_hops in l_nb_hops)
  {
    current_param$nb_hops = nb_hops
    time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
    steph = paste0(stepp, " nb_hops:", nb_hops)
    print(paste0(time, "- ", steph))
    
    output_hops <- paste0(output_proto, "_hops", nb_hops,"_/")
    dir.create(output_hops, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas
    
    local_nb_hops <- nb_hops
    tmp_hop_trace <- tmp_proto_trace[extra_router == local_nb_hops]
    print(paste("nb_hops:",unique(tmp_hop_trace[,extra_router])))
    
    if (nrow(tmp_hop_trace) == 0)
    {
      next
    }
    #### nb_att loop ####
    for (nb_att in l_nb_att)
    {
      #nb_att = current_param$trainondetour
      current_param$nb_att = nb_att #current_param$trainondetour
      
      time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
      stepa = paste(steph, paste0("nb_att:", nb_att))
      print(paste0(time, "- ", stepa))
      
      output_att <- paste0(output_hops, "_att", nb_att,"_/")
      dir.create(output_att, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas
      
      current_nb_att <- nb_att
      if (nchar(nb_att) > 1) # if current_nb_att contains several values of detour (0_1_3_5_7_9)
      {
        current_nb_att <-trainondetour_nb_att
      }
      tmp_att_trace <- tmp_hop_trace[extra_detour %in% current_nb_att]
      print(paste("nb_att:",unique(tmp_att_trace[,extra_detour])))
      
      if (nrow(tmp_att_trace) == 0)
      {
        next
      }
      ##### parasite_rate loop ####
      for (parasite_rate in l_parasite_rate)
      {
        current_param$parasite_rate = parasite_rate
        time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
        stepr = paste(stepa, paste0("parasite_rate:", parasite_rate))
        print(paste0(time, "- ", stepr))
        
        output_rate <- paste0(output_att, "_rate", parasite_rate,"_/")
        dir.create(output_rate, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas
        local_parasite_rate <- parasite_rate
        tmp_rate_trace <- tmp_att_trace[parasite_rate == local_parasite_rate]
        print(paste("parasite_rate:", unique(tmp_rate_trace[,parasite_rate])))
        print (paste0("nrow tmp_rate_trace:", nrow(tmp_rate_trace)))
        if (nrow(tmp_rate_trace) == 0)
        {
          next
        }
        
        df_healthy <- tmp_rate_trace[src_ip == src & dst_ip == "10.1.2.1"]
        df_detour <- tmp_rate_trace[src_ip == src & dst_ip == "10.1.3.1"]
        print("check1")
        print(unique(df_healthy[,src_ip]))
        print(unique(df_detour[,dst_ip]))
        nb_packets = df_healthy[, .N]#nrow(df_healthy)
        current_param$nb_packets = nb_packets
        
        ## CROSS_SEED ici sur tmp_rate_trace
        
        
        recap_a0_a1 <- data.table()
        print(paste("current_nb_att:", current_nb_att))
        nb_att2 = current_nb_att[1]
        
        for (nb_att2 in current_nb_att)
        {
          prefix <- paste0(prefix_rep, "/T",prefix_time, "_h", nb_hops, "_a", nb_att2, 
                           "_L", prefix_latency, "_B", prefix_bandwidth, 
                           "_Ra", prefix_rateaccess, "_Re", parasite_rate,
                           "_P", prefix_packetlength,"_",proto, "_Ma", prefix_meanexp, "_Me", prefix_meanexppara, "_")
          
          a0_a1 <- build_a0_a1_from_df (df_healthy, df_detour, prefix)
          a0_a1[, run_id := opt$repertory]  
          # print(paste0("prefix = ", prefix))
          # ##print(unique(df_healthy[,file]))
          # ## healthy path
          # # call build_a0_a1
          # 
          # 
          # a0_output_H <- df_healthy[file==paste0(prefix,"trace-access0-access_access0-0-0.pcap")]
          # print(unique (a0_output_H[,file]))
          # if (identical(unique (a0_output_H[,file]), character(0)))
          # {
          #   print("ERROR DATASET")
          #   file_name <- paste0("_error_dataset.csv")
          #   write.table(paste0(time, "- ", stepr), file_name, sep = ",", append = TRUE, row.names = F)
          #   write.table(paste0(prefix,"trace-access0-access_access0-0-0.pcap"), file_name, sep = ",", append = TRUE, row.names = F)
          #   next
          # }
          # #d0_input_H <- df_healthy[df_healthy$file==paste0("scratch/",prefix,"trace-access-dist0_dist0-2-0.pcap"),]
          # #d0_output_H <- df_healthy[df_healthy$file==paste0("scratch/",prefix,"trace-dist0-dist1_dist0-2-1.pcap"),]
          # #d1_input_H <- df_healthy[df_healthy$file==paste0("scratch/",prefix,"trace-dist0-dist1_dist1-3-2.pcap"),]
          # #d1_output_H <- df_healthy[df_healthy$file==paste0("scratch/",prefix,"trace-dist1-access1_dist1-3-0.pcap"),]
          # a1_input_H <- df_healthy[file==paste0(prefix,"trace-dist1-access1-direct_access1-1-0.pcap")]
          # print(unique (a1_input_H[,file]))
          # if (identical(unique (a1_input_H[,file]), character(0)))
          # {
          #   print("ERROR DATASET")
          #   file_name <- paste0("_error_dataset.csv")
          #   write.table(paste0(time, "- ", stepr), file_name, sep = ",", append = TRUE, row.names = F)
          #   
          #   write.table(paste0(prefix,"trace-dist1-access1-direct_access1-1-0.pcap"), file_name, sep = ",", append = TRUE, row.names = F)
          #   next
          # }
          # ##print(head(a0_output_H))
          # #a0_d1_H <- fusion_starttoend(end = d1_input_H, start = a0_output_H, "healthy")
          # #d0_a1_H <- fusion_starttoend(end = a1_input_H, start = d0_output_H, "healthy")
          # a0_a1_H <- fusion_starttoend(end = a1_input_H[1:min(nrow(a1_input_H), nrow(a0_output_H))], 
          #                              start = a0_output_H[1:min(nrow(a1_input_H), nrow(a0_output_H))], "healthy")
          # #d0_d1_H <- fusion_starttoend(end = d1_input_H, start = d0_input_H, "healthy")
          # #d0_H <- fusion_starttoend(end = d0_output_H, start = d0_input_H, "healthy")
          # 
          # ## detour path
          # a0_output_D <- df_detour[file==paste0(prefix,"trace-access0-access_access0-0-0.pcap")]
          # print(unique (a0_output_D[,file]))
          # if (identical(unique (a0_output_D[,file]), character(0)))
          # {
          #   print("ERROR DATASET")
          #   
          #   file_name <- paste0("_error_dataset.csv")
          #   write.table(paste0(time, "- ", stepr), file_name, sep = ",", append = TRUE, row.names = F)
          #   
          #   write.table(paste0(prefix,"trace-access0-access_access0-0-0.pcap"), file_name, sep = ",", append = TRUE, row.names = F)
          #   next
          # }
          # # d0_input_D <- df_detour[df_detour$file==paste0("scratch/",prefix,"trace-access-dist0_dist0-2-0.pcap"),]
          # # d0_output_D <- df_detour[df_detour$file==paste0("scratch/",prefix,"trace-dist0-dist2_dist0-2-2.pcap"),]
          # # d1_input_D <- df_detour[df_detour$file==paste0("scratch/",prefix,"trace-dist2-dist1_dist1-3-3.pcap"),]
          # # d1_output_D <- df_detour[df_detour$file==paste0("scratch/",prefix,"trace-dist1-access1_dist1-3-1.pcap"),]
          # a1_input_D <- df_detour[file==paste0(prefix,"trace-dist1-access1-detour_access1-1-1.pcap")]
          # print(unique (a1_input_D[,file]))
          # if (identical(unique (a1_input_D[,file]), character(0)))
          # {
          #   print("ERROR DATASET")
          #   file_name <- paste0("_error_dataset.csv")
          #   write.table(paste0(time, "- ", stepr), file_name, sep = ",", append = TRUE, row.names = F)
          #   
          #   write.table(paste0(prefix,"trace-dist1-access1-detour_access1-1-1.pcap"), file_name, sep = ",", append = TRUE, row.names = F)
          #   next
          # }
          # # a0_d1_D <- fusion_starttoend(end = d1_input_D, start = a0_output_D, "detour")
          # # d0_a1_D <- fusion_starttoend(end = a1_input_D, start = d0_output_D, "detour")
          # a0_a1_D <- fusion_starttoend(end = a1_input_D[1:min(nrow(a1_input_D), nrow(a0_output_D))], 
          #                              start = a0_output_D[1:min(nrow(a1_input_D), nrow(a0_output_D))], "detour")
          # # d0_d1_D <- fusion_starttoend(end = d1_input_D, start = d0_input_D, "detour")
          # # d0_D <- fusion_starttoend(end = d0_output_D, start = d0_input_D, "detour")
          # 
          # lookup <- c(t_start = "start_timestamp", packet_length = "length", attacked = "type", delay = "delay_path", t_end = "end_timestamp")
          # print("check2")
          # print(nrow(a0_a1_D))
          # print(nrow(a0_a1_H))
          # # Fusion verticale
          # a0_a1 <- rbindlist(list(a0_a1_D, a0_a1_H))
          # a0_a1[, c("start_file", "end_file", "source_file", "start_packet_num") := NULL]
          # # Inverser lookup pour setnames (data.table veut: old -> new)
          # new_names <- names(lookup)
          # old_names <- unname(lookup)
          # setnames(a0_a1, old = old_names[old_names %in% names(a0_a1)], new = new_names[old_names %in% names(a0_a1)])
          # # Recoder 'attacked' : "detour" -> 1, "healthy" -> 0
          # a0_a1[, attacked := fifelse(attacked == "detour", 1L, 0L)]
          # # Convertir en facteur
          # a0_a1[, attacked := factor(attacked)]
          # print(unique (a0_a1[,attacked]))
          # print(paste("0:" ,nrow(a0_a1[attacked == 0])))
          # print(paste("1:",nrow(a0_a1[attacked == 1])))
          # print(paste("a0, a1:",nrow(a0_a1)))
          # # a0_a1 <- rbind(a0_a1_D, a0_a1_H) %>% 
          # #   select(- c(start_file, end_file, source_file, start_packet_num)) %>%
          # #   rename(any_of(lookup)) %>%
          # #   mutate (attacked = recode (attacked, "detour" = 1, "healthy" = 0)) %>%
          # #   mutate_at (c('attacked'), as.factor)
          ##### do graph ####
          if (nrow(a0_a1) == 0)
          {
            print("je next a0_a1")
            next
          }
          recap_a0_a1 <- rbind(recap_a0_a1, a0_a1)
          
        }
        a0_a1 <- copy(recap_a0_a1)
        a0_a1[, run_id := opt$repertory]  
        rm (recap_a0_a1#,
            #a0_a1_D, a0_a1_H, 
            #a0_output_D, a0_output_H, 
            #a1_input_D, a1_input_H
        )
        cat ("[DEBUG] names(a0_a1):", names(a0_a1), "\n")
        gc()
        if (nrow(a0_a1) == 0){
          print("je next a0_a1")
          next
        }
        if (do_graph)
        {
          
          graph_prefix <- paste0(
            prefix_rep, "/T", prefix_time, "_h", nb_hops, "_a", nb_att2,
            "_L", prefix_latency, "_B", prefix_bandwidth,
            "_Ra", prefix_rateaccess, "_Re", parasite_rate,
            "_P", prefix_packetlength, "_", proto,
            "_Ma", prefix_meanexp, "_Me", prefix_meanexppara, "_"
          )
          if (nrow(a0_a1) > 0) {
            tryCatch(
              generate_delay_graphs(a0_a1, graph_prefix,
                                    proto, nb_hops, nb_att2, parasite_rate),
              error = function(e) cat("[GRAPH ERROR]", conditionMessage(e), "\n")
            )
          }
          
        }
        
        print(colnames(a0_a1))
        current_param$simulation_time = unique (a0_a1[, simulation_time])
        current_param$latency = unique (a0_a1[, latency])
        current_param$bandwidth = unique (a0_a1[, bandwidth])
        current_param$data_rate = unique (a0_a1[, data_rate])
        current_param$parasite_rate = unique (a0_a1[, parasite_rate])
        current_param$meanexp = unique (a0_a1[, meanexp])
        current_param$parasite_meanexp = unique (a0_a1[, meanexppara])
        
        
        ##### prop_i loop ####
        prop_i = 1
        if (! only_synthese)
        {
          for (prop_i in 1:length(prop_att))
          {
            prop = prop_att[prop_i]
            prop_att_order = prop_att[order(prop_att)]
            current_param$prop = prop
            
            
            time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
            stepi = paste(stepr, paste0("prop:", prop))
            print(paste0(time, "- ", stepi))
            
            output_prop <- paste0(output_rate, "_prop", prop,"_/")
            dir.create(output_prop, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas
            
            if (!current_param$do_evolution)
            {
              current_param$trainonparasite = current_param$parasite_rate
              current_param$trainondetour = current_param$nb_att
              current_param$trainonpath = current_param$nb_hops
              
              main_params$trainonparasite = current_param$parasite_rate
              main_params$trainondetour = current_param$nb_att
              main_params$trainonpath = current_param$nb_hops
            }
            
            tmp_att = data.table(simulation_time = current_param$simulation_time, 
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
                                 trainonpath = current_param$trainonpath) 
            
            
            size_group = c(9) #342, 27,9) # 342, 
            
            group = size_group[1]
            same_size_dataset = nrow(a0_a1)
            ####### group loop ####
            for (group in size_group)
            {
              current_param$group = group
              
              output_group <- paste0(output_prop, "_group", group,"_/")
              dir.create(output_group, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas
              
              time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
              stepg = paste(stepi, paste0("group:", group))
              print(paste0(time, "- ", stepg))
              
              tmp_group <- copy(tmp_att)
              tmp_group[, size_group := group] #cbind (tmp_att, data.table(size_group = group))
              print(paste0("before mix flow: health:", nrow(a0_a1[attacked == 0]), " , attacked:", nrow(a0_a1[attacked == 1])))
              dtf <- data.table()
              nb_att2 = current_nb_att[1]
              for (nb_att2 in current_nb_att)
              {
                print(paste("nb_att2:", nb_att2))
                dtf_att0 = a0_a1[attacked == 0 & extra_detour == as.integer(nb_att2)]
                dtf_attn = a0_a1[attacked == 1 & extra_detour == as.integer(nb_att2)]
                print(paste("length dtf_attn:", dtf_attn[,.N]))
                print(paste("length dtf_att0:", dtf_att0[,.N]))
                if (0 == dtf_attn[,.N] | 0 == dtf_att0[,.N])
                {
                  next
                }
                dtf_att <- mix_to_flow(dtf_att0 = a0_a1[attacked == 0 & extra_detour == nb_att2], dtf_attn = a0_a1[attacked == 1 & extra_detour == nb_att2], prop = prop, group)
                dtf <- rbind(dtf, dtf_att)
                rm(dtf_att)
              }
              same_size_dataset = min(same_size_dataset, nrow(dtf))
              if (current_param$comment == "same_size_dataset")
              {
                prop_init <- dtf[, mean(attacked == 1)] # Initial proportion of detoured packets
                target_size = same_size_dataset
                
                # Calcul des tailles par groupe
                n_attacked <- sum(dtf$attacked == 1)
                n_not_attacked <- sum(dtf$attacked == 0)
                
                
                # Nombre à prélever dans chaque groupe
                n_attacked_target <- round(target_size * prop_init)
                n_not_attacked_target <- target_size - n_attacked_target
                
                # Échantillonnage stratifié
                dtf <- rbind(
                  dtf[attacked == 1][sample(.N, n_attacked_target)],
                  dtf[attacked == 0][sample(.N, n_not_attacked_target)]
                )
                
                
                #dtf <- dtf[order(t_start)][1:same_size_dataset]
                time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
                steptmp = paste(stepg, paste0("same_size_dataset:", same_size_dataset))
                print(paste0(time, "- ", steptmp))
              }
              if (nrow(dtf) == 0)
              {
                print("dtf after mix flow empty")
                next
              }
              
              real_prop = dtf[, mean(attacked == 1)]#length(dtf$attacked[dtf$attacked == 1]) / nrow(dtf)
              time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
              steptmp = paste(stepg, paste0("real_prop:", real_prop))
              print(paste0(time, "- ", steptmp))
              
              if (abs(real_prop-prop)> 0.01)
              {
                next
              }
              
              
              # n_detour = max(1,round((prop / (1-prop)) * nrow(a0_a1_H)))
              # id_detour = sample(nrow(a0_a1_D), size = n_detour, replace= FALSE)
              # 
              # 
              # a0_a1 <- rbind(a0_a1_D[id_detour, ], a0_a1_H) %>% 
              #   select(- c(start_file, end_file, source_file, start_packet_num)) %>%
              #   rename(any_of(lookup)) %>%
              #   mutate (attacked = recode (attacked, "detour" = 1, "healthy" = 0)) %>%
              #   mutate_at (c('attacked'), as.factor)
              # 
              # real_prop = length(a0_a1$attacked[a0_a1$attacked == 1]) / nrow(a0_a1)
              # time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
              # steptmp = paste(stepi, paste0("real_prop:", real_prop))
              # print(paste0(time, "- ", steptmp))
              
              
              # a0_a1 des exécutions d'entraînement (mode cross-seed)
              dtf[, run_id := opt$repertory] 
              ##### ---- cross seed ----
              if (cross_seed) {
                cat ("[DEBIG] in cross seed", "\n")
                for (rep_train in names(df_train_list)) {
                  cat ("[DEBUG] rep_train:", rep_train,"\n")
                  prefix_train <- sub(opt$repertory, rep_train, prefix_m, fixed = TRUE)
                  cat ("[DEBUG] prefix_train:", prefix_train,"\n")
                  df_train <- df_train_list[[rep_train]]
                  cat ("[DEBUG] df_train:", nrow(df_train),"\n")
                  tmp_proto_trace_train <- df_train[proto == local_proto]
                  cat ("[DEBUG] tmp_proto_trace_train:", nrow(tmp_proto_trace_train),"\n")
                  rm(df_train)
                  if (tmp_proto_trace_train[ , .N] == 0) next
                  tmp_hop_trace_train <- tmp_proto_trace_train[extra_router == local_nb_hops]
                  cat ("[DEBUG] tmp_hop_trace_train:", nrow(tmp_hop_trace_train),"\n")
                  if (nrow(tmp_hop_trace_train) == 0) next
                  tmp_att_trace_train <- tmp_hop_trace_train[extra_detour %in% current_nb_att]
                  cat ("[DEBUG] tmp_att_trace_train:", nrow(tmp_att_trace_train),"\n")
                  if (nrow(tmp_att_trace_train) == 0) next
                  tmp_rate_trace_train <- tmp_att_trace_train[parasite_rate == local_parasite_rate]
                  cat ("[DEBUG] tmp_rate_trace_train:", nrow(tmp_rate_trace_train),"\n")
                  if (nrow(tmp_rate_trace_train) == 0) next
                  df_healthy_train <- tmp_rate_trace_train[src_ip == src & dst_ip == "10.1.2.1"]
                  df_detour_train <- tmp_rate_trace_train[src_ip == src & dst_ip == "10.1.3.1"]
                  cat ("[DEBUG] df_healthy_train:", nrow(df_healthy_train),"\n")
                  cat ("[DEBUG] df_detour_train:", nrow(df_detour_train),"\n")
                  recap_a0_a1_train <- data.table()
                  nb_att2 = current_nb_att[1]
                  
                  for (nb_att2 in current_nb_att)
                  {
                    prefix_tr <- paste0(sub(".*(scratch/.*)/[^/]+$", "\\1", prefix_train), 
                                        "/T",prefix_time, "_h", nb_hops, "_a", nb_att2, 
                                        "_L", prefix_latency, "_B", prefix_bandwidth, 
                                        "_Ra", prefix_rateaccess, "_Re", parasite_rate,
                                        "_P", prefix_packetlength,"_",proto, "_Ma", prefix_meanexp, 
                                        "_Me", prefix_meanexppara, "_")
                    
                    a0_a1_train <- build_a0_a1_from_df (df_healthy_train, df_detour_train, prefix_tr)
                    cat ("[DEBUG] a0_a1_train:", nrow(a0_a1_train),"\n")
                    if (is.null(a0_a1_train) || nrow(a0_a1_train) == 0) next
                    recap_a0_a1_train <- rbind(recap_a0_a1_train, a0_a1_train)
                    cat ("[DEBUG] attacked in names(recap_a0_a1_train): ", "attacked" %in% names(a0_a1_train), "\n")
                  }
                  a0_a1_train <- copy(recap_a0_a1_train)
                  rm(recap_a0_a1_train)
                  if (is.null(a0_a1_train) ||  nrow(a0_a1_train) == 0) next
                  
                  dtf_train <- data.table()
                  nb_att2 = current_nb_att[1]
                  cat ("[DEBUG] names(a0_a1_train): ", names(a0_a1_train), "\n")
                  for (nb_att2 in current_nb_att)
                  {
                    dtf_att0_train = a0_a1_train[attacked == 0 & extra_detour == as.integer(nb_att2)]
                    dtf_attn_train = a0_a1_train[attacked == 1 & extra_detour == as.integer(nb_att2)]
                    if (0 == dtf_attn_train[,.N] | 0 == dtf_att0_train[,.N]) next
                    dtf_att_train <- mix_to_flow(dtf_att0 = a0_a1_train[attacked == 0 & extra_detour == nb_att2], 
                                                 dtf_attn = a0_a1_train[attacked == 1 & extra_detour == nb_att2], 
                                                 prop = prop, group)
                    dtf_train <- rbind(dtf_train, dtf_att_train)
                    rm(dtf_att_train)
                  }
                  if (is.null(dtf_train) || nrow(dtf_train) == 0) next
                  cat ("[DEBUG] names(dtf_train): ", names(dtf_train), "\n")
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
              } else
              {
                current_param$cross_seed  <- FALSE
                current_param$test_run_id <- opt$repertory
              }
              
              cat ("[DEBUG] run_id in dtf:", "run_id" %in% names(dtf), "\n")
              cat ("[DEBUG] run_id in dtf:", unique(dtf$run_id), "\n")
              
              ######## model loop ####
              for (model in main_params$models)
              {
                current_param$model = model$name
                dtf_err_model <- initialize_dtf()
                
                time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
                stepm = paste(steptmp, paste0("model:", model$name))
                print(paste0(time,'- ', stepm))
                
                output_model <- paste0(output_group, "_model", model$name,"_/")
                dir.create(output_model, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas
                
                if ((model$params)$is_timeserie)
                {
                  dtf_no_timeseries = dtf
                  dtf = a0_a1
                }
                
                #' without pca
                keep <- setdiff(names(dtf), remove_detail) # -which(names(dtf) %in% remove_detail)
                if (isTRUE(current_param$cross_seed)) keep <- union(keep, "run_id")
                cat ("[DEBUG] run_id in keep:", "run_id" %in% keep, "\n")
                cat ("[DEBUG] run_id in dtf:", "run_id" %in% names(dtf), "\n")
                cat ("[DEBUG] run_id in dtf:", unique(dtf$run_id), "\n")
                current_param$do_pca = FALSE
                current_param$do_0 = FALSE
                train_set <- data.table()
                test_set <- data.table()
                nb_att2 = current_nb_att[1]
                for (nb_att2 in current_nb_att)
                {
                  c(train_set_att, test_set_att) %<-% partition(
                    dtf = dtf[extra_detour == nb_att2, ..keep],
                    unsupervised = (model$params)$unsupervised_partition,
                    p = (model$params)$p_partition, 
                    do_pca = current_param$do_pca,
                    is_timeserie = (model$params)$is_timeserie,
                    current_param = current_param
                  )
                  train_set <- rbind(train_set, train_set_att)
                  test_set <- rbind(test_set, test_set_att)
                  rm(train_set_att, test_set_att)
                }
                cat ("[DEBUG] fin partition\n")
                test_set <- test_set[rowSums(is.na(test_set)) <= ncol(test_set)/2]
                train_set <- train_set[rowSums(is.na(train_set)) <= ncol(train_set)/2]
                main_params$my_seed <- current_param$my_seed
                print(colnames(train_set))
                print(colnames(test_set))
                if (nrow(test_set[attacked==1]) == 0){
                  print("no detour in test set")
                  next
                }
                
                
                c(tmp_score, test_set_model) %<-% model$model_function(train_set, test_set, current_param)
                print("afeter model")
                tmp = cbind(
                  tmp_group,
                  tmp_score
                )
                #dtf_err_model <- rbind(dtf_err_model, tmp)
                dtf_err_model <- rbindlist(list(dtf_err_model, tmp), use.names = TRUE, fill = TRUE)
                
                
                #' #' do without detour #######################
                #' current_param$do_0 = TRUE
                #' c(train_set, test_set) %<-% partition(
                #'   dtf = dtf[, ..keep],
                #'   unsupervised = (model$params)$unsupervised_partition,
                #'   p = (model$params)$p_partition, 
                #'   do_pca = current_param$do_pca,
                #'   is_timeserie = (model$params)$is_timeserie,
                #'   current_param = current_param
                #' )
                #' main_params$my_seed <- current_param$my_seed
                #' # if (nrow(test_set[attacked==1]) == 0){
                #' #   print("no detour in test set")
                #' #   next
                #' # }
                #' 
                #' c(tmp_score, test_set_model) %<-% model$model_function(train_set, test_set, current_param)
                #' print("afeter model")
                #' tmp = cbind(
                #'   tmp_group,
                #'   tmp_score
                #' )
                #' tmp$nb_detour = -1
                #' dtf_err_model <- rbindlist(list(dtf_err_model, tmp), use.names = TRUE, fill = TRUE)
                #' #'########################
                if(main_params$do_pca & !(model$params)$is_timeserie)
                {
                  #' with pca
                  current_param$do_pca = TRUE
                  current_param$model = paste0("PCAthen", current_param$model)
                  
                  time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
                  stepm = paste(steptmp, paste0("model:", current_param$model))
                  print(paste0(time,'- ', stepm))
                  
                  
                  
                  keep = which(names(dtf) %in% c("attacked"))
                  keep_simple <- setdiff(names(dtf), c(remove_detail, "protocol", "attacked")) #-which(names(dtf) %in% remove_detail)
                  prev_dtf = copy(dtf)
                  new_dim = ncol(dtf)#((dim(dtf))[2])
                  
                  dtf_pca <- FactoMineR::PCA(as.data.frame(dtf[, ..keep_simple]), ncp = new_dim, graph = FALSE, quali.sup = keep)
                  print(paste0("dim: ", new_dim, "-dim pca: ", dtf_pca[["call"]][["ncp"]]))
                  # plot(dtf_pca, choix = "ind", habillage = 4, 
                  #      label = "none", invisible = "quali")
                  dtf = as.data.table((dtf_pca$ind$coord))
                  dtf[, attacked := prev_dtf$attacked]
                  
                  c(train_set, test_set) %<-% partition(
                    dtf,
                    unsupervised = (model$params)$unsupervised_partition,
                    p = (model$params)$p_partition, 
                    do_pca = current_param$do_pca,
                    is_timeserie = (model$params)$is_timeserie,
                    current_param = current_param
                  )
                  main_params$my_seed <- current_param$my_seed
                  dtf= prev_dtf
                  c(tmp_score, test_set_model) %<-% model$model_function(train_set, test_set, current_param)
                  tmp = cbind(
                    tmp_group,
                    tmp_score
                  )
                  dtf_err_model <- rbindlist(list(dtf_err_model, tmp), use.names = TRUE, fill = TRUE)#rbind(dtf_err_model, tmp)
                }
                dtf_err_model[, nb_packets := current_param$nb_packets]
                dtf_err_model[, packet_length := opt$packetSize] #substr(prefix_packetlength , 1, nchar(prefix_packetlength) - 1)]
                dtf_err_model[, testattheend := current_param$testattheend]
                dtf_err_model[, comment := current_param$comment]
                dtf_err_model[, seed := current_param$my_seed]
                # dtf_err_model$nb_packets= current_param$nb_packets
                # dtf_err_model$packet_length = substr(prefix_packetlength, 1, nchar(prefix_packetlength)-1)
                # dtf_err_model$with_queue = main_params$with_queue
                # dtf_err_model$with_alea = main_params$with_alea
                dtf_err_model[, temporal_cov := use_temporal_covariates]
                dtf_err_model[, cross_seed := isTRUE(current_param$cross_seed)]
                
                # Save results
                file_name <- paste0(output_model,
                                    "_error_model.csv")
                write.table(dtf_err_model, file_name, sep = ",", append = TRUE, row.names = FALSE, col.names = !file.exists(file_name))
                gc()
                # Save results
                if (main_params$store_test)
                {
                  file_name <- paste0(output_model,
                                      "_error_test-set.csv")
                  write.table(test_set_model, file_name, sep = ",", append = TRUE, row.names = FALSE, col.names = !file.exists(file_name))
                }
                print(as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
                
                if ((model$params)$is_timeserie)
                {
                  dtf = dtf_no_timeseries
                }
              }
              
              
              
              
            }
            
          }
        }
        rm(list = intersect(c("a0_output_H", "a0_output_D", 
                              "a1_input_H", "a1_input_D", 
                              "a0_a1_H", "a0_a1_D", 
                              "df_healthy", "df_detour"), ls()))
        gc()
      }
      
    }
    rm(tmp_att_trace)
  }
  rm(tmp_hop_trace)
  
}
rm(tmp_proto_trace)
if (exists("merge_queue")) rm(merge_queue)
if (exists("merge_bandwidth")) rm(merge_bandwidth)












# #sink()
# stopCluster(cl) # fermer le cluster

