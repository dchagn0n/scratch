#' Function that generate data when only the path length is changing
#' 
#' 
#' 
#' 
path_change <- function (nb_packet, nb_att)
{
  path = "path_change/"
  for (nb_hops in 1:64)
  {
    c(parameters, complete_data, data_delay) %<-% initialisaton(nb_packets, nb_hops)
    c(complete_data, data_delay) %<-% delay_before(parameters, complete_data, data_delay)
    
    c(parameters_attn, complete_data_attn, data_delay_attn, 
      parameters_att0, complete_data_att0, data_delay_att0) %<-% 
      attackninter (nb_att, parameters, complete_data, data_delay)
    id = paste("_id", nb_hops, "-",nb_att, sep = "")
    save_data(parameters_attn, complete_data_attn, data_delay_attn, id, path)
    save_data(parameters_att0, complete_data_att0, data_delay_att0, id, path)
  }
}


#' Function to compute correlation between consecutive flows
corr_between_flows <- function(x, by = c("flow", "packet")) {
  
  by <- match.arg(by)   # ensure correct value
  # Choose the right variable
  varname <- if (by == "flow") "fmean_delay" else "delay"
  #print(as.numeric(x[[varname]]))
  #print(as.numeric(x[["prev"]]))
  
  # Global correlation
  #cor_val <- cor(x = as.double(x[[varname]]), y = as.double(x[["prev"]]), use = "na.or.complete")
  cor_val <- acf(x = c(as.double(x[[varname]]), as.double(x[["prev"]])), na.action = na.omit, plot = FALSE)$acf[2]
  return(cor_val)
}

#' Compute different statistics to help in the analysis
#' @param X_end the final dataset
#' @param by a string describing if we deal with packets or flows set
#' @return the 2 datasets updated with the new statistics
compute_stat <- function(X_end, by="flow")
{
  print("in compute stat")
  # Compute basic stats only on un-attacked flows
  mean_delay <- X_end[attacked == 0, mean(delay, na.rm = TRUE)]
  median_delay <- X_end[attacked == 0, median(delay, na.rm = TRUE)]
  min_delay <- X_end[attacked == 0, min(delay, na.rm = TRUE)]
  max_delay <- X_end[attacked == 0, max(delay, na.rm = TRUE)]
  
  # mean_delay = mean(X_end[X_end$attacked == 0, "delay"])
  # median_delay = median(X_end[X_end$attacked == 0, "delay"], na.rm = TRUE)
  # min_delay = min(X_end[X_end$attacked == 0, "delay"])
  # max_delay = max(X_end[X_end$attacked == 0, "delay"])
  
  if ("flow" == by)
  {
    meanmean_delay <- X_end[attacked == 0, mean(fmean_delay, na.rm = TRUE)]
    medianmedian_delay <- X_end[attacked == 0, median(fmedian_delay, na.rm = TRUE)]
    
    X_end[, fmean_mean := fmean_delay - meanmean_delay]
    X_end[, fmedian_median := fmedian_delay - medianmedian_delay]
    # X_end[, max_min := fmax_delay - fmin_delay] # Optional, uncomment if needed
    
    # meanmean_delay = mean(X_end[X_end$attacked == 0, "fmean_delay"])
    # medianmedian_delay = median(X_end[X_end$attacked == 0, "fmedian_delay"], na.rm = TRUE)
    
    # X_end$fmean_mean <- X_end$fmean_delay - meanmean_delay # from the mean of delay
    # X_end$fmedian_median <- X_end$fmedian_delay - medianmedian_delay
    #X_end$max_min <- X_end$fmax_delay - X_end$fmin_delay
    
    #varname = "fmean_delay"
    
    
  }#else
  #{
    #varname = "delay"
  #}
  
  
  # Add relative difference metrics
  X_end[, `:=`(
    diff_mean = delay - mean_delay,
    diff_median = delay - median_delay,
    diff_min = delay - min_delay,
    diff_max = delay - max_delay
  )]
  #' difference to the mean
  # X_end$diff_mean <- X_end$delay - mean_delay # from the delay
  
  #' difference to the median
  # X_end$diff_median <- X_end$delay - median_delay
  
  # Optional: differences with previous or next values (grouped? sorted?)
  # X_end[, diff_previous := delay - shift(delay, 1, type = "lag")]
  # X_end[, diff_next := delay - shift(delay, 1, type = "lead")]
  #' difference with the previous sample
  #X_end <- X_end %>%  mutate(diff_previous = delay - lag(delay)) 
  
  #' difference with the next sample
  #X_end <- X_end %>%  mutate(diff_next = delay - lead(delay)) 
  
  #' difference with the min and max
  # X_end$diff_min <- X_end$delay - min_delay
  # X_end$diff_max <- X_end$delay - max_delay
  #X_end = na.omit(X_end)
  
  #' autocorrelation between flow
  # setorder(X_end, t_start)
  # X_end[, prev := shift(get(varname), type = "lag")]
  # X_end[, cor_prev := apply(X_end, 1, FUN = corr_between_flows, by)]

  
  print("end compute stat")
  return (X_end)
}


#' Function that create the dataset of packets by putting some detoured packets put in groups in a random order. 
#' @param dtf_att0 the healthy packets without detour
#' @param dtf_attn the detoured packets 
#' @param prop the proportion of attacked packets to put in the final dataset
#' @param size_group the size of each group of detoured packets
#' @return the final dataset with a mix of healthy and detoured packets put in groups placed in a random order.
mix_by_random_flow <- function (dtf_att0, dtf_attn, prop = 0.1, group = 1, start = 1)
{
  set.seed(1997)
  n_packets = nrow(dtf_attn)
  
  proportion_of_attack = round(n_packets * prop)
  nb_groups = round(proportion_of_attack / group)
  
  # Ensure we do not exceed bounds
  max_start <- n_packets - group
  possible_starts <- start:max_start
  if (length(possible_starts) < nb_groups) {
    stop("Not enough space to place all detour groups.")
  }
  sample_starts <- sort(sample(possible_starts, nb_groups, replace = FALSE))
  
  # Generate healthy and detour indices
  v_startn <- sample_starts
  v_endn <- v_startn + group - 1
  
  # Healthy segments: between detour insertions
  v_start0 <- c(start, v_endn + 1)
  v_end0 <- c(v_startn - 1, max_start)
  healthy_idx <- unlist(Map(`:`, v_start0, pmin(v_end0, n_packets)))
  healthy_idx <- healthy_idx[healthy_idx >=0]
  
  # Detoured segments
  detour_idx <- unlist(Map(`:`, v_startn, v_endn))
  
  healthy_idx <- healthy_idx[which(! (healthy_idx %in% detour_idx))]
  
  # Subset the data frames
  keep_att0 <- dtf_att0[healthy_idx, ]
  keep_attn <- dtf_attn[detour_idx, ]
  #dtf_attn[seq_len(length(detour_idx)), ]  # Ensure matching row count
  
  final_df <- rbind(keep_att0, keep_attn)
  final_df <- final_df[order(final_df$t_start), ]
  
  final_df <- compute_stat(final_df, "packet")
  return(final_df)
  
  sample <- sample(c(start:(n_packets-group)), nb_groups, replace=F)
  sample = sample[order(sample)]
  keep_attn = c()
  keep_att0 = c()
  i = 1
  v_start0 = c(start, sample+1+group)
  v_start0 = v_start0[1:length(v_start0)-1]
  v_end0 = sample
  v_startn = sample+1
  v_endn = sample+group
  keep_att0 = dtf_att0[unlist(Map(`:`, v_start0, v_end0)),]
  keep_attn = dtf_attn[unlist(Map(`:`, v_startn, v_endn)),]
  
  X_end = rbind(keep_att0, keep_attn)
  X_end = X_end[ order(X_end$t_start ), ]
  X_end = compute_stat(X_end, "packet")
  return (X_end)
}



#' Generate a list of indices where each group contains exactly 
#' p consecutive indices, 
#' and where these groups are randomly distributed in the interval 1 to n, 
#' without overlap
generate_consecutive_groups <- function(n, p, k = NULL, seed = 42) {
  set.seed(seed)
  
  # Nombre maximal de blocs possibles sans chevauchement
  max_k <- floor(n / p)
  
  if (is.null(k)) {
    k <- max_k
  } else if (k > max_k) {
    stop("Too many groups: they would overlap.")
  }
  
  # Positions de départ possibles pour chaque bloc
  possible_starts <- seq(1, n - p + 1)
  
  # Éviter le chevauchement : on choisit sans remplacement parmi les blocs possibles
  sampled_starts <- sort(sample(possible_starts, k, replace = FALSE))
  
  # Générer les groupes consécutifs
  indices <- unlist(lapply(sampled_starts, function(start) start:(start + p - 1)))
  
  return(indices)
}


generate_variable_consecutive_groups <- function(n, p_vec, seed = 42) {
  set.seed(seed)
  k <- length(p_vec)
  
  # Préparer l'espace disponible : 1 à n
  available <- rep(TRUE, n)
  
  starts <- c()
  
  for (p_i in p_vec) {
    # Positions de départ possibles pour ce bloc
    possible_starts <- which(sapply(1:(n - p_i + 1), function(s) {
      all(available[s:(s + p_i - 1)])
    }))
    
    if (length(possible_starts) == 0) {
      stop("Not enough space left to place a block of size ", p_i)
    }
    
    s <- sample(possible_starts, 1)
    starts <- c(starts, s)
    available[s:(s + p_i - 1)] <- FALSE
  }
  
  # Construire les groupes
  groups <- mapply(function(s, p_i) s:(s + p_i - 1), starts, p_vec, SIMPLIFY = FALSE)
  
  return(unlist(groups))  # ou: unlist(groups) si tu veux un vecteur à plat
}



generate_consecutive_groups_with_ids <- function(n, p_vec, seed = 42) {
  set.seed(seed)
  k <- length(p_vec)
  
  available <- rep(TRUE, n)
  starts <- c()
  group_list <- list()
  
  for (i in seq_len(k)) {
    p_i <- p_vec[i]
    
    # Cherche les positions disponibles
    possible_starts <- which(sapply(1:(n - p_i + 1), function(s) {
      all(available[s:(s + p_i - 1)])
    }))
    
    if (length(possible_starts) == 0) {
      stop("Not enough space to place block ", i, " of size ", p_i)
    }
    
    s <- sample(possible_starts, 1)
    idx <- s:(s + p_i - 1)
    
    available[idx] <- FALSE
    group_list[[i]] <- data.table(index = idx, group_num = i)
  }
  
  result <- rbindlist(group_list)
  return(result)
}


seperate_by_flow <- function(dtf_att0, dtf_attn, prop = 0.1, group = -1, start = 1)
{
  set.seed(1997)
  keep_att0 = dtf_att0[start:.N][order(t_start)]
  keep_attn = dtf_attn[start:.N][order(t_start)]
  
  n_direct = keep_att0[,.N] #nrow(keep_att0)
  
  by = "flow"
  
  #' build the vector of sizes of the flows
  if (-1 == group)#all(
  {
    n_detour = max(1,round((prop / (1-prop)) * dtf_att0[,.N])) #nrow(dtf_att0)
    
    #' On génère un nombre suffisant d'échantillons 
    #' pour s'assurer de dépasser le nombre maximum de flows dont on pourrait avoir besoin
    max_flow_here = min(max_flow, round(dtf_attn[,.N])) #/3
    max_flow_direct = min (max_flow, n_direct)
    #samples <- sample(min_flow:max_flow_here, ceiling((n_packets) /min_flow), replace = TRUE)
    samples <- rzipf(ceiling((dtf_attn[,.N]) /min_flow), max_flow_here, alpha)
    samples_direct <- rzipf(ceiling((n_direct) /min_flow), max_flow_direct, alpha)
    
    cs <- cumsum(as.numeric(samples))
    cs_direct <- cumsum(as.numeric(samples_direct))
    #' keep flow size until we reach the number of packets 
    #' (meaning that each packets belong to a flow)
    idx <- which(cs >= n_detour)[1]
    idx_direct <- which(cs_direct >= n_direct)[1]
    
    size_group <- samples[1:idx]
    size_group_direct <- samples_direct[1:idx_direct]
    
    #' reduce the size of the last flow to match the exact number of packets
    size_group[idx] <- size_group[idx] - (cs[idx] - n_detour)
    size_group_direct[idx_direct] <- size_group_direct[idx_direct] - (cs_direct[idx_direct] - n_direct)
    if (length(size_group) < 4){
      print("PROBLEME: not enough flow")
    }
  }else if (1 == length(group))
  {
    if (1 == group)
    {
      by = "packet"
    }
    n_detour = ceiling((prop/(1-prop)) * ceiling (dtf_att0[,.N] / group))
    #ceiling (nrow(dtf_attn) / group)
    
    size = group
    size_group <- rep(size, n_detour)
    if (sum(size_group) > dtf_attn[,.N]){
      size_group[n_detour] <- size_group[n_detour] -(sum(size_group) - nrow(dtf_attn))
    }
    
    n_direct =  ceiling (nrow(dtf_att0) / group)
    size_group_direct <- rep(group, n_direct)
    if (sum(size_group_direct) > nrow(dtf_att0)){
      size_group_direct[n_direct] <- size_group_direct[n_direct] -(sum(size_group_direct) - nrow(dtf_att0))
    }
    
  }else{
    n_detour = max(1,round((prop / (1-prop)) * dtf_att0[,.N]))
    #' a vector of size of flows was provided. 
    #' check if there are to much size and if yes, reduce them as necessary
    cs <- cumsum(group)
    #' keep flow size until we reach the number of packets 
    #' (meaning that each packets belong to a flow)
    idx <- which(cs >= n_detour)[1]
    idx_direct <- which(cs >= n_direct)[1]
    size_group <- group[1:idx]
    size_group_direct <- group[1:idx_direct]
    
    #' reduce the size of the last flow to match the exact number of packets
    size_group[idx] <- size_group[idx] - (cs[idx] - n_detour)
    size_group_direct[idx_direct] <- size_group_direct[idx_direct] - (cs[idx_direct] - n_direct)
  }
  
  #' give a number of flow to each packets
  print(paste0("before ind_detour:", dtf_attn[,.N]))
  if (0 == dtf_attn[,.N])
  {
    print(paste("length dtf_attn:", dtf_attn[,.N]))
    print(paste("length dtf_att0:", dtf_att0[,.N]))
  }
  ind_detour <- generate_consecutive_groups_with_ids(n = dtf_attn[,.N], p = size_group)
  dtf_attn[, index := .I]
  # Join with ind_detour (on 'index'), and get matching rows
  if (! ("index" %in% colnames(ind_detour)))
  {
    print(paste0("ind_detour: ", str(ind_detour)))
    group_num = rep(seq_len(length(size_group)), times = size_group)
    keep_attn[, group_num := group_num]
  }else
  {
    keep_attn <- dtf_attn[ind_detour, on = "index"]
    keep_attn[, index := NULL]
  }
  
  
  # keep_attn <- dtf_attn %>%
  #   mutate(index = row_number()) %>%
  #   semi_join(ind_detour, by = c("index" = "index")) %>%
  #   left_join(ind_detour, by = "index") %>%
  #   select(-index)  # facultatif
  
  # create flow for healthy packets
  group_num = rep(seq_len(length(size_group_direct)), times = size_group_direct)
  # keep_att0$group_num = group_num
  keep_att0[, group_num := group_num]
  return (list(keep_att0, keep_attn, by))
}

#' Function that create the dataset of flow of packets by grouping a certain number of packets in groups. 
#' @param dtf_att0 the healthy packets without detour
#' @param dtf_attn the detoured packets 
#' @param prop the proportion of attacked packets to put in the final dataset
#' @param group the size of each flow of packets. 
#' if group = -1: random flow size
#' @return the final dataset with a mix of healthy and detoured flows.
mix_to_flow <- function (dtf_att0, dtf_attn, prop = 0.1, group = -1, start = 1)
{
  #' set.seed(1997)
  #' keep_att0 = dtf_att0[start:.N][order(t_start)]
  #' keep_attn = dtf_attn[start:.N][order(t_start)]
  #' 
  #' n_direct = keep_att0[,.N] #nrow(keep_att0)
  #' 
  #' by = "flow"
  #' 
  #' #' build the vector of sizes of the flows
  #' if (-1 == group)#all(
  #' {
  #'   n_detour = max(1,round((prop / (1-prop)) * dtf_att0[,.N])) #nrow(dtf_att0)
  #'   
  #'   #' On génère un nombre suffisant d'échantillons 
  #'   #' pour s'assurer de dépasser le nombre maximum de flows dont on pourrait avoir besoin
  #'   max_flow_here = min(max_flow, round(dtf_attn[,.N])) #/3
  #'   max_flow_direct = min (max_flow, n_direct)
  #'   #samples <- sample(min_flow:max_flow_here, ceiling((n_packets) /min_flow), replace = TRUE)
  #'   samples <- rzipf(ceiling((dtf_attn[,.N]) /min_flow), max_flow_here, alpha)
  #'   samples_direct <- rzipf(ceiling((n_direct) /min_flow), max_flow_direct, alpha)
  #'   
  #'   cs <- cumsum(as.numeric(samples))
  #'   cs_direct <- cumsum(as.numeric(samples_direct))
  #'   #' keep flow size until we reach the number of packets 
  #'   #' (meaning that each packets belong to a flow)
  #'   idx <- which(cs >= n_detour)[1]
  #'   idx_direct <- which(cs_direct >= n_direct)[1]
  #'   
  #'   size_group <- samples[1:idx]
  #'   size_group_direct <- samples_direct[1:idx_direct]
  #'   
  #'   #' reduce the size of the last flow to match the exact number of packets
  #'   size_group[idx] <- size_group[idx] - (cs[idx] - n_detour)
  #'   size_group_direct[idx_direct] <- size_group_direct[idx_direct] - (cs_direct[idx_direct] - n_direct)
  #'   if (length(size_group) < 4){
  #'     print("PROBLEME: not enough flow")
  #'   }
  #' }else if (1 == length(group))
  #' {
  #'   if (1 == group)
  #'   {
  #'     by = "packet"
  #'   }
  #'   n_detour = ceiling((prop/(1-prop)) * ceiling (dtf_att0[,.N] / group))
  #'   #ceiling (nrow(dtf_attn) / group)
  #'   
  #'   size = group
  #'   size_group <- rep(size, n_detour)
  #'   if (sum(size_group) > dtf_attn[,.N]){
  #'     size_group[n_detour] <- size_group[n_detour] -(sum(size_group) - nrow(dtf_attn))
  #'   }
  #'   
  #'   n_direct =  ceiling (nrow(dtf_att0) / group)
  #'   size_group_direct <- rep(group, n_direct)
  #'   if (sum(size_group_direct) > nrow(dtf_att0)){
  #'     size_group_direct[n_direct] <- size_group_direct[n_direct] -(sum(size_group_direct) - nrow(dtf_att0))
  #'   }
  #'   
  #' }else{
  #'   n_detour = max(1,round((prop / (1-prop)) * dtf_att0[,.N]))
  #'   #' a vector of size of flows was provided. 
  #'   #' check if there are to much size and if yes, reduce them as necessary
  #'   cs <- cumsum(group)
  #'   #' keep flow size until we reach the number of packets 
  #'   #' (meaning that each packets belong to a flow)
  #'   idx <- which(cs >= n_detour)[1]
  #'   idx_direct <- which(cs >= n_direct)[1]
  #'   size_group <- group[1:idx]
  #'   size_group_direct <- group[1:idx_direct]
  #'   
  #'   #' reduce the size of the last flow to match the exact number of packets
  #'   size_group[idx] <- size_group[idx] - (cs[idx] - n_detour)
  #'   size_group_direct[idx_direct] <- size_group_direct[idx_direct] - (cs[idx_direct] - n_direct)
  #' }
  #' 
  #' #' give a number of flow to each packets
  #' print(paste0("before ind_detour:", dtf_attn[,.N]))
  #' ind_detour <- generate_consecutive_groups_with_ids(n = dtf_attn[,.N], p = size_group)
  #' dtf_attn[, index := .I]
  #' # Join with ind_detour (on 'index'), and get matching rows
  #' if (! ("index" %in% colnames(ind_detour)))
  #' {
  #'   print(paste0("ind_detour: ", str(ind_detour)))
  #'   group_num = rep(seq_len(length(size_group)), times = size_group)
  #'   keep_attn[, group_num := group_num]
  #' }else
  #' {
  #'   keep_attn <- dtf_attn[ind_detour, on = "index"]
  #'   keep_attn[, index := NULL]
  #' }
  #' 
  #' 
  #' # keep_attn <- dtf_attn %>%
  #' #   mutate(index = row_number()) %>%
  #' #   semi_join(ind_detour, by = c("index" = "index")) %>%
  #' #   left_join(ind_detour, by = "index") %>%
  #' #   select(-index)  # facultatif
  #' 
  #' # create flow for healthy packets
  #' group_num = rep(seq_len(length(size_group_direct)), times = size_group_direct)
  #' # keep_att0$group_num = group_num
  #' keep_att0[, group_num := group_num]
  #' 
  
  c(keep_att0, keep_attn, by) %<-% seperate_by_flow(dtf_att0, dtf_attn, prop, group , start)
  max_group_num = max (keep_att0$group_num, keep_attn$group_num)
  keep_att0 <- keep_att0[group_num < max_group_num]
  keep_attn <- keep_attn[group_num < max_group_num]
  
  #' create flows by computing the difference 
  #' between the arrival time of the last packet 
  #' and the departure of the first packet per flow
  min_t_start_att0 <- keep_att0[, .(min_t_start = min(t_start)), by = group_num][, min_t_start]
  min_t_start_attn <- keep_attn[, .(min_t_start = min(t_start)), by = group_num][, min_t_start]
  
  max_t_end_att0 <- keep_att0[, .(max_t_end = max(t_end)), by = group_num][, max_t_end]
  max_t_end_attn <- keep_attn[, .(max_t_end = max(t_end)), by = group_num][, max_t_end]
  # 
  # min_t_start_att0 <- (aggregate(keep_att0[ , "t_start"], list(keep_att0$group_num), FUN=min))[,-1]
  # min_t_start_attn <- (aggregate(keep_attn[ , "t_start"], list(keep_attn$group_num), FUN=min))[,-1]
  # max_t_end_att0 <- (aggregate(keep_att0[ , "t_end"], list(keep_att0$group_num), FUN=max))[,-1]
  # max_t_end_attn <- (aggregate(keep_attn[ , "t_end"], list(keep_attn$group_num), FUN=max))[,-1]
  
  #' add the mean of packet_length
  # Base summaries per group
  flow_att0 <- keep_att0[, .(
    packet_length = mean(packet_length),
    t_start = min(t_start),
    t_end = max(t_end),
    flow_size = .N,
    fmin_delay = min(delay),
    fQ005_delay = quantile(delay, 0.05, na.rm = TRUE),
    fQ01_delay = quantile(delay, 0.1, na.rm = TRUE),
    fFstQ_delay = quantile(delay, 0.25, na.rm = TRUE),
    fmedian_delay = median(delay),
    fmean_delay = mean(delay),
    fmeanTRIM10_delay = mean(delay, trim = 0.1),
    fTrdQ_delay = quantile(delay, 0.75, na.rm = TRUE),
    fQ09_delay = quantile(delay, 0.9, na.rm = TRUE),
    fQ095_delay = quantile(delay, 0.95, na.rm = TRUE),
    fmax_delay = max(delay),
    fvar_delay = if (.N > 1) var(delay) else NA_real_,
    fsd_delay = if (.N > 1) sd(delay) else NA_real_
  ), by = group_num]
  
  flow_attn <- keep_attn[, .(
    packet_length = mean(packet_length),
    t_start = min(t_start),
    t_end = max(t_end),
    flow_size = .N,
    fmin_delay = min(delay),
    fQ005_delay = quantile(delay, 0.05, na.rm = TRUE),
    fQ01_delay = quantile(delay, 0.1, na.rm = TRUE),
    fFstQ_delay = quantile(delay, 0.25, na.rm = TRUE),
    fmedian_delay = median(delay, na.rm = TRUE),
    fmean_delay = mean(delay, na.rm = TRUE),
    fmeanTRIM10_delay = mean(delay, trim = 0.1, na.rm = TRUE),
    fTrdQ_delay = quantile(delay, 0.75, na.rm = TRUE),
    fQ09_delay = quantile(delay, 0.9, na.rm = TRUE),
    fQ095_delay = quantile(delay, 0.95, na.rm = TRUE),
    fmax_delay = max(delay),
    fvar_delay = if (.N > 1) var(delay) else NA_real_,
    fsd_delay = if (.N > 1) sd(delay) else NA_real_
  ), by = group_num]
  
  # Coefficiant de variation
  flow_att0[, fCV_delay := fsd_delay / fmean_delay]
  flow_attn[, fCV_delay := fsd_delay / fmean_delay]
  
  
  # Add common metadata (fast and elegant)
  meta_cols <- c("attacked", "simulation_time", "extra_router", "extra_detour", "latency",
                 "bandwidth", "data_rate", "parasite_rate", "packet_size", "proto",
                 "src_ip", "dst_ip", "src_port", "dst_port")
  for (col in meta_cols) {
    #print(unique(dtf_att0[[col]]))
    #print(unique(dtf_attn[[col]]))
    flow_att0[, (col) := na.omit(unique(dtf_att0[[col]]))]
    flow_attn[, (col) := na.omit(unique(dtf_attn[[col]]))]
  }
  
  flow_att0[, delay := t_end - t_start]
  flow_attn[, delay := t_end - t_start]
  
  flow_att0[, lambda_hat := flow_size/delay]
  flow_attn[, lambda_hat := flow_size/delay]
  
  #' #remove_col <- -which(names(keep_att0) %in% c("t_start","attacked", "t_end", "delay"))
  #' flow_att0 <- keep_att0[, .(packet_length = mean(packet_length), t_start = min(t_start)), by = group_num]
  #' flow_attn <- keep_attn[, .(packet_length = mean(packet_length), t_start = min(t_start)), by = group_num]
  #' # flow_att0 <- data.frame(packet_length = (aggregate(keep_att0[ , c("packet_length")], list(keep_att0$group_num), FUN=mean))[,-1])
  #' # flow_attn <- data.frame(packet_length = (aggregate(keep_attn[ , c("packet_length")], list(keep_attn$group_num), FUN=mean))[,-1])
  #' # flow_att0$t_start <- min_t_start_att0
  #' # flow_attn$t_start <- min_t_start_attn
  #' #print(paste0("n_packets:", n_packets, ", size_group:", length(size_group), ", flow_:", nrow(flow_attn), ", ", nrow(flow_att0)))
  #' tmp_lengthgroup_0 = (aggregate(keep_att0$delay, list(keep_att0$group_num), FUN = length))[,-1]
  #' tmp_lengthgroup_n = (aggregate(keep_attn$delay, list(keep_attn$group_num), FUN = length))[,-1]
  #' 
  #' flow_att0$flow_size <- tmp_lengthgroup_0 #count(keep_att0[ , c("group_num")])[,-1]
  #' flow_attn$flow_size <- tmp_lengthgroup_n #count(keep_attn[ , c("group_num")])[,-1]
  #' 
  #' flow_att0$attacked <- unique(dtf_att0$attacked)
  #' flow_attn$attacked <- unique(dtf_attn$attacked)
  #' flow_att0$simulation_time <- unique(dtf_att0$simulation_time)
  #' flow_attn$simulation_time <- unique(dtf_attn$simulation_time)
  #' flow_att0$extra_router <- unique(dtf_att0$extra_router)
  #' flow_attn$extra_router <- unique(dtf_attn$extra_router)
  #' flow_att0$extra_detour <- unique(dtf_att0$extra_detour)
  #' flow_attn$extra_detour <- unique(dtf_attn$extra_detour)
  #' flow_att0$latency <- unique(dtf_att0$latency)
  #' flow_attn$latency <- unique(dtf_attn$latency)
  #' flow_att0$bandwidth <- unique(dtf_att0$bandwidth)
  #' flow_attn$bandwidth <- unique(dtf_attn$bandwidth)
  #' flow_att0$data_rate <- unique(dtf_att0$data_rate)
  #' flow_attn$data_rate <- unique(dtf_attn$data_rate)
  #' flow_att0$parasite_rate <- unique(dtf_att0$parasite_rate)
  #' flow_attn$parasite_rate <- unique(dtf_attn$parasite_rate)
  #' flow_att0$packet_size <- unique(dtf_att0$packet_size)
  #' flow_attn$packet_size <- unique(dtf_attn$packet_size)
  #' flow_att0$proto <- unique(dtf_att0$proto)
  #' flow_attn$proto <- unique(dtf_attn$proto)
  #' flow_att0$src_ip <- unique(dtf_att0$src_ip)
  #' flow_attn$src_ip <- unique(dtf_attn$src_ip)
  #' flow_att0$dst_ip <- unique(dtf_att0$dst_ip)
  #' flow_attn$dst_ip <- unique(dtf_attn$dst_ip)
  #' flow_att0$src_port <- unique(dtf_att0$src_port)
  #' flow_attn$src_port <- unique(dtf_attn$src_port)
  #' flow_att0$dst_port <- unique(dtf_att0$dst_port)
  #' flow_attn$dst_port <- unique(dtf_attn$dst_port)
  #' 
  #' summary0 <-   data.frame((aggregate(keep_att0[ , c("delay")], list(keep_att0$group_num), FUN=summary))[,-1])
  #' summaryn <-   data.frame((aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=summary))[,-1])
  #' #' The smallest value.
  #' flow_att0$fmin_delay <- summary0$Min.
  #' flow_attn$fmin_delay <- summaryn$Min.
  #' flow_att0$fFstQ_delay <- summary0$X1st.Qu.
  #' flow_attn$fFstQ_delay <- summaryn$X1st.Qu.
  #' #' A robust estimate of the center of the data.
  #' flow_att0$fmedian_delay <- summary0$Median
  #' flow_attn$fmedian_delay <- summaryn$Median
  #' #' The average of a dataset, defined as the sum of all observations divided by the number of observations.
  #' flow_att0$fmean_delay <- summary0$Mean
  #' flow_attn$fmean_delay <- summaryn$Mean
  #' flow_att0$fTrdQ_delay <- summary0$X3rd.Qu.
  #' flow_attn$fTrdQ_delay <- summaryn$X3rd.Qu.
  #' #' The largest value.
  #' flow_att0$fmax_delay <- summary0$Max.
  #' flow_attn$fmax_delay <- summaryn$Max.
  #' 
  #' flow_att0$delay <- max_t_end_att0 - min_t_start_att0
  #' flow_attn$delay <- max_t_end_attn - min_t_start_attn
  #' if (1 != group)
  #' {
  #'   #' A measure of the spread of your data.
  #'   flow_att0$fvar_delay <-  (aggregate(keep_att0[ , c("delay")], list(keep_att0$group_num), FUN=var))[,-1]
  #'   flow_attn$fvar_delay <- (aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=var))[,-1]
  #'   
  #'   #' The amount any observation can be expected to differ from the mean.
  #'   flow_att0$fsd_delay <-  (aggregate(keep_att0[ , c("delay")], list(keep_att0$group_num), FUN=sd))[,-1]
  #'   flow_attn$fsd_delay <- (aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=sd))[,-1]
  #' }
  
  ### TROP DE BUG BIZARRE
  # Function to compute SD of successive differences in a vector safely
  sd_diff_safe <- function(x) {
    if (length(x) < 2) {return(NA_real_)}
    return (sd(diff(x))) 
  }
  
  mean_diff_safe <- function(x) {
    if (length(x) < 2) {return(NA_real_)}
    return (mean(abs(diff(x)), na.rm=TRUE)) 
  }
  sqrt_mean_diff_safe <- function(x) {
    if (length(x) < 2) {return(NA_real_)}
    return (sqrt(mean((diff(x))^2, na.rm=TRUE)))  
  }
  mean_pmax_diff_plus_safe <- function(x) {
    if (length(x) < 2) {return(NA_real_)}
    return (mean(pmax(diff(x),0), na.rm=TRUE))  
  }
  mean_pmax_diff_moins_safe <- function(x) {
    if (length(x) < 2) {return(NA_real_)}
    return (mean(pmax(-diff(x),0), na.rm=TRUE))  
  }
  
  # Add fsd_diff_delay by group_num for keep_att0
  fsd_diff_0 <- keep_att0[, .(fsd_diff_delay = sd_diff_safe(delay)), by = group_num]
  flow_att0 <- merge(flow_att0, fsd_diff_0, by = "group_num")
  
  # Add fsd_diff_delay by group_num for keep_attn
  fsd_diff_n <- keep_attn[, .(fsd_diff_delay = sd_diff_safe(delay)), by = group_num]
  flow_attn <- merge(flow_attn, fsd_diff_n, by = "group_num")
  
  rm(fsd_diff_0, fsd_diff_n)
  
  fmean_diff_0 <- keep_att0[, .(fMASD_delay = mean_diff_safe(delay)), by = group_num]
  flow_att0 <- merge(flow_att0, fmean_diff_0, by = "group_num")
  
  fmean_diff_n <- keep_attn[, .(fMASD_delay = mean_diff_safe(delay)), by = group_num]
  flow_attn <- merge(flow_attn, fmean_diff_n, by = "group_num")
  
  rm(fmean_diff_0, fmean_diff_n)
  
  fsqrt_mean_diff_0 <- keep_att0[, .(fRMSJ_delay = sqrt_mean_diff_safe(delay)), by = group_num]
  flow_att0 <- merge(flow_att0, fsqrt_mean_diff_0, by = "group_num")
  
  fsqrt_mean_diff_n <- keep_attn[, .(fRMSJ_delay = sqrt_mean_diff_safe(delay)), by = group_num]
  flow_attn <- merge(flow_attn, fsqrt_mean_diff_n, by = "group_num")
  
  rm(fsqrt_mean_diff_0, fsqrt_mean_diff_n)
  
  
  fIPDV_pos_0 <- keep_att0[, .(fIPDV_pos_delay = mean_pmax_diff_plus_safe(delay)), by = group_num]
  flow_att0 <- merge(flow_att0, fIPDV_pos_0, by = "group_num")
  
  fIPDV_pos_n <- keep_attn[, .(fIPDV_pos_delay = mean_pmax_diff_plus_safe(delay)), by = group_num]
  flow_attn <- merge(flow_attn, fIPDV_pos_n, by = "group_num")
  
  fIPDV_neg_0 <- keep_att0[, .(fIPDV_neg_delay = mean_pmax_diff_moins_safe(delay)), by = group_num]
  flow_att0 <- merge(flow_att0, fIPDV_neg_0, by = "group_num")
  
  fIPDV_neg_n <- keep_attn[, .(fIPDV_neg_delay = mean_pmax_diff_moins_safe(delay)), by = group_num]
  flow_attn <- merge(flow_attn, fIPDV_neg_n, by = "group_num")
  
  rm(fIPDV_pos_0, fIPDV_neg_0,fIPDV_pos_n, fIPDV_neg_n)
  
  
  # tmp_agg = (aggregate(keep_att0[ , c("delay")], list(keep_att0$group_num), FUN=diff)[,-1])
  # tmp_0 = (lapply(tmp_agg, FUN = c))
  # flow_att0$fsd_diff_delay <- unlist(lapply(tmp_0, FUN = sd))
  # 
  # #flow_att0$fsd_diff_delay <- unlist(lapply(tmp_0, FUN = sd))
  # # tmp_n = lapply((aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=diff))[,-1],FUN = c)
  # # flow_attn$fsd_diff_delay <- unlist(lapply(tmp_n, FUN = sd))
  # tmp_agg = (aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=diff))[,-1]
  # tmp_n = (lapply(tmp_agg, FUN = c))
  # flow_attn$fsd_diff_delay <- unlist(lapply(tmp_n, FUN = sd))
  # 
  # rm(tmp_agg, tmp_0, tmp_n)
  ##################################
  
  
  #' The error associated with a point estimate (e.g. the mean) of the sample.
  sd_error <- function(x) {
    if (length(x) <= 1) return(NA_real_)
    sd(x) / sqrt(length(x))
  }
  # min_max function for range
  #' The maximum minus the minimum.
  min_max <- function(x) {
    if (length(x) == 0) return(NA_real_)
    max(x) - min(x)
  }
  if (1 != group)
  {
    fsderror_0 <- keep_att0[, .(fsderror_delay = sd_error(delay)), by = group_num]
    fsderror_n <- keep_attn[, .(fsderror_delay = sd_error(delay)), by = group_num]
    flow_att0 <- merge(flow_att0, fsderror_0, by = "group_num")
    flow_attn <- merge(flow_attn, fsderror_n, by = "group_num")
    rm (fsderror_0, fsderror_n)
    # flow_att0$fsderror_delay <-  (aggregate(keep_att0[ , c("delay")], list(keep_att0$group_num), FUN=sd_error))[,-1]
    # flow_attn$fsderror_delay <- (aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=sd_error))[,-1]
  }
  #' Median Absolute Deviation from the Median
  #' Average distance between each datapoint and the median
  #' A measure of spread in the data
  fmad_0 <- keep_att0[, .(fmad_delay = mad(delay, na.rm = TRUE)), by = group_num]
  fmad_n <- keep_attn[, .(fmad_delay = mad(delay, na.rm = TRUE)), by = group_num]
  flow_att0 <- merge(flow_att0, fmad_0, by = "group_num")
  flow_attn <- merge(flow_attn, fmad_n, by = "group_num")
  # flow_att0$fmad_delay <-  (aggregate(keep_att0[ , c("delay")], list(keep_att0$group_num), FUN=mad))[,-1]
  # flow_attn$fmad_delay <- (aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=mad))[,-1]
  rm(fmad_0, fmad_n)
  
  fminmax_0 <- keep_att0[, .(fminmax_delay = min_max(delay)), by = group_num]
  fminmax_n <- keep_attn[, .(fminmax_delay = min_max(delay)), by = group_num]
  flow_att0 <- merge(flow_att0, fminmax_0, by = "group_num")
  flow_attn <- merge(flow_attn, fminmax_n, by = "group_num")
  rm (fminmax_0, fminmax_n)
  # flow_att0$fminmax_delay <-  (aggregate(keep_att0[ , c("delay")], list(keep_att0$group_num), FUN=min_max))[,-1]
  # flow_attn$fminmax_delay <- (aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=min_max))[,-1]
  
  #' Interquartile Range
  #' The middle 50% of the data, contained between the 0.25 and 0.75 quantiles
  fIQR_0 <- keep_att0[, .(fIQR_delay = IQR(delay, na.rm = TRUE)), by = group_num]
  fIQR_n <- keep_attn[, .(fIQR_delay = IQR(delay, na.rm = TRUE)), by = group_num]
  flow_att0 <- merge(flow_att0, fIQR_0, by = "group_num")
  flow_attn <- merge(flow_attn, fIQR_n, by = "group_num")
  rm (fIQR_0, fIQR_n)
  flow_att0[, fQ095_Q005 := fQ095_delay - fQ005_delay]
  flow_attn[, fQ095_Q005 := fQ095_delay - fQ005_delay]
  # flow_att0$fIQR_delay <-  (aggregate(keep_att0[ , c("delay")], list(keep_att0$group_num), FUN=IQR, na.rm = TRUE))[,-1]
  # flow_attn$fIQR_delay <- (aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=IQR, na.rm = TRUE))[,-1]
  
  
  # Autocorrelation
  auto_corr_0 <- keep_att0[, .(
    facf_last = {
      x <- delay
      n <- length(x)
      if (n > 1 & !all(is.na(x))) {
        acf(x, lag.max = n - 1, plot = FALSE, na.action = na.exclude)$acf[n]  # last lag
      } else {
        NA_real_
      }
    }
  ), by = group_num]
  
  auto_corr_n <- keep_attn[, .(
    facf_last = {
      x <- delay
      n <- length(x)
      if (n > 1 & !all(is.na(x))) {
        acf(x, lag.max = n - 1, plot = FALSE, na.action = na.exclude)$acf[n]
      } else {
        NA_real_
      }
    }
  ), by = group_num]
  
  # Merge into your flows
  flow_att0 <- merge(flow_att0, auto_corr_0, by = "group_num")
  flow_attn <- merge(flow_attn, auto_corr_n, by = "group_num")
  
  auto_corr_0 <- keep_att0[, .(
     facf = {
      x <- delay
      if (length(x) > 1 & !all(is.na(x))) {
        tmp_acf = acf(x, lag.max = 10, plot = FALSE, na.action = na.exclude)
        tmp_acf$acf
      } else {
        NA_real_
      }
    }
  ), by = group_num]
  auto_corr_0[, name_lag := paste0("facf_lag", 0:(.N-1)), by = group_num]
  result_0 <- dcast(auto_corr_0, group_num ~ name_lag, value.var = "facf")
  result_0 <- as.data.table(result_0)  # Add this line
  result_0[, fACF_sum := rowSums(abs(.SD)), .SDcols = -c("group_num", "facf_lag0")]
  auto_corr_n <- keep_attn[, .(
    facf = {
      x <- delay
      if (length(x) > 1 & !all(is.na(x))) {
        tmp_acf = acf(x, lag.max = 10, plot = FALSE, na.action = na.exclude)
        tmp_acf$acf
      } else {
        NA_real_
      }
    }
  ), by = group_num]
  auto_corr_n[, name_lag := paste0("facf_lag", 0:(.N-1)), by = group_num]
  result_n <- dcast(auto_corr_n, group_num ~ name_lag, value.var = "facf")
  result_n <- as.data.table(result_n)
  result_n[, fACF_sum := rowSums(abs(.SD)), .SDcols = -c("group_num", "facf_lag0")]
  flow_att0 <- merge(flow_att0, result_0, by = "group_num")
  flow_attn <- merge(flow_attn, result_n, by = "group_num")
  
  rm (auto_corr_0, auto_corr_n, result_0, result_n)
  
  slope_index <- function(x){ n<-length(x); if (n<2) return(NA_real_); as.numeric(coef(stats::lm(x ~ seq_len(n)))[2]) }
  slope_0<- keep_att0[, .(fslope_t = slope_index(delay)), by = group_num]
  slope_n<- keep_attn[, .(fslope_t = slope_index(delay)), by = group_num]
  flow_att0 <- merge(flow_att0, slope_0, by = "group_num")
  flow_attn <- merge(flow_attn, slope_n, by = "group_num")
  rm (slope_0, slope_n)
  
  # CUSUM (simple, upward)
  cusum_max <- function(x){
    x<-na.omit(x); n<-length(x); if (n<3) return(NA_real_)
    m<-mean(x); s<-stats::sd(x); if (!is.finite(s) || s==0) return(0)
    k<-0.5; S<-0; Smax<-0
    for (i in seq_len(n)) { S <- max(0, S + (x[i]-m)/s - k); Smax <- max(Smax, S) }
    Smax
  }
  cusum_0<- keep_att0[, .(fCUSUM_max = cusum_max(delay)), by = group_num]
  cusum_n<- keep_attn[, .(fCUSUM_max = cusum_max(delay)), by = group_num]
  flow_att0 <- merge(flow_att0, cusum_0, by = "group_num")
  flow_attn <- merge(flow_attn, cusum_n, by = "group_num")
  rm(cusum_0, cusum_n)
  
  early_late_diff <- function(x){ n<-length(x); if (n<4) return(NA_real_); h<-floor(n/2); median(x[1:h]) - median(x[(h+1):n]) }
  early_diff_0<- keep_att0[, .(fearly_diff = early_late_diff(delay)), by = group_num]
  early_diff_n<- keep_attn[, .(fearly_diff = early_late_diff(delay)), by = group_num]
  flow_att0 <- merge(flow_att0, early_diff_0, by = "group_num")
  flow_attn <- merge(flow_attn, early_diff_n, by = "group_num")
  rm (early_diff_0, early_diff_n)
  
  
  # Régression d ~ L
  reg_delay_size <- function(delay, size){
    if (is.null(size) || all(!is.finite(size)) || stats::var(size,na.rm=TRUE)==0)
      return(c(alpha_hat=NA_real_, beta_hat=NA_real_, r2=NA_real_, sigma_eps=NA_real_))
    df <- data.frame(d=delay, L=size)
    fit <- stats::lm(d ~ L, data=df); s <- summary(fit)
    c(alpha_hat=unname(coef(fit)[1]), beta_hat=unname(coef(fit)[2]),
         r2=unname(s$r.squared), sigma_eps=unname(sigma(fit)))
  }
  reg_0<- keep_att0[, .(freg = reg_delay_size(delay, packet_length)), by = group_num]
  reg_0[, name_var := c("alpha_hat","beta_hat","r2", "sigma_eps"), by = group_num]
  result_reg0 <- dcast(reg_0, group_num ~ name_var, value.var = "freg")
  flow_att0 <- merge(flow_att0, result_reg0, by = "group_num")
  

  reg_n<- keep_attn[, .(freg = reg_delay_size(delay, packet_length)), by = group_num]
  reg_n[, name_var := c("alpha_hat","beta_hat","r2", "sigma_eps"), by = group_num]
  result_regn <- dcast(reg_n, group_num ~ name_var, value.var = "freg")
  flow_attn <- merge(flow_attn, result_regn, by = "group_num")
  rm (reg_0, reg_n, result_reg0, result_regn)
  
  # Hill
  hill_index <- function(x){
    x<-sort(na.omit(x))
    n<-length(x)
    if (n<10) return(NA_real_)
    k <- max(5L, floor(sqrt(n)))
    xk<-x[(n-k+1):n]
    xk0<-x[n-k]
    mean(log(xk) - log(xk0))
  }
  hill_0<- keep_att0[, .(fhill = hill_index(delay)), by = group_num]
  hill_n<- keep_attn[, .(fhill = hill_index(delay)), by = group_num]
  if (!all(is.na(hill_0$fhill)))
  {
    flow_att0 <- merge(flow_att0, hill_0, by = "group_num")
    flow_attn <- merge(flow_attn, hill_n, by = "group_num")
  }
  rm (hill_0, hill_n)
  
  
  # Spectral sur diff(d)
  spec_feats <- function(x){
    if (length(x)<8) return(list(fSpec_peak_freq=NA_real_, fSpec_entropy=NA_real_))
    y <- stats::na.omit(diff(as.numeric(x)))
    N <- length(y)
    Y <- stats::fft(y)
    P <- Mod(Y[2:floor(N/2)])^2   # ignore DC, demi-spectre
    if (length(P)<2) return(list(fSpec_peak_freq=NA_real_, fSpec_entropy=NA_real_))
    f <- seq(1, length(P))/N
    pk <- f[which.max(P)]
    pnorm <- P/sum(P)
    ent <- -sum(pnorm*log(pnorm + 1e-12))
    c(fSpec_peak_freq=as.numeric(pk), fSpec_entropy=as.numeric(ent))
  }
  keep_att0$group_num = as.integer(keep_att0$group_num)
  spec_0<- keep_att0[, .(fspec = spec_feats(delay)), by = group_num]
  spec_0[, name_var := c("fSpec_peak_freq","fSpec_entropy"), by = group_num]
  result_spec0 <- dcast(spec_0, group_num ~ name_var, value.var = "fspec")
  flow_att0 <- merge(flow_att0, result_spec0, by = "group_num")
  
  spec_n<- keep_attn[, .(fspec = spec_feats(delay)), by = group_num]
  spec_n[, name_var := c("fSpec_peak_freq","fSpec_entropy"), by = group_num]
  result_specn <- dcast(spec_n, group_num ~ name_var, value.var = "fspec")
  flow_attn <- merge(flow_attn, result_specn, by = "group_num")
  
  rm (spec_0, spec_n, result_spec0, result_specn)
  flow_att0[, rho_tilde := lambda_hat * beta_hat * packet_length]
  flow_attn[, rho_tilde := lambda_hat * beta_hat * packet_length]
  
  if (1 != group)
  {
    #' Skew
    #' The relative position of the mean and median. At 0, mean = median, and the data is normally distributed.
    fskew_0 <- keep_att0[, .(fskew_delay = skewness(delay, na.rm = TRUE)), by = group_num]
    fskew_n <- keep_attn[, .(fskew_delay = skewness(delay, na.rm = TRUE)), by = group_num]
    # flow_att0$fskew_delay <-  (aggregate(keep_att0[ , c("delay")], list(keep_att0$group_num), FUN=skewness, na.rm = TRUE))[,-1]
    # flow_attn$fskew_delay <- (aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=skewness, na.rm = TRUE))[,-1]
    
    #' Kurtosis
    #' The size of the tails in a distribution. In R, values much different from 0 are non-normally distributed.
    fkurtosis_0 <- keep_att0[, .(fkurtosis_delay = kurtosis(delay, na.rm = TRUE)), by = group_num]
    fkurtosis_n <- keep_attn[, .(fkurtosis_delay = kurtosis(delay, na.rm = TRUE)), by = group_num]
    # flow_att0$fkurtosis_delay <-  (aggregate(keep_att0[ , c("delay")], list(keep_att0$group_num), FUN=kurtosis, na.rm = TRUE))[,-1]
    # flow_attn$fkurtosis_delay <- (aggregate(keep_attn[ , c("delay")], list(keep_attn$group_num), FUN=kurtosis, na.rm = TRUE))[,-1]
    
    flow_att0 <- merge(flow_att0, fskew_0, by = "group_num")
    flow_attn <- merge(flow_attn, fskew_n, by = "group_num")
    
    flow_att0 <- merge(flow_att0, fkurtosis_0, by = "group_num")
    flow_attn <- merge(flow_attn, fkurtosis_n, by = "group_num")
    
    rm (fskew_0, fskew_n, fkurtosis_0, fkurtosis_n)
  }
  if ("queue_size" %in% names(keep_att0))
  {
    
    # Sum of queue sizes per group
    sum_queuesize_0 <- keep_att0[, .(fsum_queuesize = sum(queue_size, na.rm = TRUE)), by = group_num]
    sum_queuesize_n <- keep_attn[, .(fsum_queuesize = sum(queue_size, na.rm = TRUE)), by = group_num]
    # flow_att0$fsum_queuesize <-  (aggregate(keep_att0[ , c("queue_size")], list(keep_att0$group_num), FUN=sum, na.rm = TRUE))[,-1]
    # flow_attn$fsum_queuesize <-  (aggregate(keep_attn[ , c("queue_size")], list(keep_attn$group_num), FUN=sum, na.rm = TRUE))[,-1]
    
    # Summary statistics for queue_size per group
    summary_queuesize_0 <- keep_att0[, .(
      fmin_queuesize = min(queue_size, na.rm = TRUE),
      fFstQ_queuesize = quantile(queue_size, 0.25, na.rm = TRUE),
      fmedian_queuesize = median(queue_size, na.rm = TRUE),
      fmean_queuesize = mean(queue_size, na.rm = TRUE),
      fTrdQ_queuesize = quantile(queue_size, 0.75, na.rm = TRUE),
      fmax_queuesize = max(queue_size, na.rm = TRUE)
    ), by = group_num]
    
    summary_queuesize_n <- keep_attn[, .(
      fmin_queuesize = min(queue_size, na.rm = TRUE),
      fFstQ_queuesize = quantile(queue_size, 0.25, na.rm = TRUE),
      fmedian_queuesize = median(queue_size, na.rm = TRUE),
      fmean_queuesize = mean(queue_size, na.rm = TRUE),
      fTrdQ_queuesize = quantile(queue_size, 0.75, na.rm = TRUE),
      fmax_queuesize = max(queue_size, na.rm = TRUE)
    ), by = group_num]
    
    # Merge results back into flow_att tables
    flow_att0 <- merge(flow_att0, sum_queuesize_0, by = "group_num")
    flow_attn <- merge(flow_attn, sum_queuesize_n, by = "group_num")
    
    flow_att0 <- merge(flow_att0, summary_queuesize_0, by = "group_num")
    flow_attn <- merge(flow_attn, summary_queuesize_n, by = "group_num")
    
    
    
    
    
    
    #' summary0 <-   data.frame((aggregate(keep_att0[ , c("queue_size")], list(keep_att0$group_num), FUN=summary))[,-1])
    #' summaryn <-   data.frame((aggregate(keep_attn[ , c("queue_size")], list(keep_attn$group_num), FUN=summary))[,-1])
    #' #' The smallest value.
    #' flow_att0$fmin_queuesize <- summary0$Min.
    #' flow_attn$fmin_queuesize <- summaryn$Min.
    #' flow_att0$fFstQ_queuesize <- summary0$X1st.Qu.
    #' flow_attn$fFstQ_queuesize <- summaryn$X1st.Qu.
    #' #' A robust estimate of the center of the data.
    #' flow_att0$fmedian_queuesize <- summary0$Median
    #' flow_attn$fmedian_queuesize <- summaryn$Median
    #' #' The average of a dataset, defined as the sum of all observations divided by the number of observations.
    #' flow_att0$fmean_queuesize <- summary0$Mean
    #' flow_attn$fmean_queuesize <- summaryn$Mean
    #' flow_att0$fTrdQ_queuesize <- summary0$X3rd.Qu.
    #' flow_attn$fTrdQ_queuesize <- summaryn$X3rd.Qu.
    #' #' The largest value.
    #' flow_att0$fmax_queuesize <- summary0$Max.
    #' flow_attn$fmax_queuesize <- summaryn$Max.
  }
  
  
  # 5) Duty cycle : proportion du temps où la file est occupée
  # On mesure l’union des intervalles [arrival[i], departure[i]]
  # 6) Run max : plus longue période continue où file non vide
  # On mesure la durée max parmi les intervalles fusionnés
  # Convert to data.table for intervals_0
  dt_0 <- data.table(start = keep_att0$t_start, end = keep_att0$t_end, group_num = keep_att0$group_num)
  setorder(dt_0, group_num, start)
  
  # Merge overlapping intervals by group
  dt_0[, interval_id := cumsum(c(TRUE, start[-1] > cummax(end)[-.N])), by = group_num]
  merged_0 <- dt_0[, .(start = min(start), end = max(end)), by = .(group_num, interval_id)]
  merged_0[, duration := end - start]
  
  # Calculate metrics by group
  results_0 <- merged_0[, .(
    total_busy = sum(duration),
    duration = max(start) - min(start),
    run_max = max(duration)
  ), by = group_num]
  
  results_0[, duty := ifelse(duration > 0, total_busy / duration, 0)]
  flow_att0 <- merge(flow_att0, results_0[, .(group_num, duty, run_max)], by = "group_num")
  
  # Repeat for intervals_n
  dt_n <- data.table(start = keep_attn$t_start, end = keep_attn$t_end, group_num = keep_attn$group_num)
  setorder(dt_n, group_num, start)
  
  dt_n[, interval_id := cumsum(c(TRUE, start[-1] > cummax(end)[-.N])), by = group_num]
  merged_n <- dt_n[, .(start = min(start), end = max(end)), by = .(group_num, interval_id)]
  merged_n[, duration := end - start]
  results_n <- merged_n[, .(
    total_busy = sum(duration),
    duration = max(start) - min(start),
    run_max = max(duration)
  ), by = group_num]
  
  results_n[, duty := ifelse(duration > 0, total_busy / duration, 0)]
  flow_attn <- merge(flow_attn, results_n[, .(group_num, duty, run_max)], by = "group_num")
  
  
  rm(dt_0, dt_n, merged_0, merged_n, results_0, results_n)
  
  
  #' while (proportion_of_attack > sum(size_group[flows_attn]) && !no_more_flow)
  #' {
  #'   reste = (proportion_of_attack- sum(size_group[flows_attn]))
  #'   small_flow <- which(size_group <= reste)
  #'   
  #'   #' remove flows that where already taken
  #'   small_flow <- small_flow[! small_flow %in% flows_attn]
  #'   
  #'   #' no flow was taken and no flow can fit in the reste
  #'   #' so we take the smallest flow as the detoured one
  #'   #' to have at least one detoured flow
  #'   if (sum(flows_attn) == 0 && length(small_flow) == 0)
  #'   {
  #'     #' if there is no flow picked for being detoured and 
  #'     #' that there is no small group 
  #'     #' to fit in the proportion of allowed detoured packets,
  #'     #' we take the smaller size group to have at least one detoured flow
  #'     id_min <- which(min(abs(size_group-reste)) == abs(size_group-reste))
  #'     flows_attn = c(flows_attn, id_min)
  #'   }else if (length(small_flow) != 0){
  #'     #' we take a random flow among the ones 
  #'     #' that can fit in the detoured packets set. 
  #'     shuffle_flow <- sample (small_flow)
  #'     cs <- cumsum(size_group[shuffle_flow])
  #'     idx <- which(cs >= reste)[1]
  #'     
  #'     #' yes: all the random flow fit in the detoured packets set
  #'     #' no: a part of the random flow fit in the detoured packets set
  #'     id <- ifelse (is.na(idx), shuffle_flow, shuffle_flow[1:idx])
  #'     
  #'     flows_attn = c(flows_attn, id)
  #'   }else{
  #'     #' there is still some place for more detoured packet 
  #'     #' but there is no flow that can fill the remaining space 
  #'     #' so we stop with flows we already selected
  #'     no_more_flow = TRUE
  #'     print("no more flow")
  #'   }
  #' }
  
  
  keep_attn = flow_attn
  keep_att0 = flow_att0
  real_prop = keep_attn[, .N] / keep_att0[, .N]
  print(paste0("keepn:", keep_attn[, .N], ", keep0:", keep_att0[, .N], ", real_prop:", real_prop))
  print("end flow computation")
  X_end = rbind(keep_att0, keep_attn)
  setorder(X_end, t_start)
  # X_end = X_end[ order(X_end$t_start ), ]
  
  # if (nrow(X_end) != length(size_group)) ## for debug
  # {
  #   print(paste0("l_size_group:", length(size_group), " , l_X_end:", dim(X_end)))
  #   print(tail(X_end))
  #   print(tail(size_group))
  # }
  #X_end$flow_size = size_group ### problem should be here!!!
  
  X_end = compute_stat(X_end, by)#"flow")
  # Step 1: Compute proportion of NA per column
  na_proportions <- X_end[, lapply(.SD, function(col) mean(is.na(col)))]
  # Step 2: Identify columns to keep (less than or equal to 50% NA)
  cols_to_keep <- names(na_proportions)[na_proportions <= 0.5]
  # Step 4: Remove rows with any remaining NA
  X_end_no_na <- X_end[, ..cols_to_keep] #na.omit(X_end[, ..cols_to_keep])
  print("end mid_to_flow")
  return (X_end_no_na)
  
}

#' Function that plots the percentage of error for a machine learning model 
#' in function of the path length.
#' @param data the dataset containing the pourcentage of error for each model
#' @param ... optional argument to specify:
#' - the model ("cah", "cart", "dbscan", "isof", "kmeans", "lof", "ocsvm", "reglog", "rf", "svm", "xgboost")
#' - the approach ("analysis", "supervised", "unsupervised")
#' - the number of intermediate nodes in the detour (from 1 to 64)
#' - the way the detoured packets are put in the dataset ("end", "rand", "flow")
plot_error <-function(data, ...)
{
  # Récupérer les arguments supplémentaires
  dots <- list(...)
  ndots <- length(dots)
  
  # Initialiser les filtres avec les valeurs uniques du dataset
  myatt = unique(data$repartition_att)
  mydetour = seq(min(data$nb_detour), max(data$nb_detour))
  mymodel = unique(data$model)
  myapproach = unique(data$approach)
  
  specified_params <- list()  # Stocke les paramètres spécifiés explicitement
  
  
  # Itérer sur chaque argument supplémentaire pour ajuster les filtres
  for (i in 1:ndots) {
    arg <- dots[[i]]
    if (is.character(arg)) {
      if (arg %in% unique(data$model)) {
        mymodel <- arg
        specified_params$model <- TRUE
      } else if (arg %in% unique(data$repartition_att)) {
        myatt <- arg
        specified_params$repartition_att <- TRUE
      } else if (arg %in% unique(data$approach)) {
        myapproach <- arg
        specified_params$approach <- TRUE
      } else {
        warning(paste("L'argument", arg, "n'appartient à aucun des champs 'model', 'repartition_att' ou 'approach'."))
      }
    } else if (is.numeric(arg)) {
      mydetour <- arg
      specified_params$nb_detour <- TRUE
    } else {
      warning(paste("Type d'argument non supporté:", class(arg)))
    }
  }
  
  
  # Dynamiser les mappings pour `color` et `shape`
  color_param <- if (isTRUE(specified_params$model) && !isTRUE(specified_params$repartition_att)) {
    "repartition_att"
  } else {
    "model"
  }
  
  shape_param <- if (isTRUE(specified_params$approach) && !isTRUE(specified_params$repartition_att)) {
    "repartition_att"
  } else {
    "approach"
  }
  
  # Vérifications avant filtrage
  if (!any(data$model %in% mymodel)) {
    stop("Le modèle spécifié n'existe pas dans les données.")
  }
  if (!any(data$nb_detour %in% mydetour)) {
    stop("La valeur de 'nb_detour' spécifiée n'existe pas dans les données.")
  }
  if (!any(data$repartition_att %in% myatt)) {
    stop("L'attribut de répartition spécifié n'existe pas dans les données.")
  }
  if (!any(data$approach %in% myapproach)) {
    stop("L'approche spécifiée n'existe pas dans les données.")
  }
  
  # Create a combined factor variable for 'model' and 'approach' for the grouped legend
  if (is.null(specified_params$model) && is.null(specified_params$approach)) {
    data$grouped_model_approach <- interaction(data$model, data$approach, sep = " - ")
    color_param <- "grouped_model_approach"  # Use this combined column for color grouping
  } else {
    data$grouped_model_approach <- data$model  # Keep model grouping if specified
  }
  
  # Filtrer les données en fonction des critères définis
  filtered_data <- subset(data, 
                          model %in% mymodel & 
                            nb_detour %in% mydetour & 
                            repartition_att %in% myatt & 
                            approach %in% myapproach)
  
  # Vérifier si les données filtrées ne sont pas vides
  if(nrow(filtered_data) == 0) {
    stop("Aucune donnée ne correspond aux critères de filtrage spécifiés.")
  }
  
  # Create the title dynamically based on selected parameters
  title_text <- "Error Percentage as a function of path length\n"
  
  if (isTRUE(specified_params$model)) {
    title_text <- paste(title_text, "Model: ", mymodel, "\n", sep = "")
  }
  
  if (isTRUE(specified_params$approach)) {
    title_text <- paste(title_text, "Approach: ", myapproach, "\n", sep = "")
  }
  
  if (isTRUE(specified_params$nb_detour)) {
    title_text <- paste(title_text, "Number of detours: ", toString(mydetour), "\n", sep = "")
  }
  
  if (isTRUE(specified_params$repartition_att)) {
    title_text <- paste(title_text, "Repartition Att: ", toString(myatt), "\n", sep = "")
  }
  
  # Créer le graphique avec ggplot2
  ggplot(filtered_data, aes(x = path_length, y = error, 
                            size = nb_detour, color = .data[[color_param]], shape = .data[[shape_param]])) +
    geom_point(alpha = 0.7) +  # Ajout d'une transparence pour mieux visualiser les points
    scale_size(range = c(0, 2))+ #c(1, 5)) +  # Ajustement de la plage de tailles
    ggtitle(title_text) +
    labs(x = "Path Length (Number of links)",
         y = "Percentage of Errors",
         size = "Number of\nintermediate\nnodes in the\ndetour",
         color = color_param,
         shape = shape_param) +
    guides(color = guide_legend(title = color_param)) +#, 
    #override.aes = list(size = 3))) +  # Customize legend appearance
    theme_minimal() #+  # Utilisation d'un thème minimaliste
  #theme(plot.title = element_text(hjust = 0.5))  # Centrer le titre
}

print_confusionmatrix <- function(data, index)
{
  prop = data[index,]$prop_att
  conf_matrix <- matrix(c(data[index,]$TP,  data[index,]$FN,data[index,]$FP, data[index,]$TN)
                        , nrow = 2, byrow = TRUE, 
                        , dimnames = list(c("Actual Positive", "Actual Negative"),
                                          c("Predicted Positive", "Predicted Negative"))
  )
  
  # Convertir la table en data.frame pour ggplot
  conf_matrix_df <- as.data.frame(as.table(conf_matrix))
  model <- unique(data$model)
  # Visualiser avec ggplot2
  g <- ggplot(data = conf_matrix_df, aes(x = Var1, y = Var2, fill = Freq)) +
    geom_tile() +
    geom_text(aes(label = Freq), color = "white", size = 5) +
    scale_fill_gradient(low = "blue", high = "red") +
    labs(title = paste0(model, "/", prop, " : Confusion Matrix for sample ", index), x = "Actual", y = "Predicted") +
    theme_minimal()
  return (g)
}
