# Define model configurations ####
train_partition = 0.7
models_list <- list(
  list( #1
    name = "CAH", model_function = do_cah, params = list(unsupervised_partition = FALSE, p_partition = 1, is_timeserie = FALSE)),
  list( #2
    name = "CART", model_function = do_cart, params = list(unsupervised_partition = FALSE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #3
    name = "DBSCAN", model_function = do_dbscan, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #4
    name = "ISOF", model_function = do_isolationforest, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #5
    name = "KMEANS", model_function = do_kmeans, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #6
    name = "LOF", model_function = do_lof, params = list(unsupervised_partition = FALSE, p_partition = 1, is_timeserie = FALSE)),
  list( #7
    name = "OCSVM", model_function = do_oneclasssvm, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #8
    name = "REGLOG", model_function = do_reg_log, params = list(unsupervised_partition = FALSE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #9
    name = "RF", model_function = do_randomforest, params = list(unsupervised_partition = FALSE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #10
    name = "SVM", model_function = do_svm, params = list(unsupervised_partition = FALSE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #11
    name = "XGBOOST", model_function = do_xgboost, params = list(unsupervised_partition = FALSE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #12
    name = "PCAthenKMEANS", model_function = do_pcathenkmeans, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #13
    name = "AE_SIMPLE", model_function = do_ae_simple, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #14
    name = "AE_CLASS", model_function = do_ae_binary, params = list(unsupervised_partition = FALSE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #15
    name = "VAE", model_function = do_vae, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #16
    name = "DAE", model_function = do_dae, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #17
    name = "AE_SPARSE", model_function = do_ae_sparse, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #18
    name = "AE_CONTRACTIVE", model_function = do_ae_contractive, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #19
    name = "AE_LSTM", model_function = do_ae_lstm, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = TRUE)),
  list( #20
    name = "AE_CONV1D", model_function = do_ae_conv1d, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = TRUE)),
  list( #21
    name = "INTERVAL", model_function = do_interval, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #22
    name = "THRESHOLD", model_function = do_threshold, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE)),
  list( #23
    name = "INTERVAL_DELAY", model_function = do_interval_delay, params = list(unsupervised_partition = TRUE, p_partition = train_partition, is_timeserie = FALSE))
)


ordered_hop = c("A0 - linked ...", "D0 - linked ...","E0 - linked D0", 
                "D0 - linked E0", "D0 - linked D2","D2 - linked D0", 
                "E2 - linked D2", "D2 - linked E2", "D2 - linked D1", 
                "D1 - linked D2", "D0 - linked D1", "D1 - linked D0", 
                "D1 - linked A1", "A1 - linked D1",  "D1 - linked E1",
                "E1 - linked D1")
ordered_parasite_rate = c("1Mbps", "10Mbps","20Mbps", #"24Mbps", 
                          "30Mbps","40Mbps", #"48Mbps", 
                          "50Mbps", "60Mbps", "70Mbps", #"72Mbps", 
                          "80Mbps", "90Mbps", #"96Mbps", 
                          "100Mbps", "110Mbps", "120Mbps", "130Mbps", "140Mbps",# "144Mbps",
                          "150Mbps", "160Mbps", #"168Mbps", 
                          "170Mbps","180Mbps", "190Mbps",#"192Mbps", 
                          "200Mbps", "210Mbps", #"216Mbps",
                          "220Mbps","230Mbps","240Mbps")
col_commun <- c("simulation_time", "extra_router", "extra_detour", 
                "latency", "bandwidth", "data_rate", "parasite_rate", 
                "packet_size", "proto", "src_ip", "dst_ip", "ip_id", 
                "protocol", "src_port", "dst_port", "length", "source_file", "meanexp", "meanexppara")
# columns to remove for model analysis
remove_col <- c("attacked", "index", "packet_length", "dst_ip", "src_port", 
                "dst_port", "group_num", "protocol", "run_id")

remove_col_summary <- c(remove_col, "t_start", "t_end", "flow_size")
#, "meanexp", "meanexppara", 
# "ip_id", "end_packet_num")

remove_col_svm <- c("attacked", "src_ip", "dst_ip", "src_port", "dst_port", "group_num", "index","run_id")
remove_col_super <- c(remove_col_svm, "t_start", "t_end", "run_id")

remove_detail <- c("src_ip", "dst_ip", "src_port", "dst_port", 
                   "simulation_time", "extra_detour", 
                   "latency", "bandwidth", "data_rate", "parasite_rate", 
                   "proto")#, "meanexp", "meanexppara")

numeric_col <- c("packet_length", "t_start", "t_end", "flow_size", "fmin_delay",
                 "fFstQ_delay", "fmedian_delay", "fmean_delay", "fTrdQ_delay"
                 , "fmax_delay", "fvar_delay", "fsd_delay", "packet_size", 
                 "delay", "fsd_diff_delay" , "fsderror_delay" , "fmad_delay"
                 , "fminmax_delay", "fIQR_delay", "fskew_delay", 
                 "fkurtosis_delay", "fmean_mean" , "fmedian_median"
                 , "diff_mean", "diff_median", "diff_min", "diff_max")
batch_size<- 8
epochs <- 500

# Ablation des covariables temporelles (instruction C)
# TRUE  = comportement actuel (t_start et t_end conservés)
# FALSE = ablation
#use_temporal_covariates <- TRUE


reduced_feature_set <- NULL   # ou readRDS("reduced_features_k12.rds")