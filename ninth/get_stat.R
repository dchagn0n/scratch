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
library (cluster) #
library(corrplot)
library(dendextend)
library(digest)
library(DescTools)
library(e1071)
library(factoextra)
library(FactoMineR) # PCA and HPC
library(getip) # getip address
library(ggplot2)
#library(glmnet)
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
for (pkg in c("pROC", "ggcorrplot", "viridis")) {
  if (!requireNamespace(pkg, quietly = TRUE))
    install.packages(pkg, repos = "https://cloud.r-project.org")
  library(pkg, character.only = TRUE)
}

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
  make_option(c("-e", "--evolution"), type = "logical", default = F,
              help = "Test on unknown scenarios", metavar = "EVOLUTION"),
  make_option(c("-i", "--trainonparasite"), type = "character", default = "60Mbps",
              help = "Parasite rate of the training set", metavar = "TRAINONPARASITE"),
  make_option(c("-d", "--trainondetour"), type = "integer", default = 5,
              help = "Detour length of the training set", metavar = "TRAINONDETOUR"),
  make_option(c("-p", "--trainonpath"), type = "integer", default = 0,
              help = "Path length of the training set", metavar = "TRAINONPATH"),
  make_option(c("-c", "--comment"), type = "character", default = "",
              help = "Any comment or precision about the simulation", metavar = "COMMENT")
)

# Create the parser object
opt_parser <- OptionParser(option_list = option_list)
# Parse the arguments
opt <- parse_args(opt_parser)

print( ipaddr)
# if (ipaddr == "192.168.186.24")
# {

prefix_m = paste0(opt$repertory, "/T", sprintf(opt$simulationTime, fmt = '%#.6f'), "s_L", opt$latency, 
                  "_B", opt$bandwidth, "_Ra", opt$dataRateAccess, #"_Re", opt$dataRateExt,
                  "_P", opt$packetSize, "b_Ma" , sprintf(opt$meanExpo, fmt = '%#.6f') , 
                  "_Me", sprintf(opt$meanExpoPara, fmt = '%#.6f') , "_merge_path")#", opt$name) #"_",opt$comment,
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

model_tmp = models_list[c(8,10,11,15,16,22,23)] #22,23,10,2,11,8,5,4,16,15,17,19,20)] #11,16,  19, 20, 2, 4, 5, 8,  15, 17,23,22, 13,14,10)] #  7)] #
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
only_synthese = T
if (ipaddr == "192.168.186.24")
{
  do_graph = T #F#
  do_print = F
  do_pdf = T #F#
  do_queue = F#T #F#
  do_flow = F
  only_synthese = T #F#
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
  do_queue = F #T #F#
  do_flow = F
  only_synthese = F #T #F#
}else{
  do_graph = F#
  do_print = F
  do_pdf = F#
  do_queue = F#
  do_flow = F
  only_synthese = F#
}

src = "10.1.10.1"
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

df_healthy <- df[src_ip == src & dst_ip == "10.1.2.1"]

l_nb_hops <- unique(df[, extra_router])
#l_nb_hops <- setdiff(l_nb_hops , c(0, 10))
#l_nb_hops <- 7
l_nb_att <- unique(df[, extra_detour])
#l_nb_att <- setdiff(l_nb_att , c(0, 1,10,2,3))
l_proto = unique(df[["proto"]]) #c( "Udp", "Tcp")
l_parasite_rate = unique(df[, parasite_rate])
print(paste0("optname:", opt$name))

if ("detour" == opt$name | "path" == opt$name)
{
  #l_parasite_rate = l_parasite_rate[! l_parasite_rate %in% c('120Mbps')]
  l_parasite_rate = l_parasite_rate[ l_parasite_rate %in%c("60Mbps")] #, "40Mbps", "120Mbps")] #"1Mbps", ,"80Mbps","110Mbps","120Mbps", "140Mbps"
}
if ("detour" == opt$name | "parasite" == opt$name)
{
  l_nb_hops = l_nb_hops[ l_nb_hops %in%c(0)] #, 6)] #,5)]#,10, 30)]
}
if ("path" == opt$name | "parasite" == opt$name)
{
  l_nb_att = l_nb_att[ l_nb_att %in%c(0)] #, 6)]#,5)]#,10)]#,30)]
}
if ("testattheend" == opt$name)
{
  l_parasite_rate = l_parasite_rate[ l_parasite_rate %in%c("1Mbps", "60Mbps","80Mbps","110Mbps","120Mbps", "140Mbps")]
  l_nb_hops = l_nb_hops[ l_nb_hops %in%c(0,5)]#,10, 30)]
  l_nb_att = l_nb_att[ l_nb_att %in%c(0,5)]#,10)]#,30)]
}
# if ("detour" == opt$name){
#   l_nb_att = l_nb_att[ l_nb_att %in%c(0,1,2,3)]
# }
print(main_params$do_evolution)
if (main_params$do_evolution)
{
  l_parasite_rate <- unique (c(main_params$trainonparasite, l_parasite_rate))
  l_nb_hops <- unique (c(main_params$trainonpath, l_nb_hops))
  l_nb_att <- unique (c(main_params$trainondetour, l_nb_att))
}
print(l_parasite_rate)
print(l_nb_hops)
print(l_nb_att)

# if ("total" == opt$name)
# {
#   # # pour paraiste
#   # l_nb_hops = l_nb_hops[ l_nb_hops %in%c(0)]
#   # l_nb_att = l_nb_att[ l_nb_att %in%c(0)]
#   
#   # pour chemin
#   l_nb_att = l_nb_att[ l_nb_att %in%c(0)]
#   l_parasite_rate = l_parasite_rate[ l_parasite_rate %in%c("120Mbps")]
#   
#   # # pour detour
#   # l_nb_hops = l_nb_hops[ l_nb_hops %in%c(0)]
#   # l_parasite_rate = l_parasite_rate[ l_parasite_rate %in%c("120Mbps")]
# }

# if ("parasite" == opt$name)
# {
#   l_parasite_rate = l_parasite_rate[ l_parasite_rate %in%c("40Mbps","50Mbps", "60Mbps", "70Mbps","80Mbps", "90Mbps")]
# }


proto = l_proto[1]
nb_hops = l_nb_hops[1]
nb_att = l_nb_att[1]
parasite_rate = l_parasite_rate [1]

#l_nb_att <- c(-1, l_nb_att)

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
)

prop_att = main_params$prop_att
output_sim <- paste0(output_dir, "_sim", prefix_time,"_/")
dir.create(output_sim, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas




# start of for loop #### 
# # batch loop ####
# batch_size = 60
# min_timestamp = min (df[,timestamp])
# nb_batch = round((max(df[,timestamp])- min_timestamp) / batch_size)
# for (batch in seq(1, nb_batch)){
#   first_index = which(df[,timestamp] <= (batch)*batch_size)[1]
#   last_index = which(df[,timestamp] > 5*batch_size + min_timestamp)[1]
#   tmp_batch_trace <- df[timestamp>= (batch-1)*batch_size & timestamp <= batch*batch_size + min_timestamp]
#   tmp_batch_trace <- df[seq(0, last_index-1),]
#   
#   print(batch)
# }


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
    print("nb_hops:")
    print(unique(tmp_hop_trace[,extra_router]))
    
    if (nrow(tmp_hop_trace) == 0)
    {
      next
    }
    #### nb_att loop ####
    for (nb_att in l_nb_att)
    {
      current_param$nb_att = nb_att
      
      time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
      stepa = paste(steph, paste0("nb_att:", nb_att))
      print(paste0(time, "- ", stepa))
      
      output_att <- paste0(output_hops, "_att", nb_att,"_/")
      dir.create(output_att, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas
      
      local_nb_att <- nb_att
      tmp_att_trace <- tmp_hop_trace[extra_detour == local_nb_att]
      print("nb_att:")
      print(unique(tmp_att_trace[,extra_detour]))
      
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
        print("parasite_rate:")
        print(unique(tmp_rate_trace[,parasite_rate]))
        print (paste0("tmp_rate:", nrow(tmp_rate_trace)))
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
        prefix <- paste0(prefix_rep, "/T",prefix_time, "_h", nb_hops, "_a", nb_att, 
                         "_L", prefix_latency, "_B", prefix_bandwidth, 
                         "_Ra", prefix_rateaccess, "_Re", parasite_rate,
                         "_P", prefix_packetlength,"_",proto, "_Ma", prefix_meanexp, "_Me", prefix_meanexppara, "_")
        print(paste0("prefix = ", prefix))
        ##print(unique(df_healthy[,file]))
        ## healthy path
        a0_output_H <- df_healthy[file==paste0(prefix,"trace-access0-access_access0-0-0.pcap")]
        print(unique (a0_output_H[,file]))
        if (identical(unique (a0_output_H[,file]), character(0)))
        {
          print("ERROR DATASET")
          file_name <- paste0("_error_dataset.csv")
          write.table(paste0(time, "- ", stepr), file_name, sep = ",", append = TRUE, row.names = F)
          write.table(paste0(prefix,"trace-access0-access_access0-0-0.pcap"), file_name, sep = ",", append = TRUE, row.names = F)
          next
        }
        #d0_input_H <- df_healthy[df_healthy$file==paste0("scratch/",prefix,"trace-access-dist0_dist0-2-0.pcap"),]
        #d0_output_H <- df_healthy[df_healthy$file==paste0("scratch/",prefix,"trace-dist0-dist1_dist0-2-1.pcap"),]
        #d1_input_H <- df_healthy[df_healthy$file==paste0("scratch/",prefix,"trace-dist0-dist1_dist1-3-2.pcap"),]
        #d1_output_H <- df_healthy[df_healthy$file==paste0("scratch/",prefix,"trace-dist1-access1_dist1-3-0.pcap"),]
        a1_input_H <- df_healthy[file==paste0(prefix,"race-dist1-access1-direct_access1-1-0.pcap")]
        print(unique (a1_input_H[,file]))
        if (identical(unique (a1_input_H[,file]), character(0)))
        {
          print("ERROR DATASET")
          file_name <- paste0("_error_dataset.csv")
          write.table(paste0(time, "- ", stepr), file_name, sep = ",", append = TRUE, row.names = F)
          
          write.table(paste0(prefix,"race-dist1-access1-direct_access1-1-0.pcap"), file_name, sep = ",", append = TRUE, row.names = F)
          next
        }
        ##print(head(a0_output_H))
        #a0_d1_H <- fusion_starttoend(end = d1_input_H, start = a0_output_H, "healthy")
        #d0_a1_H <- fusion_starttoend(end = a1_input_H, start = d0_output_H, "healthy")
        a0_a1_H <- fusion_starttoend(end = a1_input_H, start = a0_output_H, "healthy")
        #d0_d1_H <- fusion_starttoend(end = d1_input_H, start = d0_input_H, "healthy")
        #d0_H <- fusion_starttoend(end = d0_output_H, start = d0_input_H, "healthy")
        
        ## detour path
        a0_output_D <- df_detour[file==paste0(prefix,"trace-access0-access_access0-0-0.pcap")]
        print(unique (a0_output_D[,file]))
        if (identical(unique (a0_output_D[,file]), character(0)))
        {
          print("ERROR DATASET")
          
          file_name <- paste0("_error_dataset.csv")
          write.table(paste0(time, "- ", stepr), file_name, sep = ",", append = TRUE, row.names = F)
          
          write.table(paste0(prefix,"trace-access0-access_access0-0-0.pcap"), file_name, sep = ",", append = TRUE, row.names = F)
          next
        }
        # d0_input_D <- df_detour[df_detour$file==paste0("scratch/",prefix,"trace-access-dist0_dist0-2-0.pcap"),]
        # d0_output_D <- df_detour[df_detour$file==paste0("scratch/",prefix,"trace-dist0-dist2_dist0-2-2.pcap"),]
        # d1_input_D <- df_detour[df_detour$file==paste0("scratch/",prefix,"trace-dist2-dist1_dist1-3-3.pcap"),]
        # d1_output_D <- df_detour[df_detour$file==paste0("scratch/",prefix,"trace-dist1-access1_dist1-3-1.pcap"),]
        a1_input_D <- df_detour[file==paste0(prefix,"trace-dist1-access1-detour_access1-1-1.pcap")]
        print(unique (a1_input_D[,file]))
        if (identical(unique (a1_input_D[,file]), character(0)))
        {
          print("ERROR DATASET")
          file_name <- paste0("_error_dataset.csv")
          write.table(paste0(time, "- ", stepr), file_name, sep = ",", append = TRUE, row.names = F)
          
          write.table(paste0(prefix,"trace-dist1-access1-detour_access1-1-1.pcap"), file_name, sep = ",", append = TRUE, row.names = F)
          next
        }
        # a0_d1_D <- fusion_starttoend(end = d1_input_D, start = a0_output_D, "detour")
        # d0_a1_D <- fusion_starttoend(end = a1_input_D, start = d0_output_D, "detour")
        a0_a1_D <- fusion_starttoend(end = a1_input_D, start = a0_output_D, "detour")
        # d0_d1_D <- fusion_starttoend(end = d1_input_D, start = d0_input_D, "detour")
        # d0_D <- fusion_starttoend(end = d0_output_D, start = d0_input_D, "detour")
        
        lookup <- c(t_start = "start_timestamp", packet_length = "length", attacked = "type", delay = "delay_path", t_end = "end_timestamp")
        print("check2")
        print(nrow(a0_a1_D))
        print(nrow(a0_a1_H))
        # Fusion verticale
        a0_a1 <- rbindlist(list(a0_a1_D, a0_a1_H))
        a0_a1[, c("start_file", "end_file", "source_file", "start_packet_num") := NULL]
        # Inverser lookup pour setnames (data.table veut: old -> new)
        new_names <- names(lookup)
        old_names <- unname(lookup)
        setnames(a0_a1, old = old_names[old_names %in% names(a0_a1)], new = new_names[old_names %in% names(a0_a1)])
        # Recoder 'attacked' : "detour" -> 1, "healthy" -> 0
        a0_a1[, attacked := fifelse(attacked == "detour", 1L, 0L)]
        # Convertir en facteur
        a0_a1[, attacked := factor(attacked)]
        print(unique (a0_a1[,attacked]))
        print(paste("0:",nrow(a0_a1[attacked == 0])) )
        print(paste("1:",nrow(a0_a1[attacked == 1])))
        print(paste("a0, a1:",nrow(a0_a1)))
        # a0_a1 <- rbind(a0_a1_D, a0_a1_H) %>% 
        #   select(- c(start_file, end_file, source_file, start_packet_num)) %>%
        #   rename(any_of(lookup)) %>%
        #   mutate (attacked = recode (attacked, "detour" = 1, "healthy" = 0)) %>%
        #   mutate_at (c('attacked'), as.factor)
        ##### do graph ####
        if (nrow(a0_a1) == 0)
        {
          print("je next a0_a1")
          next
        }
        
        if (do_graph)
        {
          ## delay analysis
          
          delaya0a1 = ggplot(a0_a1, aes(x = t_start, y = delay, color = attacked, shape = attacked)) +
            geom_point(linewidth= 1)+
            labs(title = paste0(prefix, "\nDelay between A0 and A1"),
                 x = "Timestamps (s)", y = "Delay (s)",
                 color = "attacked") +  # Title for the legend
            ylim(c(0, max(a0_a1$delay)))+
            xlim(c(0, max(a0_a1$t_start)))+
            scale_color_manual(values = c("1" = "darkred", "0" = "blue")) +
            scale_shape_manual(values = c("1" = 3, "0" = 4)) +
            theme_minimal()
          
          logdelaya0a1 = ggplot(a0_a1, aes(x = t_start, y = log10(delay), color = attacked, shape = attacked)) +
            geom_point(linewidth= 1)+
            labs(title = paste0(prefix, "\nDelay between A0 and A1"),
                 x = "Timestamps (s)", y = "Log (delay)",
                 color = "attacked") +  # Title for the legend
            ylim(c(min(log10(a0_a1$delay)), max(log10(a0_a1$delay))))+
            xlim(c(0, max(a0_a1$t_start)))+
            scale_color_manual(values = c("1" = "darkred", "0" = "blue")) +
            scale_shape_manual(values = c("1" = 3, "0" = 4)) +
            theme_minimal()
          
          if (do_queue)
          {
            ## queue analysis
            object.size(merge_queue)
            print(dim(merge_queue))
            tmp_proto_queue <- merge_queue[proto == local_proto]
            print(dim(tmp_proto_queue))
            tmp_hop_queue <- tmp_proto_queue[extra_router == local_nb_hops]
            print(dim(tmp_hop_queue))
            
            tmp_att_queue <- tmp_hop_queue[extra_detour == local_nb_att]            
            print(dim(tmp_att_queue))
            
            tmp_rate_queue <- tmp_att_queue[parasite_rate == local_parasite_rate]
            print(dim(tmp_rate_queue))
            
            rm (tmp_proto_queue, tmp_hop_queue, tmp_att_queue)
            print("test queue rate:")
            print(colnames(tmp_rate_queue))
            print(parasite_rate)
            
            print(unique(tmp_rate_queue$hop))
            max_inqueue <- max(tmp_rate_queue[hop == "D0 - linked D1" | hop == "D0 - linked D2" | hop == "D1 - linked A1" ,"nb_inqueue"])
            q_d0_d1 <- tmp_rate_queue[hop == "D0 - linked D1"]
            
            print(unique(q_d0_d1[,proto]))
            print(unique(q_d0_d1[,extra_router]))
            print(unique(q_d0_d1[,extra_detour]))
            print(unique(q_d0_d1[,parasite_rate]))
            print(unique(q_d0_d1[,hop]))
            
            queued0d1 <- ggplot(q_d0_d1, aes(x = time, y = nb_inqueue)) +
              geom_line(linewidth = 0.2) +
              geom_point(shape=4, linewidth = 0.5) +
              labs(title = paste0(prefix, "\nQueue Size of D0, Interface link with D1"),
                   x = "Timestamps (s)", y = "Queue size (number of packets)") +  
              xlim(c(0, max(q_d0_d1$time)))+
              ylim(0,max_inqueue) +
              theme_minimal()
            rm (q_d0_d1)
            q_d0_d2 <- tmp_rate_queue[hop == "D0 - linked D2"]
            print(unique(q_d0_d2[,proto]))
            print(unique(q_d0_d2[,extra_router]))
            print(unique(q_d0_d2[,extra_detour]))
            print(unique(q_d0_d2[,parasite_rate]))
            print(unique(q_d0_d2[,hop]))
            queued0d2 <- ggplot(q_d0_d2, aes(x = time, y = nb_inqueue)) +
              geom_line(linewidth = 0.2) +
              geom_point(shape=4, linewidth = 0.5) +  labs(title = paste0(prefix, "\nQueue Size of D0, Interface link with D2"),
                                                      x = "Timestamps (s)", y = "Queue size (number of packets)") +  # Title for the legend
              xlim(c(0, max(q_d0_d2$time)))+
              ylim(0,max_inqueue) +
              theme_minimal()
            rm (q_d0_d2)
            
            q_a1_d1 <- tmp_rate_queue[hop == "A1 - linked D1"]
            q_a1_d1_direct <- q_a1_d1[path == "direct"]
            print(unique(q_a1_d1_direct[,proto]))
            print(unique(q_a1_d1_direct[,extra_router]))
            print(unique(q_a1_d1_direct[,extra_detour]))
            print(unique(q_a1_d1_direct[,parasite_rate]))
            print(unique(q_a1_d1_direct[,hop]))
            print(unique(q_a1_d1_direct[,path]))
            queuea1_d1_direct <- ggplot(q_a1_d1_direct, aes(x = time, y = nb_inqueue)) +
              geom_line(linewidth = 0.2) +
              geom_point(shape=4, linewidth = 0.5) +  labs(title = paste0(prefix, "\nQueue Size of A1, Interface link with D1, direct link"),
                                                      x = "Timestamps", y = "Queue size (number of packets)") +  # Title for the legend
              xlim(c(0, max(q_a1_d1_direct$time)))+
              ylim(0,max_inqueue) +
              theme_minimal()
            rm (q_a1_d1_direct)
            q_a1_d1_detour <- q_a1_d1[path == "detour"]
            print(unique(q_a1_d1_detour[,proto]))
            print(unique(q_a1_d1_detour[,extra_router]))
            print(unique(q_a1_d1_detour[,extra_detour]))
            print(unique(q_a1_d1_detour[,parasite_rate]))
            print(unique(q_a1_d1_detour[,hop]))
            print(unique(q_a1_d1_detour[,path]))
            queuea1_d1_detour <- ggplot(q_a1_d1_detour, aes(x = time, y = nb_inqueue)) +
              geom_line(linewidth = 0.2) +
              geom_point(shape=4, linewidth = 0.5) +  labs(title = paste0(prefix, "\nQueue Size of A1, Interface link with D1, detour link"),
                                                      x = "Timestamps (s)", y = "Queue size (number of packets)") +  # Title for the legend
              xlim(c(0, max(q_a1_d1_detour$time)))+
              ylim(0,max_inqueue) +
              theme_minimal()
            rm (q_a1_d1_detour, q_a1_d1)
            
            
            q_d1_a1 <- tmp_rate_queue[hop == "D1 - linked A1"]
            q_d1_a1_direct <- q_d1_a1[path == "direct"]
            print(unique(q_d1_a1_direct[,proto]))
            print(unique(q_d1_a1_direct[,extra_router]))
            print(unique(q_d1_a1_direct[,extra_detour]))
            print(unique(q_d1_a1_direct[,parasite_rate]))
            print(unique(q_d1_a1_direct[,hop]))
            print(unique(q_d1_a1_direct[,path]))
            queued1_a1_direct <- ggplot(q_d1_a1_direct, aes(x = time, y = nb_inqueue)) +
              geom_line(linewidth = 0.2) +
              geom_point(shape=4, linewidth = 0.5) +  labs(title = paste0(prefix, "\nQueue Size of D1, Interface link with A1, direct link"),
                                                      x = "Timestamps (s)", y = "Queue size (number of packets)") +  # Title for the legend
              xlim(c(0, max(q_d1_a1_direct$time)))+
              ylim(0,max_inqueue) +
              theme_minimal()
            rm (q_d1_a1_direct)
            q_d1_a1_detour <- q_d1_a1[path == "detour"]
            print(unique(q_d1_a1_detour[,proto]))
            print(unique(q_d1_a1_detour[,extra_router]))
            print(unique(q_d1_a1_detour[,extra_detour]))
            print(unique(q_d1_a1_detour[,parasite_rate]))
            print(unique(q_d1_a1_detour[,hop]))
            print(unique(q_d1_a1_detour[,path]))
            queued1_a1_detour <- ggplot(q_d1_a1_detour, aes(x = time, y = nb_inqueue)) +
              geom_line(linewidth = 0.2) +
              geom_point(shape=4, linewidth = 0.5) +  labs(title = paste0(prefix, "\nQueue Size of D1, Interface link with A1, detour link"),
                                                      x = "Timestamps (s)", y = "Queue size (number of packets)") +  # Title for the legend
              xlim(c(0, max(q_d1_a1_detour$time)))+
              ylim(0,max_inqueue) +
              theme_minimal()
            rm (q_d1_a1_detour, q_d1_a1, tmp_rate_queue)
            
            
            ## data rate analysis
            tmp_proto_bandwidth <- merge_bandwidth[proto == local_proto]
            tmp_hop_bandwidth <- tmp_proto_bandwidth[extra_router == local_nb_hops]
            tmp_att_bandwidth <- tmp_hop_bandwidth[extra_detour == local_nb_att]
            tmp_rate_bandwidth <- tmp_att_bandwidth[parasite_rate == local_parasite_rate]
            rm (tmp_proto_bandwidth, tmp_hop_bandwidth, tmp_att_bandwidth)
            print("test bandwidth rate:")
            print(colnames(tmp_rate_bandwidth))
            print(parasite_rate)
            print(unique(tmp_rate_bandwidth[,proto]))
            print(unique(tmp_rate_bandwidth[,extra_router]))
            print(unique(tmp_rate_bandwidth[,extra_detour]))
            print(unique(tmp_rate_bandwidth[,parasite_rate]))
            
            grate <- ggplot(tmp_rate_bandwidth, aes(x = hop, y = data_rate_bps, color = path)) +
              geom_point(shape=4, size = 1) +  labs(title = paste0(prefix, "\nData Rate by hops"),
                                                    x = "Hop", y = "Data Rate (Mbps)") +  
              geom_path(group=tmp_rate_bandwidth$path) +
              theme_minimal()+ 
              theme(
                axis.text.x = element_text( angle = 45, hjust = 1),
              )
            rm (tmp_rate_bandwidth)
          }
          
          
          if (do_flow && exists("tmp_rate_bandwidth"))
          {
            gflowchart <- do_flowchart(tmp_rate_bandwidth, nb_hops, nb_att)
          }
          
          if (do_print)
          {
            print(queued0d2)
            print(delaya0a1)
            print(logdelaya0a1)
            print(queued0d1)
            print(grate)
            if (do_flow)
            {
              print(gflowchart)
            }
          }
          
          if (do_pdf)
          {
            if (do_queue)
            {
              page1 <- queued0d2/
                delaya0a1 /
                queued0d1 
              
              
            }else{
              page1 <- logdelaya0a1/
                logdelaya0a1 /
                delaya0a1 
            }
            
            if (do_queue)
            {
              page2 <- queued1_a1_detour/
                logdelaya0a1 /
                queued1_a1_direct 
              
              
            }else{
              page2 <- delaya0a1 /
                delaya0a1 / 
                logdelaya0a1
            }
            
            if (do_queue)
            {
              page3 <- queuea1_d1_detour/
                delaya0a1 /
                queuea1_d1_direct 
              page5 <- grate
              
            }else{
              page3 <- logdelaya0a1/
                logdelaya0a1 /
                logdelaya0a1 
            }
            
            
            if (do_flow)
            {
              page4 <- (gflowchart)
            }
            pdf(paste0(prefix, "page_synthese_graphes.pdf"), width = 8.27, height = 11.69, compress = TRUE, pointsize = 5)
            print(page1) 
            print(page2)
            print(page3)
            if (do_queue){print(page5)}
            if (do_flow)
            {
              print(page4)
            }
            dev.off()
            rm (page1)
            rm (page2)
            if (do_flow)
            {
              rm(page3)
            }
          }
          rm(list = intersect(c("delaya0a1", "logdelaya0a1", "queued0d1", "queued0d2", "grate", 
                                "queuea1_d1_detour", "queuea1_d1_direct", 
                                "queued1_a1_detour", "queued1_a1_direct"), ls()))
          if (do_flow)
          {
            if (exists("gflowchart")) rm(gflowchart)
          }
        }
        
        
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
            ## completer
            ###### ################## TO PUT BACK #######
            # tmp_size_group_prop = round((prop_att_order[prop_att_order <= prop] * nb_packets))
            # tmp_size_group_inf10000 = which(tmp_size_group_prop <= max_flow)
            # 
            # tmp_comp_size_group_prop = if (length(tmp_size_group_inf10000) < length(tmp_size_group_prop)){
            #   c(tmp_size_group_prop[tmp_size_group_inf10000],
            #     round(seq.int (max(tmp_size_group_prop[tmp_size_group_inf10000]) + 100, max_flow, length.out =5)))
            # } else {
            #   tmp_size_group_prop
            # }
            # size_group <- c(10, round(seq.int (1, (min(prop_att) * nb_packets)-1, length.out =5)), tmp_comp_size_group_prop, -1)
            # size_group <- size_group[size_group != 0]
            # if (proto == "Udp")
            # {
            #   size_group = unique (transform_vector(size_group))
            # }
            # 
            # df <- data.frame(value = size_group, bucket = floor(size_group / 100))
            # unique_per_bucket <- df[!duplicated(df$bucket), "value"]
            # size_group = unique_per_bucket
            # print("size_group: ")
            # print(size_group)
            #'###############################
            
            ########### TO REMOVE ###############
            size_group = c(342, 27,9) # 342, 
            #'#########################
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
              if (nrow(a0_a1[attacked == 0]) == 0 | nrow(a0_a1[attacked == 1]) == 0)
              {
                print("a0_a1 before mix flow empty")
                next
              }
              dtf <- mix_to_flow(dtf_att0 = a0_a1[attacked == 0], dtf_attn = a0_a1[attacked == 1], prop = prop, group)
              
              
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
              ### PB ICI POUR LES ENSEMBLE REDUIT.
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
              
              
              # DT est ton data.table
              
              # 1.1 – Séparation colonnes numériques
              num_vars <- names(dtf)[sapply(dtf, is.numeric)]
              cat_vars <- setdiff(names(dtf), num_vars)
              
              
              
              #1.2 – Statistiques globales
              stats_global <- dtf[, lapply(.SD, function(x) list(
                n = .N,
                min = min(x, na.rm=TRUE),
                q1 = quantile(x, 0.25, na.rm=TRUE),
                median = median(x, na.rm=TRUE),
                mean = mean(x, na.rm=TRUE),
                q3 = quantile(x, 0.75, na.rm=TRUE),
                max = max(x, na.rm=TRUE)
              )), .SDcols = num_vars]
              
              
              print("##### Statistiques globales ####")
              print(str(stats_global))
              
              # Sauvegarde : stats globales
              fwrite(stats_global,
                     file = file.path(output_group, "_stats_global.csv"),
                     sep = ";")
              
              
              # 1.3 – Statistiques selon attacked
              stats_by_class <- dtf[, lapply(.SD, function(x) list(
                min = min(x, na.rm=TRUE),
                q1 = quantile(x, 0.25, na.rm=TRUE),
                median = median(x, na.rm=TRUE),
                mean = mean(x, na.rm=TRUE),
                q3 = quantile(x, 0.75, na.rm=TRUE),
                max = max(x, na.rm=TRUE)
              )), by = attacked, .SDcols = num_vars]
              
              print(str(stats_by_class))
              
              # Sauvegarde : stats par classe (healthy vs detour)
              fwrite(stats_by_class,
                     file = file.path(output_group, "stats_by_class.csv"),
                     sep = ";")
              
              
              
              
              
              ###############################################################################
              # 2. MATRICE DE CORRÉLATION
              ###############################################################################
              
              
              
              # Corrélation sur données complètes
              corr_matrix <- cor(dtf[, ..num_vars], use="pairwise.complete.obs")
              
              pdf( paste0(prefix, "_correlation_matrix.pdf"), width=10, height=10)
              corrplot(corr_matrix, method="color", addCoef.col="black"
                       , number.cex=.3 # taille des chiffres
                       , tl.cex = 0.5) ## tailles des labels
              
              ggcorrplot::ggcorrplot(
                corr_matrix,
                method        = "square",
                type          = "full", #lower",
                lab           = TRUE,
                colors        = c("#2166AC", "white", "#D6604D"),
                outline.color = "gray90",
                tl.cex        = 7,
                hc.order = T
              ) +
                labs(
                  title    = "Spearman correlation between features of benign flows",
                  # subtitle = paste0(
                  #   "Features ordered by family (A to M). ",
                  #   "|rho| > 0.85 indicates redundancy. ",
                  #   sum(c3$unique_info, na.rm = TRUE), "/", nrow(c3),
                  #   " features with max |rho| < 0.85."
                  # ),
                  fill = "Spearman rho"
                ) +
                TH +
                theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 6),
                      axis.text.y = element_text(size = 6))
              dev.off()
              
              # Corrélation pour healthy et detour séparés
              corr_healthy <- cor(dtf[attacked==0, ..num_vars], use="pairwise.complete.obs", method = "spearman")
              corr_detour  <- cor(dtf[attacked==1, ..num_vars], use="pairwise.complete.obs", method = "spearman")
              
              pdf( paste0(prefix, "_correlation_healthy_vs_detour.pdf"), width=12, height=6)
              par(mfrow=c(1,2))
              corrplot(corr_healthy, method="color", main="Healthy Only"
                       , number.cex=.3 # taille des chiffres
                       , tl.cex = 0.5) ## tailles des labels)
              corrplot(corr_detour,  method="color", main="Detour Only"
                       , number.cex=.3 # taille des chiffres
                       , tl.cex = 0.5) ## tailles des labels)
              
              ggcorrplot::ggcorrplot(
                corr_healthy,
                method        = "square",
                type          = "full", #lower",
                lab           = FALSE,
                colors        = c("#2166AC", "white", "#D6604D"),
                outline.color = "gray90",
                tl.cex        = 7,
                hc.order = T
              ) +
                labs(
                  title    = "Spearman correlation between features of benign flows",
                  # subtitle = paste0(
                  #   "Features ordered by family (A to M). ",
                  #   "|rho| > 0.85 indicates redundancy. ",
                  #   sum(c3$unique_info, na.rm = TRUE), "/", nrow(c3),
                  #   " features with max |rho| < 0.85."
                  # ),
                  fill = "Spearman rho"
                ) +
                TH +
                theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 6),
                      axis.text.y = element_text(size = 6))
              
              ggcorrplot::ggcorrplot(
                corr_detour,
                method        = "square",
                type          = "full", #lower",
                lab           = FALSE,
                colors        = c("#2166AC", "white", "#D6604D"),
                outline.color = "gray90",
                tl.cex        = 7,
                hc.order = T
              ) +
                labs(
                  title    = "Spearman correlation between features of detour flows",
                  # subtitle = paste0(
                  #   "Features ordered by family (A to M). ",
                  #   "|rho| > 0.85 indicates redundancy. ",
                  #   sum(c3$unique_info, na.rm = TRUE), "/", nrow(c3),
                  #   " features with max |rho| < 0.85."
                  # ),
                  fill = "Spearman rho"
                ) +
                TH +
                theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 6),
                      axis.text.y = element_text(size = 6))
              dev.off()
              
              
              
              
              
              
              dtf_pca <- PCA(dtf[, ..num_vars], scale.unit=TRUE, graph=FALSE)
              
              pdf(paste0(prefix,"_pca_individuals.pdf"))
              fviz_pca_ind(dtf_pca,
                           habillage=dtf$attacked,
                           palette=c("blue","red"),
                           title="PCA — Healthy vs Detour")
              dev.off()
              
              pdf(paste0(prefix,"_pca_variables.pdf"))
              fviz_pca_var(dtf_pca,
                           col.var="contrib",
                           gradient.cols=c("blue","yellow","red"),
                           title="PCA — Contribution des variables")
              dev.off()
              
              
              
              dist_matrix <- dist(scale(dtf[, ..num_vars]))
              clust <- hclust(dist_matrix, method="ward.D2")
              
              pdf(paste0(prefix,"_cluster_dendrogram.pdf"))
              plot(clust, main="Clustering des flux", xlab="")
              abline(h=mean(clust$height), col="red")
              dev.off()
              
              
              
              
              
              
              
              
              
              
              
              output_pdf <- paste0(prefix,"rapport_complet_dtf.pdf")
              pdf(output_pdf, width = 10, height = 8)
              
              
              #######################
              # Page : Statistiques
              #######################
              plot.new()
              title("Résumé statistique global")
              grid()
              text(0.01, 0.99, paste(capture.output(print(stats_global)), collapse="\n"), adj=c(0,1), cex=0.7)
              
              plot.new()
              title("Résumé statistique par classe (attacked = 0/1)")
              grid()
              text(0.01, 0.99, paste(capture.output(print(stats_by_class)), collapse="\n"), adj=c(0,1), cex=0.7)
              
              #######################
              # Corrélation
              #######################
              corrplot(corr_matrix, method="color", addCoef.col="black"
                       , number.cex=.3 # taille des chiffres
                       , tl.cex = 0.5) ## tailles des labels)
              
              par(mfrow=c(1,2))
              corrplot(corr_healthy, method="color", main="Benign Correlation"
                       , number.cex=.3 # taille des chiffres
                       , tl.cex = 0.5) ## tailles des labels)
              corrplot(corr_detour,  method="color", main="Detour Correlation"
                       , number.cex=.3 # taille des chiffres
                       , tl.cex = 0.5) ## tailles des labels)
              par(mfrow=c(1,1))
              
              
              #######################
              # PCA
              #######################
              fviz_pca_ind(dtf_pca, habillage=dtf$attacked,
                           palette=c("blue","red"), 
                           title="PCA — individus")
              fviz_pca_var(dtf_pca, col.var="contrib",
                           gradient.cols=c("blue","yellow","red"),
                           title="PCA — variables")
              
              
              ######################
              # Clustering
              #######################
              plot(clust, main="Dendrogramme du clustering")
              abline(h=mean(clust$height), col="red")
              
              rect.hclust(clust, k = 4, border = 2:5)
              
              d <- as.dendrogram(clust)
              d <- set(d, "labels", rep("", length(labels(d))))  # retirer labels
              plot(d)
              
              
              
              
              #######################
              # Bonus : distributions
              #######################
              num_vars <- names(dtf)[sapply(dtf, is.numeric)]
              
              for (v in num_vars) {
                g <- ggplot(dtf, aes_string(x=v, fill="attacked", color="attacked")) +
                  geom_density(alpha=0.3) +
                  #geom_histogram(alpha=0.6, bins=40, position="identity") +
                  theme_minimal() +
                  labs(title=paste("Density of", v),
                       x=v, y="Density")
                print(g)
              }
              
              dev.off()
              print(paste("Rapport PDF généré :", output_pdf))
              
              
              
              #' dtf_err_model <- rbindlist(list(dtf_err_model, tmp_score), use.names = TRUE, fill = TRUE)
              #' dtf_err_model[, nb_packets := current_param$nb_packets]
              #' dtf_err_model[, packet_length := opt$packetSize] #substr(prefix_packetlength , 1, nchar(prefix_packetlength) - 1)]
              #' dtf_err_model[, testattheend := current_param$testattheend]
              #' dtf_err_model[, comment := current_param$comment]
              #' dtf_err_model[, seed := current_param$my_seed]
              #' 
              #' # Save results
              #' file_name <- paste0(output_group, "_stat_data.csv")
              #' write.table(dtf_err_model, file_name, sep = ",", append = TRUE, row.names = F)
              #' 
              #' ######## model loop ####
              #' for (model in main_params$models)
              #' {
              #'   current_param$model = model$name
              #'   dtf_err_model <- initialize_dtf()
              #'   
              #'   time = (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
              #'   stepm = paste(steptmp, paste0("model:", model$name))
              #'   print(paste0(time,'- ', stepm))
              #'   
              #'   output_model <- paste0(output_group, "_model", model$name,"_/")
              #'   dir.create(output_model, showWarnings = FALSE)  # Crée le dossier s'il n'existe pas
              #'   
              #'   if ((model$params)$is_timeserie)
              #'   {
              #'     dtf_no_timeseries = dtf
              #'     dtf = a0_a1
              #'   }
              #'   
              #'   #' without pca
              #'   keep <- setdiff(names(dtf), remove_detail)# -which(names(dtf) %in% remove_detail)
              #'   current_param$do_pca = FALSE
              #'   current_param$do_0 = FALSE
              #'   c(train_set, test_set) %<-% partition(
              #'     dtf = dtf[, ..keep],
              #'     unsupervised = (model$params)$unsupervised_partition,
              #'     p = (model$params)$p_partition, 
              #'     do_pca = current_param$do_pca,
              #'     is_timeserie = (model$params)$is_timeserie,
              #'     current_param = current_param
              #'   )
              #'   test_set <- test_set[rowSums(is.na(test_set)) <= ncol(test_set)/2]
              #'   train_set <- train_set[rowSums(is.na(train_set)) <= ncol(train_set)/2]
              #'   main_params$my_seed <- current_param$my_seed
              #'   print(colnames(train_set))
              #'   print(colnames(test_set))
              #'   if (nrow(test_set[attacked==1]) == 0){
              #'     print("no detour in test set")
              #'     next
              #'   }
              #'   
              #'   
              #'   
              #'   
              #'   
              #'   
              #'   c(tmp_score, test_set_model) %<-% model$model_function(train_set, test_set, current_param)
              #'   print("afeter model")
              #'   tmp = cbind(
              #'     tmp_group,
              #'     tmp_score
              #'   )
              #'   #dtf_err_model <- rbind(dtf_err_model, tmp)
              #'   dtf_err_model <- rbindlist(list(dtf_err_model, tmp), use.names = TRUE, fill = TRUE)
              #'   
              #'   
              #'  
              #'   
              #'   dtf_err_model[, nb_packets := current_param$nb_packets]
              #'   dtf_err_model[, packet_length := opt$packetSize] #substr(prefix_packetlength , 1, nchar(prefix_packetlength) - 1)]
              #'   dtf_err_model[, testattheend := current_param$testattheend]
              #'   dtf_err_model[, comment := current_param$comment]
              #'   
              #'   dtf_err_model[, seed := current_param$my_seed]
              #'   # dtf_err_model$nb_packets= current_param$nb_packets
              #'   # dtf_err_model$packet_length = substr(prefix_packetlength, 1, nchar(prefix_packetlength)-1)
              #'   # dtf_err_model$with_queue = main_params$with_queue
              #'   # dtf_err_model$with_alea = main_params$with_alea
              #'   
              #'   # Save results
              #'   file_name <- paste0(output_model,
              #'                       "_error_model.csv")
              #'   write.table(dtf_err_model, file_name, sep = ",", append = TRUE, row.names = F)
              #'   gc()
              #'   # Save results
              #'   if (main_params$store_test)
              #'   {
              #'     file_name <- paste0(output_model,
              #'                         "_error_test-set.csv")
              #'     write.csv(test_set_model, file_name, append = TRUE, , row.names = F)
              #'   }
              #'   print(as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
              #'   
              #'   
              #' }
              #' 
              
              
              
            }
            
          }
        }
        rm(list = intersect(c("a0_output_H", "a0_output_D", 
                              "a1_input_H", "a1_input_D", 
                              "a0_a1_H", "a0_a1_D", 
                              "df_healthy", "df_detour"), ls()))
        
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

