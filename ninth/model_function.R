make_seed_from_string <- function(s) {
  # 32-bit hex (8 chars) produit par xxhash32
  hash_hex <- digest(s, algo = "xxhash32", serialize = FALSE)
  # split into two 4-hex parts to avoid strtoi overflow
  hi <- strtoi(substr(hash_hex, 1, 4), base = 16L)
  lo <- strtoi(substr(hash_hex, 5, 8), base = 16L)
  
  # fallback si strtoi renvoie NA (très improbable avec xxhash32, mais prudent)
  if (is.na(hi)) hi <- 0L
  if (is.na(lo)) lo <- 0L
  
  # compute numeric then reduce to valid R integer range
  seed_num <- (as.numeric(hi) * 65536 + as.numeric(lo)) %% .Machine$integer.max
  seed_int <- as.integer(seed_num)
  
  # Ensure single valid seed in [1, .Machine$integer.max - 1]
  if (length(seed_int) != 1 || is.na(seed_int) || seed_int < 1L) {
    seed_int <- 1L
  }
  return(seed_int)
}

partition <- function(dtf, unsupervised = FALSE,  p = 0.7, do_pca = FALSE, is_timeserie = FALSE, current_param)
{
  if (isTRUE(current_param$cross_seed)) {
    cat ("[DEBUG] in partition in crossseed: ", current_param$test_run_id,"\n")
    dtf[, index := .I]
    test_set  <- dtf[run_id == current_param$test_run_id]
    train_set <- dtf[run_id != current_param$test_run_id]
    cat ("[DEBUG] test_set:", nrow(test_set), ", train_set:", nrow(train_set), "\n")
    if (isTRUE(unsupervised) || isTRUE(current_param$do_0)) {
      train_set <- train_set[attacked == 0]   # autoencodeurs : benins uniquement
    }
    cat ("[DEBUG] fin before null in partition in crossseed\n")
    cat ("[DEBUG] run_id in test_set:", unique(test_set$run_id), "\n")
    cat ("[DEBUG] run_id in train_set:", unique(train_set$run_id), "\n")
    train_set[, run_id := NULL]; test_set[, run_id := NULL]
    cat ("[DEBUG] fin partition in crossseed\n")
    return(list(train_set, test_set))
  }
  # #current_seed <- (as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M")))
  # hash_hex <- digest(current_param$my_seed, algo = "xxhash32", serialize = FALSE)
  # current_seed <- strtoi(substr(hash_hex, 1, 8), base = 16)
  # current_seed <- as.integer(current_seed %% .Machine$integer.max)
  current_seed <- make_seed_from_string(current_param$my_seed)
  #current_param$my_seed <- current_seed
  print(paste("current_seed:",current_seed))
  set.seed(current_seed)
  group = current_param$group
  prop_in_att = current_param$prop
  print(paste0("prop_in_att:", prop_in_att))
  dtf[, index := .I]
  testattheend = current_param$testattheend
  do_0 <- current_param$do_0
  print(paste0("do_0:", do_0))
  if (do_0)
  {
    dtf_healthy <- dtf[attacked==0]
    if (testattheend)
    {
      to_train_tmp <- seq(1, p*nrow(dtf_healthy))
    }else{
      to_train_tmp <- createDataPartition(dtf_healthy$delay, times = 1, p = p, list = FALSE)
    }
    #to_test_tmp = dtf_healthy[-to_train_tmp ]
    to_train = dtf_healthy[to_train_tmp, .(index)]
    to_test = dtf_healthy[-to_train_tmp, .(index)]
    train_set <- dtf[to_train$index]
    test_set <- dtf[to_test$index]
    
  } else if (! unsupervised)
  {
    if (!testattheend)
    {
      #' supervised model (can put attacked packets in the training set)
      to_train <- createDataPartition(dtf$attacked, p = p, list = FALSE, groups = 2)
      train_set <- dtf[to_train]
      test_set = dtf[-to_train ]
    }else{
      print("partition: testat the end for supervised models")
      to_train <- seq(1, p*nrow(dtf))
      train_set <- dtf[to_train]
      test_set <- dtf[-to_train]
    }
    
  }else{
    #' unsupervised model (can NOT put attacked packets in the training set)
    
    # pick train set only among healthy packets
    # dtf[, index := .I]  # .I is data.table's row index #dtf$index = 1:nrow(dtf)
    dtf_healthy <- dtf[attacked==0]
    #print(nrow(dtf_healthy))
    dtf_attacked <- dtf[attacked == 1]
    #print(nrow(dtf_attacked))
    
    
    
    #non_p = min ((p * nrow(dtf)) / nrow(dtf_nonsuper), 1)
    #to_train_tmp <- createDataPartition(dtf_nonsuper$delay, p = non_p, list = FALSE)
    if (testattheend){
      to_train_tmp <- seq(1, p*nrow(dtf_healthy))
    
    }else if (!do_pca & !is_timeserie){
      to_train_tmp <- createDataPartition(dtf_healthy$delay, times = 1, p = p, list = FALSE)
    }else if (!do_pca & is_timeserie){
      horizon = 0#group #floor(group * ((1-p)/p))
      timeslice = createTimeSlices(dtf_healthy$t_start, group, 
                                   horizon = horizon, fixedWindow = TRUE, 
                                   skip = group-1)
      ntrain = length(timeslice$train) 
      to_train_partition <- createDataPartition(1:ntrain, times = 1, p = p, list = FALSE )
      to_train_tmp2 <- unlist (timeslice$train[to_train_partition])
      to_train_tmp <- c(to_train_tmp2)
      
    }else if (do_pca & !is_timeserie){
      to_train_tmp <- createDataPartition(dtf_healthy[[1]], times = 1, p = p, list = FALSE, groups = 2)
    }else # if (do_pca & is_timeserie)
    {
      horizon = 0#group #floor(group * ((1-p)/p))
      timeslice = createTimeSlices(dtf_healthy[[1]], group, 
                                   horizon = horizon, fixedWindow = TRUE, 
                                   skip = group-1)
      ntrain = length(timeslice$train) 
      to_train_partition <- createDataPartition(1:ntrain, times = 1, p = p, list = FALSE )
      to_train_tmp2 <- unlist (timeslice$train[to_train_partition])
      to_train_tmp <- c(to_train_tmp2)
    }
    
    #
    to_train = dtf_healthy[to_train_tmp, .(index)]
    to_test = dtf_healthy[-to_train_tmp, .(index)]
    # the remaining healthy packets belong to the test set:
    #test_set = dtf[-to_train, ]
    
    test_healthy <- dtf[J(to_test), on = "index"]
    print(head(test_healthy$index))
    print(head(to_train))
    # print(setdiff(to_train, test_healthy$index))
    print(dim(test_healthy))
    print(dim(to_train))
    # test_healthy = dtf[to_test, ]
    
    # print(paste0("train:", dtf[J(to_train), on = "index"][,.N]/(test_healthy[,.N]+dtf[J(to_train), on = "index"][,.N]), 
    #              ", test:", test_healthy[,.N]/(test_healthy[,.N]+dtf[J(to_train), on = "index"][,.N]), 
    #              ", attacked in testset:", nrow(test_healthy[test_healthy$attacked == 1])/(test_healthy[,.N])))
    # take 30% of the detoured packets to match the case of supervised models
    print("after first partition")
    
    #prop = nrow(dtf_attacked)/nrow(dtf) # pourcentage of detoured packets in the whole dataset
    # packet to take among to detoured one
    #p_test_att = (1-p) * prop 
    to_test_part <- 1
    #to_test_part <- createDataPartition(dtf_attacked$delay, p = p_test_att, list = FALSE)
    if (1 < dtf_attacked[,.N])
    {
      print(colnames(dtf_attacked))
      if (testattheend){
        mini_test <- which(dtf_attacked[,t_start]>= min(test_healthy[,t_start]))[1]
        mini_test <- max(mini_test, 1, na.rm = T)
        to_test_part <- seq(mini_test, mini_test +(1-p)*nrow(dtf_attacked))
      }else if (!do_pca & !is_timeserie){
        if (1==length(unique(dtf_attacked$delay)))
        {
          to_test_part <- sample(dtf_attacked[,.N], size = floor((1-p) * dtf_attacked[,.N]))
        }else{
          to_test_part <- createDataPartition(dtf_attacked$delay, p = 1-p, list = FALSE)
        }
      } else if (!do_pca & is_timeserie){
        horizon = 0#group #floor(group * ((1-p)/p))
        timeslice = createTimeSlices(dtf_attacked$t_start, group, 
                                     horizon = horizon, fixedWindow = TRUE, 
                                     skip = group-1)
        ntest = length(timeslice$train) 
        #' need to get prop_in_att detour packet instead of 1-p 
        #' because in the casee of not timeseries model,
        #' we take 1-p of prop_in_att that where already taken in 
        #' mix_to_flow function that is not called here for timeseries models
        #' 
        print("i'm here in is_timeserie, test set construction")
        to_test_partition <- createDataPartition(1:ntest, times = 1, p = prop_in_att * (1-p), list = FALSE ) #(1-p)*(1-p)
        to_test_tmp2 <- unlist (timeslice$train[to_test_partition])
        to_test_part <- c(to_test_tmp2)
      }else if  (do_pca & !is_timeserie){
        to_test_part <- createDataPartition(dtf_attacked[[1]], p = 1-p, list = FALSE, groups = 2)
      } else {
        horizon = 0#group #floor(group * ((1-p)/p))
        timeslice = createTimeSlices(dtf_attacked[[1]], group, 
                                     horizon = horizon, fixedWindow = TRUE, 
                                     skip = group-1)
        ntest = length(timeslice$train) 
        to_test_partition <- createDataPartition(1:ntest, times = 1, p = prop_in_att* (1-p), list = FALSE ) #(1-p)*(1-p)
        to_test_tmp2 <- unlist (timeslice$train[to_test_partition])
        to_test_part <- c(to_test_tmp2)
      }
      
    }
    to_test_att <- dtf_attacked[to_test_part, .(index)]
    
    #packets to take among the healthy one
    # p_test_health = (1-p) * (1-prop)
    # dtf_health = dtf_nonsuper[-to_train, ]
    # to_test_helthy <- createDataPartition(dtf_nonsuper$delay, p = p_test_att, list = FALSE)
    
    test_set <- rbind (test_healthy, dtf[J(to_test_att), on = "index"])#dtf[to_test_att,])
    train_set <- dtf[J(to_train), on = "index"]
  }
  # print(length(to_train) /nrow(dtf)  ) ### debug
  #train_set <- dtf[to_train, ]
  print(paste0("train:", train_set[,.N]/(test_set[,.N]+train_set[,.N]), 
               ", test:", test_set[,.N]/(test_set[,.N]+train_set[,.N]), 
               ", attacked in testset:", nrow(test_set[test_set$attacked == 1])/(test_set[,.N])))
  print(head(test_set$index))
  print(head(train_set$index))
  # print(setdiff(train_set$index, test_set$index))
  print(dim(test_set))
  print(dim(train_set))
  return (list(train_set, test_set))
}

is_charge_before <- function(current_param, suffix = ".RData")
{
  # Chemin vers votre fichier sauvegardé
  char = c("s", "l", "b", "Ra", "Re", "Ma", "Me", "P", "h", "a", "p", "g", "m
           pca", "end", "seed","evol", "trainpara", "traindetour", "trainpath")
  par = paste0(char, current_param)
  par = par[1:length(char)]
  
  path_parts <- strsplit(current_param$my_seed, "/")[[1]]
  last_part <- tail(path_parts, n=1)
  
  par = paste0("T", current_param$simulation_time, "_L", current_param$latency,
              "_B", current_param$bandwidth,"_Ra", current_param$data_rate,
              "_Ma", current_param$meanexp, "_Me", current_param$parasite_meanexp,
              "_p", current_param$prop, "_g", current_param$group, "_", current_param$model,
              "_", current_param$proto, "_",last_part,
              "_tpar", current_param$trainonparasite, "_td", current_param$trainondetour,
              "_tpath", current_param$trainonpath, 
              "_testrunid", basename(current_param$test_run_id)
              )
  filename = paste0("scratch/ninth/model/", paste(par, collapse = "_"))
  fichier_sauvegarde <- paste0(filename, suffix)
  # Vérifier si le fichier existe
  print(paste("file exist ?", file.exists(fichier_sauvegarde)))
  if (file.exists(fichier_sauvegarde) & current_param$do_evolution) {
    print(fichier_sauvegarde)
    if (suffix == ".RData")
    {
      load(fichier_sauvegarde, envir = .GlobalEnv)
      print("Fichier RDATA chargé avec succès.")
    }
    
    print(paste("filename:", filename))
    return (list(T, filename)) #TRUE
  } else {
    print(paste("filename:", filename))
    return(list(FALSE, filename))
  }
}

commun_info <- function(test_set, prediction, filename)
{
  print(paste0("pred:" , length(prediction), "test:", dim(test_set)))
  test_set$prediction = prediction
  print("afeter alocation pred")
  #test_set$prediction_label = factor(test_set$prediction, levels = c(0,1), labels = c("healthy", "attacked"))
  err <- as.numeric(sum(prediction != test_set$attacked))/(length(test_set$attacked))
  all_1 <- factor (rep (1, length(test_set$attacked)), levels = levels(test_set$attacked))
  all_err <- as.numeric(sum(all_1 != test_set$attacked))/(length(test_set$attacked))
  all_0 <- factor (rep (0, length(test_set$attacked)), levels = levels(test_set$attacked))
  no_err <- as.numeric(sum(all_0 != test_set$attacked))/(length(test_set$attacked))
  
  # conf_matrix <- table(test_set$attacked, prediction)
  # conf_matrix_label <- table(test_set$label, test_set$prediction_label)
  
  # Chemin vers votre fichier sauvegardé
  fichier_sauvegarde <- paste0(filename, "_CM.RData")
  # Vérifier si le fichier existe
  if (file.exists(fichier_sauvegarde)) {
    load(fichier_sauvegarde)
    CM <- get("CM")
    #CM_label <- get("CM_label")
    #print("Fichier chargé avec succès.")
  } else {
    # CM <- confusionMatrix(conf_matrix, positive = "1")
    # CM_label <- confusionMatrix(conf_matrix_label, positive = "attacked")
    CM <- confusionMatrix(test_set$prediction, test_set$attacked, positive = "1")
    #CM_label <- confusionMatrix(test_set$label, test_set$prediction_label, positive = "attacked")
    #save(CM, file = fichier_sauvegarde)
  }
  
  print(CM$table)
  score =  data.frame(error = err, all_err = all_err, no_err = no_err,
                      Recall = (CM$byClass)["Recall"], 
                      Precision = (CM$byClass)["Precision"],
                      F1_score = (CM$byClass)["F1"],
                      TP = CM[["table"]]['1','1'], # 1 predit en 1
                      FN = CM[["table"]]['0','1'], # 1 considéré comme des 0
                      FP = CM[["table"]]['1','0'], # 0 considéré commes des 1
                      TN = CM[["table"]]['0','0']  # 0 predit correctement en 0
                      #FPR =  FP / (FP + TN)
  )
  score$FPR <-  if ((score$FP + score$TN) > 0) score$FP / (score$FP + score$TN) else NA_real_
  # if ((FP + TN) > 0){
  #   score[,FPR :=  FP / (FP + TN) ]
  # }else {
  #   score[,FPR := NA_real_]
  # }
  #score[,FPR := if ((FP + TN) > 0) FP / (FP + TN) else NA_real_]
  return(list(score, test_set))
}

#' Normalisation (Min-Max scaling)
# normalize_me <- function(x) {
#   if (max(x, na.rm =  TRUE) == min(x, na.rm =  TRUE)){
#     return (1)
#   }
#   return ((x - min(x, na.rm =  TRUE)) / (max(x, na.rm =  TRUE) - min(x, na.rm =  TRUE)))
# }
# normalize_me <- function(x) {
#   rng <- range(x, na.rm = TRUE)
#   if (rng[1] == rng[2]) {
#     return(rep(1, length(x)))  # Return a vector of 1s, not a scalar
#   }
#   return((x - rng[1]) / (rng[2] - rng[1]))
# }
normalize_me <- function(x, min_val = NULL, max_val = NULL) {
  if (is.null(min_val) || is.null(max_val)) {
    rng <- range(x, na.rm = TRUE)
    min_val <- rng[1]
    max_val <- rng[2]
  }  
  if (min_val == max_val) {
    return(rep(1, length(x)))  # Tous les éléments sont identiques
  }
  return((x - min_val) / (max_val - min_val))
}



# Supervised models ####
## Classification ####
do_reg_log<- function (train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  
  alpha_base  = train_set[attacked == 0, median(alpha_hat, na.rm=TRUE)]
  jitter_base = train_set[attacked == 0, median(fMASD_delay, na.rm=TRUE)]
  cv_base     = train_set[attacked == 0, median(fCV_delay, na.rm=TRUE)]
  beta_base   = train_set[attacked == 0, median(beta_hat, na.rm=TRUE)]
  
  train_set[, d_alpha := alpha_hat - alpha_base]
  train_set[, d_masd  := fMASD_delay     - jitter_base]
  train_set[, d_cv    := fCV_delay - cv_base]
  train_set[, d_beta  := beta_hat  - beta_base]
  test_set[, d_alpha := alpha_hat - alpha_base]
  test_set[, d_masd  := fMASD_delay     - jitter_base]
  test_set[, d_cv    := fCV_delay - cv_base]
  test_set[, d_beta  := beta_hat  - beta_base]
  reglog_features <- c(
    # robustes niveau/dispersion
    "fmedian_delay", "fmad_delay", "fIQR_delay", "fCV_delay", "fQ095_delay", "fQ095_Q005", "fmeanTRIM10_delay",
    # jitter                   
    "fMASD_delay","fRMSJ_delay", "fsd_diff_delay", "fIPDV_neg_delay", "fIPDV_pos_delay",
    # dépendance & changements                   
    "facf_lag0","facf_lag1","facf_lag2","facf_lag3","facf_lag4",
    "facf_lag5","facf_lag6","facf_lag7","facf_lag8","facf_lag9","facf_lag10",
    "fACF_sum", "fslope_t", "fCUSUM_max", "fearly_diff", 
    # régression d~L
    "alpha_hat","beta_hat", "r2", "sigma_eps",
    #files
    "rho_tilde", "lambda_hat", 
    #queues
    "fkurtosis_delay", "fskew_delay", "fhill",
    #meta
    "delay", "flow_size",
    "d_alpha","d_masd","d_cv","d_beta"
    #,"fmean_mean", "fmedian_median"
    )
  
  if (!use_temporal_covariates) {
    reglog_features <- c(reglog_features, "t_start", "t_end")
  }
  if (!is.null(reduced_feature_set)) {
    .n_before <- length(reglog_features)
    reglog_features <- intersect(reglog_features, reduced_feature_set)
    cat(sprintf("[FEATSET] reglog : %d -> %d variables (jeu reduit de %d)\n",
                .n_before, length(reglog_features), length(reduced_feature_set)))
    cat("[FEATSET] reglog retenues :", paste(reglog_features, collapse = ", "), "\n")
    if (length(reglog_features) == 0L)
      stop("[ERROR] reglog : le jeu reduit ne recouvre aucune variable du modele.")
  }
  
  #keep <- setdiff(names(train_set), remove_col_super)
  keep = colnames(train_set)[colnames(train_set) %in% reglog_features]
  skew_cols <- intersect(c("fCUSUM_max","fhill","rho_tilde","lambda_hat",
                           "fQ095_delay","fQ095_Q005","fPOT_rate_u"), names(train_set))
  for (nm in skew_cols) train_set[[nm]] <- log1p(pmax(train_set[[nm]], 0))
  skew_cols <- intersect(c("fCUSUM_max","fhill","rho_tilde","lambda_hat",
                           "fQ095_delay","fQ095_Q005","fPOT_rate_u"), names(test_set))
  for (nm in skew_cols) test_set[[nm]] <- log1p(pmax(test_set[[nm]], 0))
  
  
  c(is_charged, filename) %<-% is_charge_before(current_param)
  if (FALSE == is_charged)
  {
    counts <- table(train_set$attacked)
    print(counts)
    weight_for_0 = 1 / (2 * (counts["0"]/ sum(counts)))
    weight_for_1 = 1 / (2 * (counts["1"]/ sum(counts)))
    
    # weight_for_0 = 1 / counts["0"]
    # weight_for_1 = 1 / counts["1"]
    #weight_for_0 <- log(1 + train_set[, .N]/counts["0"])
    #weight_for_1 <- log(1 + train_set[, .N]/counts["1"])
    obs_weights <- ifelse(train_set$attacked == "0", weight_for_0, weight_for_1)
    summary(obs_weights)
    # mod_reg_log <- glm(attacked ~ ., data = train_set[, c("attacked", ..keep), with = FALSE], 
    #                    weights = obs_weights,
    #                    family = binomial(link = "logit"), 
    #                    control = glm.control(maxit = 1000, epsilon = 1e-8),
    #                    na.action = na.exclude)
    X_train <- as.matrix(
      lapply(as.data.frame(train_set[, ..keep]), function(col) {
        col[is.na(col)] <- median(col, na.rm = TRUE); col
      }) |> as.data.frame()
    )
    
    set.seed(1997)
    cv_lasso    <- cv.glmnet(X_train, as.numeric(as.character(train_set$attacked)),
                             family  = "binomial", alpha = 1,
                             weights = obs_weights, nfolds = 5)
    mod_reg_log <- glmnet(X_train, as.numeric(as.character(train_set$attacked)),
                          family  = "binomial", alpha = 1,
                          lambda  = cv_lasso$lambda.1se,
                          weights = obs_weights)
    
    if (current_param$do_evolution)
    {
      print(paste("before saving", paste0(filename, ".RData")))
      print(getwd())
      # save(mod_reg_log, file = paste0(filename, ".RData"))
      lasso_keep <- keep   # sauvegarder les features utilisées
      save(mod_reg_log, cv_lasso, lasso_keep,
           file = paste0(filename, ".RData"))
    }
    
    
  }else{
    load(paste0(filename, ".RData"))   # charge mod_reg_log, cv_lasso, lasso_keep
    # mod_reg_log <- get("mod_reg_log")
    print("mod_reg_log (LASSO) chargé")
    
    # ← AJOUT DIAGNOSTIC
    print(paste0("class(mod_reg_log): ", paste(class(mod_reg_log), collapse=", ")))
    print(paste0("is.null(mod_reg_log): ", is.null(mod_reg_log)))
    print(paste0("objets chargés: ", paste(ls(), collapse=", ")))
    
    # # Aligner keep avec les variables attendues par le modèle chargé
    # expected_vars <- attr(mod_reg_log$terms, "term.labels")
    # missing_vars <- setdiff(expected_vars, colnames(test_set))
    # if (length(missing_vars) > 0) {
    #   print(paste("Ajout de colonnes manquantes dans test_set:", paste(missing_vars, collapse=", ")))
    #   for (mv in missing_vars) {
    #     train_set[, (mv) := 0]
    #     test_set[, (mv) := 0]
    #   }
    #   keep <- union(keep, missing_vars)
    # }
    # Aligner keep avec les features utilisées à l'entraînement
    print(paste0( "lasso_keep", lasso_keep))
    missing_in_train <- setdiff(lasso_keep, colnames(train_set))
    print(paste0( "missing_in_train", missing_in_train))
    missing_in_test  <- setdiff(lasso_keep, colnames(test_set))
    print(paste0( "missing_in_test", missing_in_test))
    
    if (length(missing_in_train) > 0 || length(missing_in_test) > 0) {
      print(paste("Ajout colonnes manquantes:",
                  paste(union(missing_in_train, missing_in_test), collapse = ", ")))
      for (mv in missing_in_train) train_set[, (mv) := 0]
      for (mv in missing_in_test)  test_set[,  (mv) := 0]
    }
    keep <- lasso_keep
    print(paste0("keep: ", keep))
  }

  
  
  
  # coef_summary <- summary(mod_reg_log)$coefficients
  # common_vars <- rownames(coef_summary)
  # coef_df <- data.frame(
  #   variable = common_vars,
  #   estimate = coef_summary[common_vars, "Estimate"],
  #   std_error = coef_summary[common_vars, "Std. Error"],
  #   p_value = coef_summary[common_vars, "Pr(>|z|)"]
  #   #,ci_lower = conf_int[common_vars, 1],
  #   #ci_upper = conf_int[common_vars, 2]
  # )
  print(paste0("coef(mod_reg_log): ", coef(mod_reg_log)))
  # Remplacer la ligne 457 par ces 4 prints
  tmp_coef <- coef(mod_reg_log)
  print(is.null(tmp_coef))           # TRUE → coef retourne NULL
  print(class(tmp_coef))             # la vraie classe
  print(dim(tmp_coef))               # dimensions
  print(tmp_coef) 
  
  print(length(mod_reg_log$lambda))   # nombre de lambdas stockés
  print(mod_reg_log$beta)             # la matrice des coefficients brute
  print(mod_reg_log)
  
  #coef_mat <- as.matrix(coef(mod_reg_log))
  # Remplace : coef_mat <- as.matrix(coef(mod_reg_log))
  beta_mat  <- as(mod_reg_log$beta, "matrix")          # S4 coercion Matrix, toujours fiable
  coef_mat  <- rbind("(Intercept)" = as.numeric(mod_reg_log$a0), beta_mat)
  
  coef_df  <- data.frame(
    variable = rownames(coef_mat),
    estimate = coef_mat[, 1]
  )
  coef_df  <- coef_df[
    coef_df$variable != "(Intercept)" & coef_df$estimate != 0, ]
  coef_df  <- head(
    coef_df[order(abs(coef_df$estimate), decreasing = TRUE), ], 2)
  
  n_selected <- sum(coef_mat[-1, 1] != 0)  # nb features retenues hors intercept
  
  
  
  # pred_reg_log <- predict(mod_reg_log, newdata = test_set[,  ..keep], type = "response", na.action = na.pass)
  X_test <- as.matrix(
    lapply(as.data.frame(test_set[, ..keep]), function(col) {
      col[is.na(col)] <- median(col, na.rm = TRUE); col
    }) |> as.data.frame()
  )
  pred_reg_log <- as.vector(predict(mod_reg_log, newx = X_test,
                                    type = "response"))
  # Convertir les prédictions en facteur avec les mêmes niveaux que la variable cible 
  pred_class <- factor(ifelse(pred_reg_log > 0.5, 1, 0), levels = levels(test_set$attacked))
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_class, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  
  top_n <- 2
  coef_df <- coef_df[order(abs(coef_df$estimate), decreasing = TRUE), ]
  coef_df <- head(coef_df, top_n)
  
  
  dtf_model_info <- data.table(simulation_time = current_param$simulation_time, 
                               latency = current_param$latency, 
                               bandwidth = current_param$bandwidth, 
                               data_rate = current_param$data_rate,
                               parasite_rate = current_param$parasite_rate,
                               meanexp = current_param$meanexp,
                               parasite_meanexp = current_param$parasite_meanexp,
                               nb_hops = current_param$nb_hops,
                               nb_att = current_param$nb_att,
                               prop_att = current_param$prop,
                               group = current_param$group,
                               model = current_param$model,
                               protocol = current_param$proto,
                               do_evolution = current_param$do_evolution,
                               trainonparasite = current_param$trainonparasite,
                               trainondetour = current_param$trainondetour,
                               trainonpath = current_param$trainonpath,
                               my_seed = current_param$my_seed,
                               # first_variable = coef_df$variable[1],
                               # second_variable = coef_df$variable[2],
                               first_variable   = if (nrow(coef_df) >= 1) coef_df$variable[1] else NA,
                               second_variable  = if (nrow(coef_df) >= 2) coef_df$variable[2] else NA,
                               F1_score = score$F1_score,
                               Recall = score$Recall,
                               Precision = score$Precision,
                               # critere1 = mod_reg_log$deviance,
                               # critere2 = mod_reg_log$aic,
                               # critere3 =  1 - (mod_reg_log$deviance/mod_reg_log$null.deviance),
                               # critere4 = BrierScore(mod_reg_log),
                               critere1         = mod_reg_log$dev.ratio,        # R² déviance (0-1)
                               critere2         = n_selected,                   # nb features sélectionnées
                               critere3         = cv_lasso$lambda.1se,           # lambda retenu
                               critere4         = min(cv_lasso$cvm),             # erreur CV minimale
                               date = as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M:%OS6"))
  )
  file_name <- paste0("scratch/ninth/model/_model_info.csv")
  write.table(dtf_model_info, file_name, sep = ",", append = TRUE, row.names = F)
  
  
  rm(mod_reg_log)
  
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "supervised"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, 
  #                         nb_detour = nb_att, model = current_param$model, 
  #                         approach = "supervised"), score)
  return (list(tmp, test_set))
}

do_cart <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  print("in cart")
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  keep <- setdiff(names(train_set), remove_col_super)
  c(is_charged, filename) %<-% is_charge_before(current_param)
  if (FALSE == is_charged)
  {
    mod_tree <- rpart(attacked ~ ., data = train_set[, c("attacked", ..keep), with = FALSE])
    #filename = paste0("model/", "modcart_h",nb_hops, "_a", nb_att, "_t", type)
    # save(mod_tree, file = paste0(filename, ".RData"))
  }else{
    mod_tree <- get("mod_tree")
  }
  pred_tree <- predict(mod_tree, newdata = test_set[,..keep], type = "class", na.action = na.pass)
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_tree, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "supervised"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att,
  #                         model = current_param$model, 
  #                         approach = "supervised"), score)
  rm(mod_tree)
  return (list(tmp, test_set))
}

do_randomforest <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  keep <- setdiff(names(train_set), remove_col_super)
  c(is_charged, filename) %<-% is_charge_before(current_param)
  if (FALSE == is_charged)
  {
    print("test1")
    mod_rf <- randomForest(attacked ~ ., data = train_set[,c("attacked", ..keep), with = FALSE], 
                           na.action = na.exclude, proximity = FALSE)
    print("test2")
    #filename = paste0("model/", "modrf_h",nb_hops, "_a", nb_att, "_t", type)
    # save(mod_rf, file = paste0(filename, ".RData"))
  }else{
    mod_rf <- get("mod_rf")
  }
  pred_rf <- predict(mod_rf, newdata = test_set[,c("attacked", ..keep), with = FALSE], na.action = na.exclude)
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_rf, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "supervised"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "supervised"), score)
  rm(mod_rf)
  return (list(tmp, test_set))
}

do_svm <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  #keep = c("packet_length", "t_start", "delay")
  
  svm_features <- c("fmean_delay", "fmedian_delay", 
                    "fsd_delay", "fmad_delay", "fIQR_delay", "fmeanTRIM10_delay",
                    "fCV_delay", "fQ005_delay", "fQ095_delay", 
                    "fmin_delay", "fmax_delay", "fQ095_Q005",
                    "fkurtosis_delay", "fskew_delay",
                    "fsd_diff_delay","fMASD_delay", "fRMSJ_delay", "fIPDV_pos_delay", "fIPDV_neg_delay",
                    "facf_lag0","facf_lag1","facf_lag2","facf_lag3","facf_lag4",
                    "facf_lag5","facf_lag6","facf_lag7","facf_lag8","facf_lag9","facf_lag10",
                    "fACF_sum", "fslope_t","fCUSUM_max", "fearly_diff",
                    "alpha_hat","beta_hat","r2", "sigma_eps",
                    "fhill", "fSpec_peak_freq","fSpec_entropy", 
                    "rho_tilde", "lambda_hat",
                    "flow_size", "delay", "t_start", "t_end"
                    #,"fmean_mean", "fmedian_median"
                    )
  #keep = setdiff(names(train_set), remove_col_super) 
  if (!use_temporal_covariates) {
    svm_features <- setdiff(svm_features, c("t_start", "t_end"))
  }
  
  if (!is.null(reduced_feature_set)) {
    .n_before <- length(svm_features)
    cat("[DEBUG] reduce feature set:", reduced_feature_set, "\n")
    svm_features <- intersect(svm_features, reduced_feature_set)
    cat(sprintf("[FEATSET] svm : %d -> %d variables (jeu reduit de %d)\n",
                .n_before, length(svm_features), length(reduced_feature_set)))
    cat("[FEATSET] svm retenues :", paste(svm_features, collapse = ", "), "\n")
    if (length(svm_features) == 0L)
      stop("[ERROR] svm : le jeu reduit ne recouvre aucune variable du modele.")
  }
  cat("[DEBUG] svm_features:", svm_features, "\n")
  keep = colnames(train_set)[colnames(train_set) %in% svm_features]
  keep <- keep[!sapply(train_set[, ..keep], function(x) length(unique(x)) <= 1)]
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  # Calculer les min et max pour chaque colonne
  mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
  maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
  
  # X <- train_set[, ..keep][, lapply(.SD, normalize_me)] #train_set[, !names(train_set) %in% remove_col] #c("attacked", "index", "packet_length")
  X_train_tmp <- train_set[, ..keep]
  X <- X_train_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  X[,attacked := train_set$attacked]
  
  # #X_test <- test_set[, ..keep][, lapply(.SD, normalize_me)]
  X_test_tmp <- test_set[, ..keep]
  # Appliquer normalize_me à chaque colonne avec ses propres min et max
  X_test <- X_test_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  #X_test[attacked := test_set$attacked]
  
  counts <- table(X$attacked)
  print(counts)
  weight_for_0 = 1 / (2 * (counts["0"]/ sum(counts)))
  weight_for_1 = 1 / (2 * (counts["1"]/ sum(counts)))
  
  # weight_for_0 = 1 / counts["0"]
  # weight_for_1 = 1 / counts["1"]
  #weight_for_0 <- log(1 + train_set[, .N]/counts["0"])
  #weight_for_1 <- log(1 + train_set[, .N]/counts["1"])
  class_weight <- list("0" = weight_for_0,
                       "1" = weight_for_1)
  print (class_weight)
  cat ("[DEBUG] !all(is.na(X[attacked == \"1\"][[\"delay\"]])):", !all(is.na(X[attacked == "1"][["delay"]])), "\n")
  if(!all(is.na(X[attacked == "1"][["delay"]]))){
    if (FALSE == is_charged)
    {
      
      #keep = c( "delay")
      
      # print(colnames(train_set[, c("attacked", ..keep), with = FALSE]))
      # print(str(train_set[, c("attacked", ..keep), with = FALSE]))
      # print(table(train_set$attacked))
      # 
      # print(str(X))
      print(table(X$attacked))
      classifier = svm(formula = attacked ~ ., 
                       data = X,#train_set[, c("attacked", ..keep), with = FALSE],#train_set, 
                       # x = train_set[,..keep],
                       # y = train_set[,"attacked"],
                       cost = 100,
                       type = 'C-classification', # 'C-classification
                       kernel = 'radial', # 'radial' 'linear'
                       scale = F
                       , class.weights = class_weight
                       , na.action = na.exclude
      )
      
      
      ## filename = paste0("model/", "modsvm_h",nb_hops, "_a", nb_att, "_t", type)
      if (current_param$do_evolution)
      {
      save(classifier, file = paste0(filename, ".RData"))
      }
    }else{
      classifier <- get("classifier")
      print("classifier chargé")
      # Aligner les colonnes de X_test avec celles attendues par le classifieur chargé
      expected_cols <- colnames(classifier$SV)
      missing_cols <- setdiff(expected_cols, colnames(X_test))
      if (length(missing_cols) > 0) {
        print(paste("Ajout de colonnes manquantes dans X_test:", paste(missing_cols, collapse=", ")))
        for (mc in missing_cols) X_test[, (mc) := 0]
      }
      # Réordonner les colonnes de X_test pour correspondre au classifieur
      X_test <- X_test[, intersect(expected_cols, colnames(X_test)), with = FALSE]
    }
    str(X_test)
    y_pred = factor(predict(classifier, newdata = X_test, na.action = na.exclude) , #test_set[, ..keep]
                    levels = levels(test_set$attacked))
    X_test[,attacked := test_set$attacked]
    
  }else{
    y_pred = factor(rep(NA,nrow(X_test)), levels = levels(test_set$attacked))
  }
  
  
  
  # str(y_pred)
  # str(X_test)
  # print(table(y_pred))
  # print(table(X_test$attacked))
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, y_pred, filename) #test_set
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "supervised"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att,
  #                         model = current_param$model, 
  #                         approach = "supervised"), score)
  
  
  #cat ("[DEBUG] classifier:", classifier, "\n")
  dtf_model_info <- data.table(simulation_time = current_param$simulation_time, 
                               latency = current_param$latency, 
                               bandwidth = current_param$bandwidth, 
                               data_rate = current_param$data_rate,
                               parasite_rate = current_param$parasite_rate,
                               meanexp = current_param$meanexp,
                               parasite_meanexp = current_param$parasite_meanexp,
                               nb_hops = current_param$nb_hops,
                               nb_att = current_param$nb_att,
                               prop_att = current_param$prop,
                               group = current_param$group,
                               model = current_param$model,
                               protocol = current_param$proto,
                               do_evolution = current_param$do_evolution,
                               trainonparasite = current_param$trainonparasite,
                               trainondetour = current_param$trainondetour,
                               trainonpath = current_param$trainonpath,
                               my_seed = current_param$my_seed,
                               first_variable = NA,
                               second_variable = NA,
                               F1_score = score$F1_score,
                               Recall = score$Recall,
                               Precision = score$Precision,
                               critere1 = NA, #classifier$tot.nSV,
                               critere2 = NA, #(classifier$tot.nSV / nrow(X)) * 100,
                               critere3 =  NA, #classifier$gamma,
                               critere4 = NA,
                               date = as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M:%OS6"))
  )
  file_name <- paste0("scratch/ninth/model/_model_info.csv")
  write.table(dtf_model_info, file_name, sep = ",", append = TRUE, row.names = F)
  
  
  
  rm(classifier)
  return (list(tmp, test_set))
  
}

do_xgboost <- function (train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  alpha_base  = train_set[attacked == 0, median(alpha_hat, na.rm=TRUE)]
  jitter_base = train_set[attacked == 0, median(fMASD_delay, na.rm=TRUE)]
  cv_base     = train_set[attacked == 0, median(fCV_delay, na.rm=TRUE)]
  beta_base   = train_set[attacked == 0, median(beta_hat, na.rm=TRUE)]
  
  train_set[, d_alpha := alpha_hat - alpha_base]
  train_set[, d_masd  := fMASD_delay     - jitter_base]
  train_set[, d_cv    := fCV_delay - cv_base]
  train_set[, d_beta  := beta_hat  - beta_base]
  test_set[, d_alpha := alpha_hat - alpha_base]
  test_set[, d_masd  := fMASD_delay     - jitter_base]
  test_set[, d_cv    := fCV_delay - cv_base]
  test_set[, d_beta  := beta_hat  - beta_base]
  
  q_train <- function(x,p) as.numeric(quantile(x, probs=p, na.rm=TRUE, type=7))
  thr <- list(
    d_alpha_q90  = q_train(train_set$d_alpha, 0.90),
    fMASD_q90    = q_train(train_set$fMASD_delay, 0.90),
    fACF_sum_q90 = q_train(train_set$fACF_sum, 0.90),
    fHill_q75    = q_train(train_set$fhill, 0.75),
    #fPOT_q90     = q_train(train_set$fPOT_rate_u, 0.90),
    fCUSUM_q90   = q_train(train_set$fCUSUM_max, 0.90),
    rho_q90      = q_train(train_set$rho_tilde, 0.90),
    fCV_q90      = q_train(train_set$fCV_delay, 0.90),
    r2_q10       = q_train(train_set$r2, 0.10)
  )
  
  add_flags <- function(dt, thr) {
    dt[, `:=`(
      flag_alpha_hi  = as.integer(d_alpha > thr$d_alpha_q90),
      flag_jitter_hi = as.integer(fMASD_delay > thr$fMASD_q90),
      flag_acf_dep   = as.integer((fACF_sum > thr$fACF_sum_q90)),# | (fLB_p < 0.05)),
      #flag_tail_heavy= as.integer((fhill > thr$fHill_q75)),# | (fPOT_rate_u > thr$fPOT_q90)),
      flag_change    = as.integer(fCUSUM_max > thr$fCUSUM_q90),
      flag_util_hi   = as.integer(rho_tilde > thr$rho_q90),
      flag_queue_dom = as.integer(fCV_delay > thr$fCV_q90),
      flag_low_fit   = as.integer(r2 < thr$r2_q10)
    )]
    return(dt)
  }
  train_set <- add_flags(train_set, thr)
  test_set <- add_flags(test_set, thr)
  
  xgboost_features <- c(
    # robustes niveau/dispersion
    "fmedian_delay", "fmean_delay", "fmad_delay", "fIQR_delay", "fCV_delay", 
    "fQ005_delay","fQ095_delay", "fQ095_Q005", "fmeanTRIM10_delay",
    # jitter                   
    "fMASD_delay","fRMSJ_delay", "fsd_diff_delay", "fIPDV_neg_delay", "fIPDV_pos_delay",
    # dépendance & changements                   
    "facf_lag0","facf_lag1","facf_lag2","facf_lag3","facf_lag4",
    "facf_lag5","facf_lag6","facf_lag7","facf_lag8","facf_lag9","facf_lag10",
    "fslope_t", "fCUSUM_max", "fearly_diff", 
    # régression d~L
    "alpha_hat","beta_hat", "r2", "sigma_eps",
    #files
    "rho_tilde", "lambda_hat", 
    #queues
    "fkurtosis_delay", "fskew_delay", "fhill",
    # spectral
    "fSpec_peak_freq","fSpec_entropy", 
    #meta
    "delay", "flow_size",
    "d_alpha","d_masd","d_cv","d_beta",
    # flags (optionnels)
    "flag_alpha_hi","flag_jitter_hi","flag_acf_dep","flag_tail_heavy","flag_change",
    "flag_util_hi","flag_queue_dom","flag_low_fit"
    #"fmean_mean", "fmedian_median"
    )
  
  
  #keep = c("packet_length", "t_start", "delay")
  #keep = setdiff(names(train_set), remove_col_super) #-which(names(train_set) %in% remove_col_svm ) #, "flow_size"c("attacked")
  keep = colnames(train_set)[colnames(train_set) %in% xgboost_features]
  
  train_x = data.matrix(train_set[,..keep])
  train_y = as.integer(levels(train_set[["attacked"]]))[train_set[["attacked"]]]  #as.integer(levels(train_set$attacked))[train_set$attacked]
  #print(head(train_y))
  test_x = data.matrix(test_set[,..keep])
  test_y = as.integer(levels(test_set[["attacked"]]))[test_set[["attacked"]]]  #as.integer(levels(test_set$attacked))[test_set$attacked]
  
  #define final training and testing sets
  
  xgb_test = xgb.DMatrix(data = test_x, label = test_y)
  if (is_charged != TRUE)
  {
    counts <- table(train_set$attacked)
    weight_for_0 = 1 / (2 * (counts["0"]/ sum(counts)))
    weight_for_1 = 1 / (2 * (counts["1"]/ sum(counts)))
    
    obs_weights <- ifelse(train_set$attacked == "0", weight_for_0, weight_for_1)
    
    xgb_train = xgb.DMatrix(data = train_x, 
                            label = train_y)
    
    final = xgboost(data = xgb_train, weight = obs_weights, max.depth = 1000, nrounds = 50, verbose = 0)
    
    if (current_param$do_evolution)
    {
    ##filename = paste0("model/", "modxgboost_h",nb_hops, "_a", nb_att, "_t", type)
    save(final, file = paste0(filename, ".RData"))
    }
  }else{
    final <- get("final")
    print("final xgboost chargé")
  }
  #use model to make predictions on test data
  pred_y = predict(final, xgb_test, na.action = na.exclude)
  prediction <- factor(as.numeric(pred_y > 0.5), levels = levels(test_set$attacked))
  
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, prediction, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "supervised"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "supervised"), score)
  
  importance <- xgb.importance(model = final)
  dtf_model_info <- data.table(simulation_time = current_param$simulation_time, 
                               latency = current_param$latency, 
                               bandwidth = current_param$bandwidth, 
                               data_rate = current_param$data_rate,
                               parasite_rate = current_param$parasite_rate,
                               meanexp = current_param$meanexp,
                               parasite_meanexp = current_param$parasite_meanexp,
                               nb_hops = current_param$nb_hops,
                               nb_att = current_param$nb_att,
                               prop_att = current_param$prop,
                               group = current_param$group,
                               model = current_param$model,
                               protocol = current_param$proto,
                               do_evolution = current_param$do_evolution,
                               trainonparasite = current_param$trainonparasite,
                               trainondetour = current_param$trainondetour,
                               trainonpath = current_param$trainonpath,
                               my_seed = current_param$my_seed,
                               first_variable = importance$Feature[1],
                               second_variable = importance$Feature[2],
                               F1_score = score$F1_score,
                               Recall = score$Recall,
                               Precision = score$Precision,
                               critere1 = NA,
                               critere2 = NA,
                               critere3 =  NA,
                               critere4 = NA,
                               date = as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M:%OS6"))
  )
  file_name <- paste0("scratch/ninth/model/_model_info.csv")
  write.table(dtf_model_info, file_name, sep = ",", append = TRUE, row.names = F)
  
  rm(final)
  return (list(tmp, test_set))
}

## a verifier
do_lda <- function (train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  if (FALSE == is_charged)
  {
    model_lda <- lda(attacked ~ ., data = train_set, na.action = na.pass)
    #filename = paste0("model/", "modlda_h",nb_hops, "_a", nb_att, "_t", type)
    # save(model_lda, file = paste0(filename, ".RData"))
  }else{
    model_lda <- get("model_lda")
  }
  
  pred_lda <- predict(model_lda, newdata = test_set, na.action = na.pass)
  
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_lda, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "supervised"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "supervised"), score)
  rm(model_lda)
  return (list(tmp, test_set))
}


## a verifier
do_naivebayes <- function (train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  if (FALSE == is_charged)
  {
    model_nbc <- naiveBayes(attacked ~ ., data = train_set, na.action = na.pass)
    #filename = paste0("model/", "modnbc_h",nb_hops, "_a", nb_att, "_t", type)
    # save(model_nbc, file = paste0(filename, ".RData"))
  }else{
    model_nbc <- get("model_nbc")
  }
  
  pred_nbc <- predict(model_nbc, newdata = test_set, na.action = na.pass)
  
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_nbc, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "supervised"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "supervised"), score)
  rm(model_nbc)
  return (list(tmp, test_set))
}


## Regression ####
# Decision tree
# Random forest
# XGBoost

# Unsupervised models ####
## Clustering ####
do_kmeans <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  keep = setdiff(names(train_set), remove_col_svm) #-which(names(train_set) %in% remove_col_svm) #, "flow_size" c("attacked")
  
  #keep = c("t_start", "packet_length", "delay")
  #keep = -which(names(train_set) %in% remove_col_svm) #, "flow_size" c("attacked")
  # keep = c( "packet_length","delay")
  # keep = c( "delay")
  
  no_na <- train_set[complete.cases(train_set[, ..keep]), ..keep] #na.omit(train_set[,..keep])
  numeric_cols <- names(which(sapply(no_na, is.numeric)))
  no_na <- no_na[, ..numeric_cols]
  # yes_na <- !na.omit(train_set[,keep])
  # no_na <- which(train_set[,keep] %in% no_na)
  model_kmeans <- kmeans(no_na, centers = 2)
  
  # # Créer une grille de toutes les combinaisons de points et centres
  # combinations <- expand.grid(point = test_set$delay, centre = (model_kmeans$centers)[,1])
  # # Calculer les distances avec mapply (différence absolue)
  # combinations$distance <- mapply(function(p, c) abs(p - c), combinations$point, combinations$centre)
  # 
  # # Trouver la distance minimale pour chaque point
  # min_distances <- tapply(combinations$distance, combinations$point, min)
  # # Afficher les distances
  # distances = min_distances[as.character(test_set$delay)]
  # anomalies2 <- (distances > quantile(distances, 0.9500, na.rm = T))
  
  
  keep = setdiff(names(train_set), c(remove_col_svm, "prediction")) #-which(names(test_set) %in% c(remove_col_svm, "prediction")) #c("attacked",
  test_no_na <- test_set[complete.cases(test_set)] #na.omit(test_set)
  test_no_na_keep <- test_no_na[,..keep]
  numeric_keep <- names(test_no_na_keep)[sapply(test_no_na_keep, is.numeric)]
  test_no_na_keep <- test_no_na_keep[, ..numeric_keep]
  
  # Calculate the distance of each point from the nearest cluster center
  distances <- apply(test_no_na_keep, 1, function(x) {
    (sqrt(rowSums((t(model_kmeans$centers) - x)^2)))
  })
  distances <- apply(distances, 2, norm, type = "2")
  
  anomalies <- (distances > quantile(distances, 0.9500, na.rm = T))
  
  
  
  
  
  pred_kmeans = factor(ifelse(anomalies, 1, 0), levels = levels(test_set$attacked))
  
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_no_na, pred_kmeans, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, c(names(score)) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "unsupervised"), score)
  rm(model_kmeans)
  return (list(tmp, test_set))
}

do_pcathenkmeans <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  print(paste0("model: ",current_param$model))
  keep <- setdiff(names(train_set), c(remove_col_svm, "latency", "bandwidth", "data_rate", 
                                      "parasite_rate", "proto", "src_ip"))
  # keep = -which(names(train_set) %in% c(remove_col_svm, 
  #                                       "latency", "bandwidth", "data_rate", 
  #                                       "parasite_rate", "proto", "src_ip")) #, "flow_size" c("attacked")
  # Step 1: Compute proportion of NA per column
  na_proportions <- train_set[, lapply(.SD, function(col) mean(is.na(col)))]
  # Step 2: Identify columns to keep (less than or equal to 50% NA)
  cols_to_keep <- names(na_proportions)[na_proportions <= 0.5]
  # Step 3: Intersect with your existing 'keep' variable
  final_keep <- intersect(keep, cols_to_keep)
  # Step 4: Remove rows with any remaining NA
  train_no_na <- na.omit(train_set[, ..final_keep])
  #train_no_na <- na.omit(train_set[, ..keep])
  
  train_pca <- FactoMineR::PCA(as.data.frame(train_no_na), graph = FALSE, ncp=ncol(train_no_na))#, quali.sup = 3)
  model_pcathenkmeans <- kmeans(train_pca$ind$coord , centers = 1)
  
  keep <- setdiff(names(test_set), c(remove_col_svm, "prediction"))
  #keep = -which(names(test_set) %in% c(remove_col_svm, "prediction")) #"attacked"
  # Step 1: Compute proportion of NA per column
  na_proportions <- test_set[, lapply(.SD, function(col) mean(is.na(col)))]
  # Step 2: Identify columns to keep (less than or equal to 50% NA)
  cols_to_keep <- names(na_proportions)[na_proportions <= 0.5]
  final_keep <- intersect(keep, cols_to_keep)
  test_no_na <- na.omit(test_set[, ..cols_to_keep])
  
  new_data = predict(train_pca, newdata = as.data.frame(test_no_na[, ..final_keep]))
  # Calculate the distance of each point from the nearest cluster center
  distances <- apply(new_data$coord, 1, function(x) {
    (sqrt(rowSums((t(model_pcathenkmeans$centers) - x)^2)))
  })
  
  
  distances <- apply(distances, 2, norm, type = "2")
  
  anomalies <- (distances > quantile(distances, 0.95000, na.rm = T))
  pred_pcathenkmeans = factor(ifelse(anomalies, 1, 0), levels = levels(test_set$attacked))
  print(paste0("before prediction:"))
  
  c(score, test_set) %<-% commun_info(test_no_na, pred_pcathenkmeans, "filename")
  print("after prediction")
  
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(path_length = nb_hops,
                    nb_detour = nb_att,
                    model = current_param$model,
                    approach = "unsupervised")
  tmp <- cbind(tmp, score)
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "unsupervised"), score)
  rm(model_pcathenkmeans)
  print("end pca model")
  return (list(tmp, test_set))
}

do_dbscan <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  keep = -which(names(train_set) %in% remove_col_svm) #, "flow_size" c("attacked")
  if (FALSE == is_charged)
  {
    db_model <- dbscan(train_set[,keep], eps =650, minPts = 30)
    # save(db_model, file = paste0(filename, ".RData"))
  }else{
    db_model <- get("db_model")
  }
  
  scores <- predict(db_model, test_set[, keep], train_set[, c("packet_length", "t_start", "delay")], na.action = na.exclude)
  pred_dbscan <- factor(ifelse(scores < 0.5, 1, 0), 
                        levels = levels(test_set$attacked))
  # err= as.numeric(sum(pred_dbscan != test_set$attacked))/(length(test_set$attacked))
  # all_1 <- factor (rep (1, length(test_set$attacked)), levels = levels(test_set$attacked))
  # all_err <- as.numeric(sum(all_1 != test_set$attacked))/(length(test_set$attacked))
  # all_0 <- factor (rep (0, length(test_set$attacked)), levels = levels(test_set$attacked))
  # no_err <- as.numeric(sum(all_0 != test_set$attacked))/(length(test_set$attacked))
  # conf_db <- table(test_set$attacked, pred_dbscan)
  # CM <- confusionMatrix(conf_db)
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_dbscan, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "unsupervised"), score)
  rm(db_model)
  return (list(tmp, test_set))
}

do_cah <- function(dtf, unused, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  #if (FALSE == is_charged)
  keep = -which(names(dtf) %in% remove_col_svm) #, "flow_size" c("attacked")
  cah_data = dtf[,keep]
  
  pca_fm <- FactoMineR::PCA(cah_data, graph = T, ncp = Inf)
  cah_fm <- FactoMineR::HCPC(pca_fm, nb.clust = -1,graph = T, min = 2)
  # save(cah_fm, file = paste0(filename, ".RData"))
  cah_data$cluster = (cah_fm$data.clust$clust)
  
  cah_data$attacked = dtf$attacked
  cnt = count((cah_data[cah_data$attacked == 1,])$cluster)
  id_max= which.max(cnt$freq)
  clust_max = cnt$x[id_max]
  
  pred_cah = factor(ifelse(cah_data$cluster == clust_max , 1, 0), levels = levels(dtf$attacked) )
  # err = as.numeric(sum(pred_cah != dtf$attacked))/length(dtf$attacked)
  # all_1 <- factor (rep (1, length(dtf$attacked)), levels = levels(dtf$attacked))
  # all_err <- as.numeric(sum(all_1 != dtf$attacked))/length(dtf$attacked)
  # all_0 <- factor (rep (0, length(dtf$attacked)), levels = levels(dtf$attacked))
  # no_err <- as.numeric(sum(all_0 != dtf$attacked))/length(dtf$attacked)
  # conf_cah <- table(dtf$attacked, pred_cah)
  # CM <- confusionMatrix(conf_cah)
  print(paste0("model: ",current_param$model))
  c(score, dtf) %<-% commun_info(dtf, pred_cah, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "analysis"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att,
  #                         model = current_param$model, 
  #                         approach = "analysis"), score)
  gc()
  return (list(tmp, dtf))
}

## Anomalies detection ####
do_isolationforest <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  keep = setdiff(names(train_set), remove_col_svm)#-which(names(train_set) %in% remove_col_svm) #, "flow_size" c("attacked")
  c(is_charged, filename) %<-% is_charge_before(current_param)
  if (is_charged != TRUE){
    
    mod_iso <- isolation.forest(train_set[, ..keep], ntrees = 100,
                                ndim = 2, ntry = 100
                                ,prob_pick_avg_gain=0.5
    )
    
    #filename = paste0("model/", "modisof_h",nb_hops, "_a", nb_att, "_t", type)
    # save(mod_iso, file = paste0(filename, ".RData"))
  }else{
    mod_iso <- get("mod_iso")
  }
  scores <- predict(mod_iso, test_set[,..keep], na.action = na.exclude)
  pred_class <- factor(ifelse(scores > 0.5, 1, 0), 
                       levels = levels(test_set$attacked))
  
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_class, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "unsupervised"), score)
  rm(mod_iso)
  return (list(tmp, test_set))
}

do_lof <- function (dtf, unused, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  # Calculate LOF scores using minPts
  keep = -which(names(dtf) %in% remove_col_svm) #, "flow_size" c("attacked")
  c(is_charged, filename) %<-% is_charge_before(current_param)
  if (FALSE == is_charged)
  {
    lof_scores <- lof(dtf[,keep], minPts = 30)
    
    # save(lof_scores, file = paste0(filename, ".RData"))
  }else{
    lof_scores <- get("lof_scores")
  }
  # Define a threshold
  #threshold <- 1.05
  threshold <- quantile(lof_scores, 0.90, na.rm = T)
  # Identify and mark outliers
  outliers <- dtf[lof_scores > threshold, ]
  pred_lof = factor(ifelse(lof_scores > threshold, 1, 0), levels = levels(dtf$attacked))
  # err = as.numeric(sum(pred_lof != dtf$attacked))/length(dtf$attacked)
  # all_1 <- factor (rep (1, length(dtf$attacked)), levels = levels(dtf$attacked))
  # all_err <- as.numeric(sum(all_1 != dtf$attacked))/length(dtf$attacked)
  # all_0 <- factor (rep (0, length(dtf$attacked)), levels = levels(dtf$attacked))
  # no_err <- as.numeric(sum(all_0 != dtf$attacked))/length(dtf$attacked)
  # conf_lof <- table(dtf$attacked, pred_lof)
  # CM <- confusionMatrix(conf_lof)
  print(paste0("model: ",current_param$model))
  c(score, dtf) %<-% commun_info(dtf, pred_lof, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "analysis"
  )[, names(score) := score]
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "analysis"), score)
  rm(lof_scores)
  return (list(tmp, dtf))
}

# DBSCAN

do_oneclasssvm <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  keep = setdiff(names(train_set), remove_col_svm) #-which(names(train_set) %in% remove_col_svm) #, "flow_size" c("attacked")
  
  # Calculer les min et max pour chaque colonne
  mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
  maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
  
  # X <- train_set[, ..keep][, lapply(.SD, normalize_me)] #train_set[, !names(train_set) %in% remove_col] #c("attacked", "index", "packet_length")
  X_train_tmp <- train_set[, ..keep]
  X <- X_train_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  X[,attacked := train_set$attacked]
  
  # #X_test <- test_set[, ..keep][, lapply(.SD, normalize_me)]
  X_test_tmp <- test_set[, ..keep]
  # Appliquer normalize_me à chaque colonne avec ses propres min et max
  X_test <- X_test_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  print(paste0("ocsvm debug1:", !all(is.na(X[["delay"]]))))
  print(paste0("ocsvm debug2:", all(is.na(X[["delay"]]))))
  print(all(apply(apply(X_test, 2, FUN=is.na), 1, FUN=all)))
  if(!all(apply(apply(X, 2, FUN=is.na), 1, FUN=all))){ #!all(is.na(X[["delay"]]))){ #!
    if (FALSE == is_charged)
    {
      # Apprentissage du modèle One-Class SVM
      model_svm <- svm(
        x = X[,..keep], #train_set[,..keep],
        #y = X[, "attacked"],#train_set[,"attacked"],
        type = 'one-classification', 
        nu = 0.01,#current_param$prop,
        cost = 100,
        scale = F, 
        gamma = 0.5,
        kernel="radial", na.action = na.exclude)#, cross = 5)
      
      
      #filename = paste0("model/", "modonesvm_h",nb_hops, "_a", nb_att, "_t", type)
      # save(model_svm, file = paste0(filename, ".RData"))
    }else{
      model_svm <- get("model_svm")
    }
    anomalies_svm <- predict(model_svm, X_test, na.action = na.exclude)
    str(anomalies_svm)
    pred_svm = factor(ifelse(anomalies_svm, 0, 1), levels = levels(test_set$attacked))
    str(pred_svm)
    
  }else{
    pred_svm = factor(rep(NA,nrow(test_set)), levels = levels(test_set$attacked))
  }
  
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_svm, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, names(score) := score]
  rm(model_svm)
  return (list(tmp, test_set))
}

in_interval <- function(x, summary_delay)
{
  return (x <= summary_delay[2] & x >= summary_delay[1])
}
do_interval <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  ## method by interval
  keep_summary = setdiff(names(train_set), remove_col_summary)
  
  build_interval <- function(x){
    qsup <- quantile(x, 0.9, na.rm = TRUE)
    qinf <- quantile(x, 0.1, na.rm = TRUE)
    return(c(qinf, qsup))
  }
  
  summary_delay <- data.table(apply(train_set[,..keep_summary], MARGIN = 2, FUN = build_interval))
  
  results <- copy(test_set[,..keep_summary])
  for (col in names(test_set[,..keep_summary]))
  {
    results[[col]] <- apply(as.data.table(test_set[[col]]), 1, FUN = in_interval,summary_delay[[col]])
  }
  
  sum_results <- apply(results, MARGIN= 1, FUN = sum)
  
  anomalies <- (sum_results < dim(results)[2] /2)
  pred_base = factor(ifelse(anomalies, 1, 0), levels = levels(test_set$attacked))
  
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_base, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, names(score) := score]
  
  rm(results, summary_delay)
  return (list(tmp, test_set))
}

do_interval_delay <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  if ("fmean_delay" %in% colnames(train_set))
  {
    variable_delay = "fmean_delay"
  }else{
    variable_delay = "delay"
  }
  
  ## method by interval
  if (is_charged != TRUE)
  {
    keep_summary = setdiff(names(train_set), remove_col_summary)
    
    
    
    build_interval <- function(x){
      qsup <- quantile(x, 0.9, na.rm = TRUE)
      qinf <- quantile(x, 0.1, na.rm = TRUE)
      return(c(qinf, qsup))
    }
    
    summary_delay <- build_interval(train_set[[variable_delay]])
    if (current_param$do_evolution)
    {
      ##filename = paste0("model/", "modxgboost_h",nb_hops, "_a", nb_att, "_t", type)
      save(summary_delay, file = paste0(filename, ".RData"))
    }
  }else{
    summary_delay <- get("summary_delay")
    print("summary_delay interval chargé")
  }
  
  anomalies<- !in_interval(as.data.table(test_set[[variable_delay]]),summary_delay)
  
  
  
  pred_base = factor(ifelse(anomalies, 1, 0), levels = levels(test_set$attacked))
  
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_base, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, names(score) := score]
  
  rm(summary_delay)
  return (list(tmp, test_set))
}

do_threshold <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  # method by threshold on delay
  if ("fmean_delay" %in% colnames(train_set))
  {
    variable_delay = "fmean_delay"
  }else{
    variable_delay = "delay"
  }
  print(variable_delay)
  ## method by interval
  if (is_charged != TRUE)
  {
    keep_summary = setdiff(names(train_set), remove_col_summary)
    summary_delay <- quantile(train_set[[variable_delay]], 0.95, na.rm = TRUE)
    
    
    print(summary_delay)
    if (current_param$do_evolution)
    {
      ##filename = paste0("model/", "modxgboost_h",nb_hops, "_a", nb_att, "_t", type)
      save(summary_delay, file = paste0(filename, ".RData"))
    }
  }else{
    summary_delay <- get("summary_delay")
    print("summary_delay therhsold chargé")
  }
  anomalies <- test_set[[variable_delay]] > summary_delay
  pred_threshold = factor(ifelse(anomalies, 1, 0), levels = levels(test_set$attacked))
  
  print(paste0("model: ",current_param$model))
  c(score, test_set) %<-% commun_info(test_set, pred_threshold, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, names(score) := score]
  
  rm(anomalies, summary_delay)
  return (list(tmp, test_set))
  
}


# Representation Learning Models ####
## autoencoder
do_ae_simple <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  keep = setdiff(names(train_set), remove_col)#-which(names(train_set) %in% remove_col) #, "flow_size" c("attacked", "index", "packet_length")
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  # Preparation of data
  # Seperate target column
  # Calculer les min et max pour chaque colonne
  mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
  maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
  
  # X <- train_set[, ..keep][, lapply(.SD, normalize_me)] #train_set[, !names(train_set) %in% remove_col] #c("attacked", "index", "packet_length")
  X_train_tmp <- train_set[, ..keep]
  X <- X_train_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # #X_test <- test_set[, ..keep][, lapply(.SD, normalize_me)]
  X_test_tmp <- test_set[, ..keep]
  # Appliquer normalize_me à chaque colonne avec ses propres min et max
  X_test <- X_test_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # X <- as.data.frame(lapply(X, normalize_me))
  # X_test <- as.data.frame(lapply(X_test, normalize_me))
  # To matrix conversion
  X <- as.matrix(X)
  X_test <- as.matrix(X_test)
  
  
  
  
  if (is_charged != TRUE){
    
    # defining dimensions
    input_dim <- ncol(X)
    latent_dim <- 6
    intermediate_dim <- 12
    
    # model definition
    ## encoder
    input_layer <- layer_input(shape = input_dim)
    x <- layer_dense(input_layer, units = intermediate_dim, activation = "relu")
    z <- layer_dense(x, units = latent_dim, activation = "relu") # Goulot d'étranglement
    encoder <- keras_model(input_layer, z, name="encoder")
    
    ## decoder
    inputs <- layer_input(shape = c(latent_dim)) 
    x <- layer_dense(inputs, units = intermediate_dim, activation = "relu")
    outputs <- layer_dense(x, units = input_dim, activation = "sigmoid")
    decoder <- keras_model(inputs, outputs, name="decoder")
    
    ## autoencodeur
    inputs <- layer_input(shape = input_dim)
    latents <- encoder(inputs)
    outputs <- decoder(latents)
    mod_ae <- keras_model(inputs, outputs, name="ae")
    
    # Model compilation
    mod_ae %>% compile(
      loss = "mse",
      optimizer = optimizer_adam(learning_rate = 0.001)
    )
    # Model training
    history <- mod_ae %>% fit(
      x= X, y= X,  # Entrée = Sortie (car autoencodeur)
      epochs = 1000, #440,
      batch_size = floor(nrow(X)*0.1),
      shuffle = T,
      validation_split = 0.2,
      verbose = 1,
      callbacks = list(callback_early_stopping(patience = 10, restore_best_weights = TRUE))
    )
    
    #save(mod_ae, file = paste0(filename, ".RData"))
  }else{
    mod_ae <- get("mod_ae")
  }
  
  X_pred <- mod_ae %>% predict(X_test)
  # Calcul de l'erreur de reconstruction (MSE)
  reconstruction_error <- rowMeans((X_test - X_pred)^2, na.rm = TRUE)
  
  # Définition d'un seuil (ex : quantile 95% des erreurs sur les normales)
  threshold <- quantile(reconstruction_error, 0.95, na.rm = TRUE)
  
  # Marquage des anomalies
  predicted_anomalies <- factor(ifelse(reconstruction_error > threshold, 1, 0), levels = levels(test_set$attacked))
  
  c(score, test_set) %<-% commun_info(test_set, predicted_anomalies, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp =  data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, c(names(score)) := score]
  # cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "unsupervised"), score)
  rm(mod_ae)
  
  
  # Comparaison avec la vraie colonne 'attacked'
  #print(table(Predicted = predicted_anomalies, Actual = test_set$attacked))
  return (list(tmp, test_set))
}


do_ae_binary <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  #keep = -which(names(train_set) %in% remove_col) #, "flow_size" c("attacked", "index", "packet_length" )
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  # Preparation of data
  # Seperate target column
  keep <- setdiff(names(train_set), remove_col)
  # Calculer les min et max pour chaque colonne
  mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
  maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
  
  # X <- train_set[, ..keep][, lapply(.SD, normalize_me)] #train_set[, !names(train_set) %in% remove_col] #c("attacked", "index", "packet_length")
  X_train_tmp <- train_set[, ..keep]
  X <- X_train_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # #X_test <- test_set[, ..keep][, lapply(.SD, normalize_me)]
  X_test_tmp <- test_set[, ..keep]
  # Appliquer normalize_me à chaque colonne avec ses propres min et max
  X_test <- X_test_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  
  # X <- X[, lapply(.SD, normalize_me)]
  # X_test <- X_test[, lapply(.SD, normalize_me)]
  # X <- as.data.frame(lapply(X, normalize_me))
  # X_test <- as.data.frame(lapply(X_test, normalize_me))
  # To matrix conversion
  X <- as.matrix(X)
  X_test <- as.matrix(X_test)
  train_att <- as.matrix(as.numeric(as.character(train_set$attacked)))
  test_att <- as.matrix(as.numeric(as.character(test_set$attacked)))
  
  
  
  if (is_charged != TRUE){
    
    # defining dimensions
    input_dim <- ncol(X)
    counts <- table(train_att)
    # weight_for_0 = 1 / (2 * (counts["0"]/ sum(counts)))
    # weight_for_1 = 1 / (2 * (counts["1"]/ sum(counts)))
    
    # weight_for_0 = 1 / counts["0"]
    # weight_for_1 = 1 / counts["1"]
    weight_for_0 <- log(1 + train_set[, .N]/counts["0"])
    weight_for_1 <- log(1 + train_set[, .N]/counts["1"])
    class_weight <- list("0" = weight_for_0,
                         "1" = weight_for_1)
    
    # model definition
    inputs <- layer_input(shape = c(input_dim))
    x <- layer_dense(inputs, units = 26, activation = "relu")
    #x <- layer_dense(x, units = 20, activation = "relu")
    #x <- layer_dense(x, units = 16, activation = "relu")
    x <- layer_dense(x, units = 8, activation = "relu")
    #x <- layer_dropout(x, 0.2)
    #x <- layer_dense(x, units = 4, activation = "relu")
    #x <- layer_dropout(x, 0.2)
    z <- layer_dense(x, units = 1, activation = "sigmoid", )
    classifier <- keras_model(inputs, z, name="classifier")
    
    
    metrics <- list( #metric_false_negatives(name = "fn"),
      metric_false_positives(name = "fp"),
      #metric_true_negatives(name = "tn"),
      metric_true_positives(name = "tp"),
      metric_precision(name = "precision"),
      metric_recall(name = "recall"),
      metric_f1_score(name = "f1"))
    
    # Model compilation
    classifier %>% compile(
      loss = loss_binary_crossentropy(), #loss_binary_focal_crossentropy(alpha = 1),
      optimizer = optimizer_adam(learning_rate = 0.001),
      metrics = metrics
    )
    callbacks <- list(
      #callback_model_checkpoint("fraud_model_at_epoch_{epoch}.keras"),
      callback_early_stopping(patience = 10, restore_best_weights = TRUE)
    )
    
    # Model training
    
    history <- classifier %>% fit(
      X, train_att,  # Entrée = Sortie (car autoencodeur)
      #validation_data = list(X_val, val_att),
      class_weight = class_weight,
      epochs = 1000,
      batch_size = floor(nrow(X)*0.1), #32,
      #callbacks = callbacks,
      validation_split = 0.2,
      verbose = 1,
      shuffle = TRUE,
      callbacks = list(callback_early_stopping(patience = 50, restore_best_weights = TRUE))
    )
    #filename2 = paste0("model/", "modae_bin")
    #save(classifier, file = paste0(filename, ".RData"))
  }else{
    classifier <- get("classifier")
    #classifier <- keras::load_model_hdf5(filename)
  }
  
  test_pred <- classifier %>% predict(X_test)
  threshold <- 0.5 #current_param$threshold %||% 0.5
  test_pred <- as.integer(test_pred > threshold)
  
  # Marquage des anomalies
  predicted_anomalies <- factor(test_pred, levels = levels(test_set$attacked))
  
  c(score, test_set) %<-% commun_info(test_set, predicted_anomalies, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  # tmp =  cbind(data.frame(path_length = nb_hops, nb_detour = nb_att,
  #                         model = current_param$model, 
  #                         approach = "supervised"), score)
  tmp <- data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "supervised"
  )[, c(names(score)) := score]
  rm(classifier)
  
  
  # Comparaison avec la vraie colonne 'attacked'
  #print(table(Predicted = predicted_anomalies, Actual = test_set$attacked))
  return (list(tmp, test_set))
}

# variational autoencoder
do_vae <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  
  vae_features <- c(
    # robustes niveau/dispersion
    "fmedian_delay", "fmad_delay", "fIQR_delay", "fCV_delay", "fQ095_delay", "fQ095_Q005", "fmeanTRIM10_delay",
    # jitter                   
    "fMASD_delay","fRMSJ_delay", "fsd_diff_delay", "fIPDV_neg_delay", "fIPDV_pos_delay",
    # dépendance & changements                   
    "facf_lag0","facf_lag1","facf_lag2","facf_lag3","facf_lag4",
    "facf_lag5","facf_lag6","facf_lag7","facf_lag8","facf_lag9","facf_lag10",
    "fACF_sum", "fslope_t", "fCUSUM_max", "fearly_diff", 
    # régression d~L
    "alpha_hat","beta_hat", "r2", "sigma_eps",
    #files d'attente
    "rho_tilde", "lambda_hat", "fmean_delay","fQ095_delay","duty","run_max",
    #queues
    "fkurtosis_delay", "fskew_delay", "fhill",
    #meta
    "delay", "flow_size",
    "t_start","t_end"#,
    #"fmean_mean", "fmedian_median"
    )
  
  if (!use_temporal_covariates) {
    vae_features <- setdiff(vae_features, c("t_start", "t_end"))
  }
  if (!is.null(reduced_feature_set)) {
    .n_before <- length(vae_features)
    vae_features <- intersect(vae_features, reduced_feature_set)
    cat(sprintf("[FEATSET] vae : %d -> %d variables (jeu reduit de %d)\n",
                .n_before, length(vae_features), length(reduced_feature_set)))
    cat("[FEATSET] vae retenues :", paste(vae_features, collapse = ", "), "\n")
    if (length(vae_features) == 0L)
      stop("[ERROR] vae : le jeu reduit ne recouvre aucune variable du modele.")
  }
  #keep = setdiff(names(train_set), remove_col)#-which(names(train_set) %in% remove_col) #, "flow_size" c("attacked", "index", "packet_length")
  keep = colnames(train_set)[colnames(train_set) %in% vae_features]
  skew_cols <- intersect(c("fCUSUM_max","fhill","rho_tilde","lambda_hat",
                           "fQ095_delay","fQ095_Q005","fPOT_rate_u",
                           "fmean_delay","fQ095_delay","run_max"), names(train_set))
  for (nm in skew_cols) train_set[[nm]] <- log1p(pmax(train_set[[nm]], 0))
  skew_cols <- intersect(c("fCUSUM_max","fhill","rho_tilde","lambda_hat",
                           "fQ095_delay","fQ095_Q005","fPOT_rate_u",
                           "fmean_delay","fQ095_delay","run_max"), names(test_set))
  for (nm in skew_cols) test_set[[nm]] <- log1p(pmax(test_set[[nm]], 0))
  c(is_charged, filename) %<-% is_charge_before(current_param, "_encoder.keras")
  
  # Preparation of data
  # Seperate target column
  # Calculer les min et max pour chaque colonne
  mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
  maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
  
  # X <- train_set[, ..keep][, lapply(.SD, normalize_me)] #train_set[, !names(train_set) %in% remove_col] #c("attacked", "index", "packet_length")
  X_train_tmp <- train_set[, ..keep]
  X <- X_train_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # #X_test <- test_set[, ..keep][, lapply(.SD, normalize_me)]
  X_test_tmp <- test_set[, ..keep]
  # Appliquer normalize_me à chaque colonne avec ses propres min et max
  X_test <- X_test_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  
  # X <- as.data.frame(lapply(X, normalize_me))
  # X_test <- as.data.frame(lapply(X_test, normalize_me))
  # To matrix conversion
  X <- as.matrix(X)
  X_test <- as.matrix(X_test)
  train_att <- as.matrix(as.numeric(as.character(train_set$attacked)))
  test_att <- as.matrix(as.numeric(as.character(test_set$attacked)))
  
  # Fonction d’échantillonnage pour extraire z
  layer_sampler <- new_layer_class(
    classname = "Sampler",
    call = function(z_mean, z_log_var) {
      epsilon <- tf$random$normal(shape = tf$shape(z_mean))
      z_mean + exp(0.5 * z_log_var) * epsilon }
  )
  
  if (is_charged != TRUE){
    
    # Dimensions du VAE
    original_dim <- ncol(X) # input_dim
    latent_dim <- 2L # Taille de l’espace latent
    intermediate_dim <- original_dim /2 -1
    # model definition
    # Entrée
    input_layer <- layer_input(shape = original_dim)
    
    # Encodeur : transformation vers un espace latent
    x <- layer_dense(input_layer, units = intermediate_dim, activation = "relu")
    
    z_mean <- layer_dense(x, units = latent_dim, name = "z_mean")  # Moyenne
    z_log_var <- layer_dense(x, units = latent_dim, name = "z_log_var")  # Log-variance
    
    encoder <- keras_model(input_layer, list(z_mean, z_log_var), name= "encoder")
    
    
    
    # Décodeur
    decoder_input <- layer_input(shape = latent_dim)
    decoder_dense <- decoder_input %>%
      layer_dense(units = intermediate_dim, activation = "relu") %>%
      #layer_dense(units = 64, activation = "relu") %>%
      layer_dense(units = original_dim, activation = "sigmoid") #linear")
    
    # Modèle du décodeur
    decoder <- keras_model(decoder_input, decoder_dense, name="decoder")
    
    
    
    ## autoencodeur
    model_vae <- new_model_class(
      classname = "VAE",
      
      initialize = function(encoder, decoder, ...) {
        super$initialize(...)
        self$encoder <- encoder
        self$decoder <- decoder
        self$sampler <- layer_sampler()
        self$total_loss_tracker <- metric_mean(name = "total_loss")
        self$reconstruction_loss_tracker <- metric_mean(name = "reconstruction_loss")
        self$kl_loss_tracker <- metric_mean(name = "kl_loss")
      },
      
      metrics = mark_active(function() {
        list(
          self$total_loss_tracker,
          self$reconstruction_loss_tracker,
          self$kl_loss_tracker
        )
      }),
      
      train_step = function(data) {
        with(tf$GradientTape() %as% tape, {
          
          c(z_mean, z_log_var) %<-% self$encoder(data)
          z <- self$sampler(z_mean, z_log_var)
          
          reconstruction <- decoder(z)
          reconstruction_loss <-
            loss_binary_crossentropy(data, reconstruction) %>%
            sum(axis = c(1)) %>%
            mean()
          
          kl_loss <- -0.5 * (1 + z_log_var - z_mean^2 - exp(z_log_var))
          total_loss <- reconstruction_loss + mean(kl_loss)
        })
        
        grads <- tape$gradient(total_loss, self$trainable_weights)
        self$optimizer$apply_gradients(zip_lists(grads, self$trainable_weights))
        
        self$total_loss_tracker$update_state(total_loss)
        self$reconstruction_loss_tracker$update_state(reconstruction_loss)
        self$kl_loss_tracker$update_state(kl_loss)
        
        list(total_loss = self$total_loss_tracker$result(),
             reconstruction_loss = self$reconstruction_loss_tracker$result(),
             kl_loss = self$kl_loss_tracker$result())
      }
    )
    
    vae <- model_vae(encoder, decoder)
    vae %>% compile(optimizer = optimizer_adam())
    vae %>% fit(X, epochs = 1000,
                shuffle = TRUE,
                batch_size = floor(nrow(X)*0.1),
                callbacks = list(callback_early_stopping(patience = 10, 
                                                         restore_best_weights = TRUE, 
                                                         monitor = "total_loss",
                                                         mode = "min"))
    )
    vae_encoder <- vae$encoder
    vae_decoder <- vae$decoder
    if (current_param$do_evolution)
    {
      #save(vae, file = paste0(filename, ".RData"))
      # To save a Keras model properly
      #save_model(vae$encoder, filepath = paste0(filename, "_encoder.keras"), overwrite = T)
      #save_model(vae$decoder, filepath = paste0(filename, "_decoder.keras"), overwrite = T)
      
      # Or save the entire VAE if it's a unified model
      #save_model(vae, filepath = paste0(filename, ".keras"), overwrite = T)
      save_model(vae$encoder, filepath = paste0(filename, "_encoder.keras"), overwrite = T)
      save_model(vae$decoder, filepath = paste0(filename, "_decoder.keras"), overwrite = T)
      vae_keep <- keep
      save(vae_keep, file = paste0(filename, "_keep.RData"))
    }
  }else{
    #vae <- get("vae")
    #vae <- load_model(paste0(filename, ".keras"))
    vae_encoder <- load_model(paste0(filename, "_encoder.keras"))
    vae_decoder <- load_model(paste0(filename, "_decoder.keras"))
    print("vae chargé")
    # Realign columns if saved keep differs from current keep
    keep_file <- paste0(filename, "_keep.RData")
    if (file.exists(keep_file)) {
      load(keep_file)  # loads vae_keep
      missing_in_train <- setdiff(vae_keep, colnames(train_set))
      missing_in_test <- setdiff(vae_keep, colnames(test_set))
      if (length(missing_in_train) > 0 || length(missing_in_test) > 0) {
        print(paste("VAE: realignment colonnes, manquantes:", paste(union(missing_in_train, missing_in_test), collapse=", ")))
        for (mc in missing_in_train) train_set[, (mc) := 0]
        for (mc in missing_in_test) test_set[, (mc) := 0]
      }
      keep <- vae_keep
      # Recalculate X and X_test with aligned keep
      mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
      maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
      X <- train_set[, ..keep][, Map(function(col, minv, maxv) { normalize_me(col, min_val = minv, max_val = maxv) }, .SD, mins, maxs)]
      X <- as.matrix(X)
      X_test <- test_set[, ..keep][, Map(function(col, minv, maxv) { normalize_me(col, min_val = minv, max_val = maxv) }, .SD, mins, maxs)]
      X_test <- as.matrix(X_test)
    }
  }
  
  sampler <- layer_sampler()
  pred <-  predict(vae_encoder,X_test)#, batch_size = batch_size)
  pred_mean <- (pred[[1]])
  pred_logvar <- pred[[2]]
  z <- sampler(pred_mean, pred_logvar)
  
  X_pred <- predict(vae_decoder, z)#, batch_size = batch_size)
  reconstruction_error <- rowMeans((X_test - X_pred)^2, na.rm = TRUE)
  
  # Définition d'un seuil (ex : quantile 95% des erreurs sur les normales)
  threshold <- quantile(reconstruction_error, 0.90, na.rm = TRUE)
  
  # Marquage des anomalies
  predicted_anomalies <- factor(ifelse(reconstruction_error > threshold, 1, 0), levels = levels(test_set$attacked))
  
  c(score, test_set) %<-% commun_info(test_set, predicted_anomalies, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp =  data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, c(names(score)) := score]
  
  latent_space <- data.table(apply(z, MARGIN = 2, FUN = as.numeric))
  latent_space$label <- factor(test_att, levels = c(0, 1), labels = c("Normal", "Anomaly"))
  # Compute centroids for each class
  centroid_cols <- setdiff(names(latent_space), "label")
  centroids <- latent_space[, lapply(.SD, mean), by = label, .SDcols = centroid_cols]
  # Compute pairwise distances between centroids
  centroid_matrix <- as.matrix(centroids[, -"label"])
  distances <- dist(centroid_matrix, method = "euclidean")
  latent_separation <- mean(distances)
  
  kl_div <- -0.5 * mean(1 + pred_logvar - pred_mean^2 - exp(pred_logvar))
  
  # Total variance across all latent dimensions
  total_variance <- sum(apply(z, 2, var))
  
  # Mean variance per dimension
  mean_variance <- mean(apply(z, 2, var))
  
  
  #sil <- silhouette(as.numeric(as.factor(test_att)), dist(z))
  #mean_silhouette <- mean(sil[, 3])
  
  dtf_model_info <- data.table(simulation_time = current_param$simulation_time, 
                               latency = current_param$latency, 
                               bandwidth = current_param$bandwidth, 
                               data_rate = current_param$data_rate,
                               parasite_rate = current_param$parasite_rate,
                               meanexp = current_param$meanexp,
                               parasite_meanexp = current_param$parasite_meanexp,
                               nb_hops = current_param$nb_hops,
                               nb_att = current_param$nb_att,
                               prop_att = current_param$prop,
                               group = current_param$group,
                               model = current_param$model,
                               protocol = current_param$proto,
                               do_evolution = current_param$do_evolution,
                               trainonparasite = current_param$trainonparasite,
                               trainondetour = current_param$trainondetour,
                               trainonpath = current_param$trainonpath,
                               my_seed = current_param$my_seed,
                               first_variable = NA,
                               second_variable = kl_div,
                               F1_score = score$F1_score,
                               Recall = score$Recall,
                               Precision = score$Precision,
                               critere1 = mean((X_test - X_pred)^2, na.rm = TRUE),
                               critere2 = latent_separation,
                               critere3 =  mean_variance, #mean_silhouette
                               critere4 = mean_variance,
                               date = as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M:%OS6"))
  )
  file_name <- paste0("scratch/ninth/model/_model_info.csv")
  write.table(dtf_model_info, file_name, sep = ",", append = TRUE, row.names = F)
  rm(vae, vae_encoder, vae_decoder)
  
  
  # Comparaison avec la vraie colonne 'attacked'
  #print(table(Predicted = predicted_anomalies, Actual = test_set$attacked))
  return (list(tmp, test_set))
}

# denoising autoencoder
do_dae <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  #type = current_param$type
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  dae_features <- c(
    # robustes niveau/dispersion
    "fmedian_delay", "fmad_delay", "fIQR_delay", "fCV_delay", "fQ095_delay", "fQ095_Q005", "fmeanTRIM10_delay",
    # jitter                   
    "fMASD_delay","fRMSJ_delay", "fsd_diff_delay", "fIPDV_neg_delay", "fIPDV_pos_delay",
    # dépendance & changements                   
    "facf_lag0","facf_lag1","facf_lag2","facf_lag3","facf_lag4",
    "facf_lag5","facf_lag6","facf_lag7","facf_lag8","facf_lag9","facf_lag10",
    "fACF_sum", "fslope_t", "fCUSUM_max", "fearly_diff", 
    # régression d~L
    "alpha_hat","beta_hat", "r2", "sigma_eps",
    #files d'attente
    "rho_tilde", "lambda_hat", 
    #queues
    "fkurtosis_delay", "fskew_delay", "fhill",
    #meta
    "delay", "flow_size",
    "fmean_delay","fQ095_delay","duty","run_max",
    "t_start", "t_end"
    #"fmean_mean", "fmedian_median"
    )
  
  if (!use_temporal_covariates) {
    dae_features <- setdiff(dae_features, c("t_start", "t_end"))
  }
  
  if (!is.null(reduced_feature_set)) {
    .n_before <- length(dae_features)
    dae_features <- intersect(dae_features, reduced_feature_set)
    cat(sprintf("[FEATSET] dae : %d -> %d variables (jeu reduit de %d)\n",
                .n_before, length(dae_features), length(reduced_feature_set)))
    cat("[FEATSET] dae retenues :", paste(dae_features, collapse = ", "), "\n")
    if (length(dae_features) == 0L)
      stop("[ERROR] dae : le jeu reduit ne recouvre aucune variable du modele.")
  }
  #keep = setdiff(names(train_set), remove_col)
  keep = colnames(train_set)[colnames(train_set) %in% dae_features]
  skew_cols <- intersect(c("fCUSUM_max","fhill","rho_tilde","lambda_hat",
                           "fQ095_delay","fQ095_Q005","fPOT_rate_u",
                           "fmean_delay","fQ095_delay","run_max"), names(train_set))
  for (nm in skew_cols) train_set[[nm]] <- log1p(pmax(train_set[[nm]], 0))
  skew_cols <- intersect(c("fCUSUM_max","fhill","rho_tilde","lambda_hat",
                           "fQ095_delay","fQ095_Q005","fPOT_rate_u",
                           "fmean_delay","fQ095_delay","run_max"), names(test_set))
  for (nm in skew_cols) test_set[[nm]] <- log1p(pmax(test_set[[nm]], 0))
  
  c(is_charged, filename) %<-% is_charge_before(current_param, ".keras")
  
  # Preparation of data
  # Seperate target column
  # Calculer les min et max pour chaque colonne
  mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
  maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
  
  # X <- train_set[, ..keep][, lapply(.SD, normalize_me)] #train_set[, !names(train_set) %in% remove_col] #c("attacked", "index", "packet_length")
  X_train_tmp <- train_set[, ..keep]
  X <- X_train_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # #X_test <- test_set[, ..keep][, lapply(.SD, normalize_me)]
  X_test_tmp <- test_set[, ..keep]
  # Appliquer normalize_me à chaque colonne avec ses propres min et max
  X_test <- X_test_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # X <- as.data.frame(lapply(X, normalize_me))
  # X_test <- as.data.frame(lapply(X_test, normalize_me))
  # To matrix conversion
  X <- as.matrix(X)
  X_test <- as.matrix(X_test)
  
  
  add_noise <- function(x, noise_factor = 0.3) {
    x + noise_factor * matrix(rnorm(length(x)), nrow = nrow(x), ncol = ncol(x))
  }
  
  if (is_charged != TRUE){
    
    # Dimensions du DAE
    original_dim <- ncol(X) # input_dim
    latent_dim <- 6L # 6L Taille de l’espace latent
    intermediate_dim <- 12
    
    # Entrée
    input_layer <- layer_input(shape = original_dim)
    
    # Encodeur : transformation vers un espace latent
    #encoder_dense <- input_layer
    x <- layer_dense(input_layer, units = intermediate_dim, activation = "relu")
    
    z <- layer_dense(x, units = latent_dim, activation = "relu")  
    
    encoder <- keras_model(input_layer, z, name= "encoder")
    
    # Décodeur
    decoder_input <- layer_input(shape = latent_dim)
    decoder_dense <- decoder_input %>%
      layer_dense(units = intermediate_dim, activation = "relu") %>%
      #layer_dense(units = 64, activation = "relu") %>%
      layer_dense(units = original_dim, activation = "sigmoid") #linear")
    
    # Modèle du décodeur
    decoder <- keras_model(decoder_input, decoder_dense, name="decoder")
    
    inputs <- layer_input(shape = original_dim)
    latents <- encoder(inputs)
    outputs <- decoder(latents)
    mod_dae <- keras_model(inputs, outputs, name="dae")
    mod_dae %>% compile(optimizer = optimizer_adam(), loss = "mse")
    
    
    X_noisy <- add_noise(X, noise_factor = 0.2)
    mod_dae %>% fit(x= X_noisy, y= X, 
                    epochs = 1000, #600,
                    batch_size = floor(nrow(X)*0.1), #75
                    shuffle = TRUE,
                    validation_split = 0.2,
                    callbacks = list(callback_early_stopping(patience = 10, restore_best_weights = TRUE))
    )
    
    if (current_param$do_evolution)
    {
    #save(mod_dae, file = paste0(filename, ".RData"))
      save_model(mod_dae, filepath = paste0(filename, ".keras"), overwrite = T)
      dae_keep <- keep
      save(dae_keep, file = paste0(filename, "_keep.RData"))
    }
  }else{
    #mod_dae <- get("mod_dae")
    mod_dae <- load_model(paste0(filename, ".keras"))
    print("mod_dae chargé")
    # Realign columns if saved keep differs from current keep
    keep_file <- paste0(filename, "_keep.RData")
    if (file.exists(keep_file)) {
      load(keep_file)  # loads dae_keep
      missing_in_train <- setdiff(dae_keep, colnames(train_set))
      missing_in_test <- setdiff(dae_keep, colnames(test_set))
      if (length(missing_in_train) > 0 || length(missing_in_test) > 0) {
        print(paste("DAE: realignment colonnes, manquantes:", paste(union(missing_in_train, missing_in_test), collapse=", ")))
        for (mc in missing_in_train) train_set[, (mc) := 0]
        for (mc in missing_in_test) test_set[, (mc) := 0]
      }
      keep <- dae_keep
      # Recalculate X and X_test with aligned keep
      mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
      maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
      X <- train_set[, ..keep][, Map(function(col, minv, maxv) { normalize_me(col, min_val = minv, max_val = maxv) }, .SD, mins, maxs)]
      X <- as.matrix(X)
      X_test <- test_set[, ..keep][, Map(function(col, minv, maxv) { normalize_me(col, min_val = minv, max_val = maxv) }, .SD, mins, maxs)]
      X_test <- as.matrix(X_test)
    }
  }
  
  X_test_noisy <- add_noise(X_test)
  X_pred <- mod_dae %>% predict(X_test_noisy)
  # Calcul de l'erreur de reconstruction (MSE)
  reconstruction_error <- rowMeans((X_test - X_pred)^2, na.rm = TRUE)
  
  # Définition d'un seuil (ex : quantile 95% des erreurs sur les normales)
  threshold <- quantile(reconstruction_error, 0.90, na.rm = TRUE)
  
  # Marquage des anomalies
  predicted_anomalies <- factor(ifelse(reconstruction_error > threshold, 1, 0), levels = levels(test_set$attacked))
  
  c(score, test_set) %<-% commun_info(test_set, predicted_anomalies, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp =  data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, c(names(score)) := score]
  # cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "unsupervised"), score)
  
  
  dae_encoder <- get_layer(mod_dae, name= "encoder")
  z <- dae_encoder %>% predict(X_test_noisy)
  latent_space <- data.table(apply(z, MARGIN = 2, FUN = as.numeric))
  latent_space$label <- factor(test_set$attacked, levels = c(0, 1), labels = c("Normal", "Anomaly"))
  
  # Compute centroids for each class
  centroid_cols <- setdiff(names(latent_space), "label")
  centroids <- latent_space[, lapply(.SD, mean), by = label, .SDcols = centroid_cols]
  # Compute pairwise distances between centroids
  centroid_matrix <- as.matrix(centroids[, -"label"])
  distances <- dist(centroid_matrix, method = "euclidean")
  latent_separation <- mean(distances)
  

  # Total variance across all latent dimensions
  total_variance <- sum(apply(z, 2, var))
  
  # Mean variance per dimension
  mean_variance <- mean(apply(z, 2, var))
  
  
  # sil <- silhouette(as.numeric(as.factor(test_set$attacked)), dist(z))
  # mean_silhouette <- mean(sil[, 3])
  
  dtf_model_info <- data.table(simulation_time = current_param$simulation_time, 
                               latency = current_param$latency, 
                               bandwidth = current_param$bandwidth, 
                               data_rate = current_param$data_rate,
                               parasite_rate = current_param$parasite_rate,
                               meanexp = current_param$meanexp,
                               parasite_meanexp = current_param$parasite_meanexp,
                               nb_hops = current_param$nb_hops,
                               nb_att = current_param$nb_att,
                               prop_att = current_param$prop,
                               group = current_param$group,
                               model = current_param$model,
                               protocol = current_param$proto,
                               do_evolution = current_param$do_evolution,
                               trainonparasite = current_param$trainonparasite,
                               trainondetour = current_param$trainondetour,
                               trainonpath = current_param$trainonpath,
                               my_seed = current_param$my_seed,
                               first_variable = NA,
                               second_variable = NA,
                               F1_score = score$F1_score,
                               Recall = score$Recall,
                               Precision = score$Precision,
                               critere1 = mean((X_test - X_pred)^2, na.rm = TRUE),
                               critere2 = latent_separation,
                               critere3 =  mean_variance, #mean_silhouette,
                               critere4 = mean_variance,
                               date = as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M:%OS6"))
  )
  file_name <- paste0("scratch/ninth/model/_model_info.csv")
  write.table(dtf_model_info, file_name, sep = ",", append = TRUE, row.names = F)
  rm(mod_dae)
  
  
  # Comparaison avec la vraie colonne 'attacked'
  #print(table(Predicted = predicted_anomalies, Actual = test_set$attacked))
  return (list(tmp, test_set))
}


do_ae_contractive <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  keep = setdiff(names(train_set), remove_col)#-which(names(train_set) %in% remove_col) #, "flow_size" c("attacked", "index", "packet_length")
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  # Preparation of data
  # Seperate target column
  # Calculer les min et max pour chaque colonne
  mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
  maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
  
  # X <- train_set[, ..keep][, lapply(.SD, normalize_me)] #train_set[, !names(train_set) %in% remove_col] #c("attacked", "index", "packet_length")
  X_train_tmp <- train_set[, ..keep]
  X <- X_train_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # #X_test <- test_set[, ..keep][, lapply(.SD, normalize_me)]
  X_test_tmp <- test_set[, ..keep]
  # Appliquer normalize_me à chaque colonne avec ses propres min et max
  X_test <- X_test_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # X <- as.data.frame(lapply(X, normalize_me))
  # X_test <- as.data.frame(lapply(X_test, normalize_me))
  # To matrix conversion
  X <- as.matrix(X)
  X_test <- as.matrix(X_test)
  train_att <- as.matrix(as.numeric(as.character(train_set$attacked)))
  test_att <- as.matrix(as.numeric(as.character(test_set$attacked)))
  
  
  
  if (is_charged != TRUE){
    
    # Dimensions
    input_dim <- ncol(X)
    encoding_dim <- 10 #2
    contractive_lambda <- 1e-4  # penalty strength
    
    # model definition
    # Entrée
    input <- layer_input(shape = input_dim)
    
    # Encoder
    encoded <- input |>
      layer_dense(units = encoding_dim, activation = "sigmoid", name = "encoded")
    
    # Decoder
    decoded <- encoded |>
      layer_dense(units = input_dim, activation = "linear")
    
    mod_contractive <- keras_model(input, decoded)
    encoder_model <- keras_model(inputs = input, outputs = mod_contractive$get_layer("encoded")$output)
    
    # Initialize model weights (required before accessing them)
    mod_contractive %>% compile(optimizer = "adam", loss = "mse")
    mod_contractive %>% predict(matrix(runif(input_dim), nrow = 1))  # Dummy forward pass to build weights
    
    # Extract encoder weights as constant tensor
    W_matrix <- mod_contractive$get_layer("encoded")$weights[[1]]  # shape (input_dim, encoding_dim)
    
    # Custom contractive loss
    contractive_loss <- function(W, contractive_lambda) {
      function(y_true, y_pred) {
        #k <- backend()
        
        # MSE part
        mse <- op_mean(op_square(y_pred - y_true))
        
        # Hidden activation
        h <- encoder_model(y_true)
        
        # Derivative of sigmoid
        dh <- h * (1 - h)  # shape: (batch_size, encoding_dim)
        
        # Sum over input dimension weights (squared)
        W_squared_sum <- op_sum(op_square(W), axis = 1)  # shape: (encoding_dim,)
        
        # Broadcast multiplication and sum
        contractive_term <- op_sum(dh^2 * W_squared_sum)
        
        return(mse + contractive_lambda * contractive_term)
      }
    }
    
    # Compile with custom loss
    mod_contractive %>% compile(
      optimizer = "adam",
      loss = contractive_loss(W_matrix, contractive_lambda)
    )
    
    # Fit model
    history <- mod_contractive %>% fit(
      X, X,
      epochs = 1000,
      batch_size = floor(nrow(X)*0.1), #16,
      validation_split = 0.2,
      callbacks = list(callback_early_stopping(patience = 10, restore_best_weights = TRUE))
    )
    
    #save(vae, file = paste0(filename, ".RData"))
  }else{
    mod_contractive <- get("mod_contractive")
  }
  
  X_pred <-  predict(mod_contractive,X_test)
  reconstruction_error <- rowMeans((X_test - X_pred)^2, na.rm = TRUE)
  
  # Définition d'un seuil (ex : quantile 95% des erreurs sur les normales)
  threshold <- quantile(reconstruction_error, 0.95, na.rm = TRUE)
  
  # Marquage des anomalies
  predicted_anomalies <- factor(ifelse(reconstruction_error > threshold, 1, 0), levels = levels(test_set$attacked))
  
  c(score, test_set) %<-% commun_info(test_set, predicted_anomalies, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp =  data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, c(names(score)) := score]
  
  rm(mod_contractive)
  
  
  # Comparaison avec la vraie colonne 'attacked'
  #print(table(Predicted = predicted_anomalies, Actual = test_set$attacked))
  return (list(tmp, test_set))
}



do_ae_sparse <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  keep = setdiff(names(train_set), remove_col)#-which(names(train_set) %in% remove_col) #, "flow_size" c("attacked", "index", "packet_length")
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  # Preparation of data
  # Seperate target column
  # Calculer les min et max pour chaque colonne
  mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
  maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
  
  # X <- train_set[, ..keep][, lapply(.SD, normalize_me)] #train_set[, !names(train_set) %in% remove_col] #c("attacked", "index", "packet_length")
  X_train_tmp <- train_set[, ..keep]
  X <- X_train_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # #X_test <- test_set[, ..keep][, lapply(.SD, normalize_me)]
  X_test_tmp <- test_set[, ..keep]
  # Appliquer normalize_me à chaque colonne avec ses propres min et max
  X_test <- X_test_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # X <- as.data.frame(lapply(X, normalize_me))
  # X_test <- as.data.frame(lapply(X_test, normalize_me))
  # To matrix conversion
  X <- as.matrix(X)
  X_test <- as.matrix(X_test)
  
  if (is_charged != TRUE){
    
    # Dimensions du DAE
    input_dim <- ncol(X)
    encoding_dim <- 5
    rho <- 0.05              # Desired average activation of hidden neurons
    beta <- 1                # Weight of sparsity penalty
    l1_penalty <- 1e-4       # Optional L1 regularization for weights
    
    # Define the model
    input <- layer_input(shape = input_dim)
    
    encoded <- input |> 
      layer_dense(units = encoding_dim, activation = "sigmoid", name = "encoded",
                  kernel_regularizer = regularizer_l1(l1_penalty))
    
    decoded <- encoded |> 
      layer_dense(units = input_dim, activation = "sigmoid")
    
    mod_sparse <- keras_model(input, decoded)
    
    # Capture the hidden activations
    hidden_layer_model <- keras_model(inputs = input, outputs = mod_sparse$get_layer("encoded")$output)
    
    # Custom sparsity loss: KL divergence between rho and average activation
    kl_sparsity_loss <- function(rho_hat) {
      #k <- backend()
      rho_tensor <- rho #k$constant(rho, dtype = "float32")
      return(op_sum(rho_tensor * op_log(rho_tensor / rho_hat) +
                      (1 - rho_tensor) * op_log((1 - rho_tensor) / (1 - rho_hat))))
    }
    # Custom loss
    custom_loss <- function(y_true, y_pred) {
      #k <- backend()
      mse_loss <- op_mean(op_square(y_pred - y_true))
      
      # Compute average activation per hidden unit
      hidden_output <- hidden_layer_model(y_true)
      rho_hat <- op_mean(hidden_output, axis = 1)
      
      sparsity_loss <- kl_sparsity_loss(rho_hat)
      total_loss <- mse_loss + beta * sparsity_loss
      return(total_loss)
    }
    
    mod_sparse %>% compile(optimizer = "adam", loss = custom_loss)
    # Fit the model
    history <- mod_sparse %>% fit(
      x = X,
      y = X,
      epochs = 1000,
      batch_size = floor(nrow(X)*0.1), #32,
      validation_split = 0.2
      ,callbacks = list(callback_early_stopping(patience = 10, restore_best_weights = TRUE))
    )
    
    
    #save(mod_dae, file = paste0(filename, ".RData"))
  }else{
    mod_sparse <- get("mod_sparse")
  }
  
  X_pred <-  predict(mod_sparse,X_test)
  # Calcul de l'erreur de reconstruction (MSE)
  reconstruction_error <- rowMeans((X_test - X_pred)^2, na.rm = TRUE)
  
  # Définition d'un seuil (ex : quantile 95% des erreurs sur les normales)
  threshold <- quantile(reconstruction_error, 0.95, na.rm = TRUE)
  
  # Marquage des anomalies
  predicted_anomalies <- factor(ifelse(reconstruction_error > threshold, 1, 0), levels = levels(test_set$attacked))
  
  c(score, test_set) %<-% commun_info(test_set, predicted_anomalies, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp =  data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, c(names(score)) := score]
  # cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "unsupervised"), score)
  rm(mod_sparse)
  
  
  # Comparaison avec la vraie colonne 'attacked'
  #print(table(Predicted = predicted_anomalies, Actual = test_set$attacked))
  return (list(tmp, test_set))
}


do_ae_lstm <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  keep = setdiff(names(train_set), remove_col)#-which(names(train_set) %in% remove_col) #, "flow_size" c("attacked", "index", "packet_length")
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  # Preparation of data
  # Seperate target column
  # Calculer les min et max pour chaque colonne
  mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
  maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
  
  # X <- train_set[, ..keep][, lapply(.SD, normalize_me)] #train_set[, !names(train_set) %in% remove_col] #c("attacked", "index", "packet_length")
  X_train_tmp <- train_set[, ..keep]
  X <- X_train_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # #X_test <- test_set[, ..keep][, lapply(.SD, normalize_me)]
  X_test_tmp <- test_set[, ..keep]
  # Appliquer normalize_me à chaque colonne avec ses propres min et max
  X_test <- X_test_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # X <- as.data.frame(lapply(X, normalize_me))
  # X_test <- as.data.frame(lapply(X_test, normalize_me))
  # To matrix conversion
  X <- as.matrix(X)
  X_test <- as.matrix(X_test)
  
  if (is_charged != TRUE){
    
    TIME_STEPS <- current_param$group
    
    create_sequences <- function(values, time_steps = TIME_STEPS) {
      n <- nrow(values)
      
      output <- vector("list", n - time_steps + 1)
      for (i in seq_len(n - time_steps + 1)) {
        # Slice each sequence: [time_steps x features]
        output[[i]] <- values[i:(i + time_steps - 1), , drop = FALSE]
      }
      
      # Stack into a 3D array: [samples, time_steps, features]
      array_3d <- abind::abind(output, along = 3)  # [time_steps, features, samples]
      aperm(array_3d, c(3, 1, 2))  # Reorder to [samples, time_steps, features]
    }
    
    # Example usage:
    x_train <- create_sequences(X)
    cat("Training input shape:", paste(dim(x_train), collapse = " x "), "\n")
    # Paramètres
    time_steps <- dim(x_train)[2]
    n_features <- dim(x_train)[3]
    
    # Définition de l'autoencodeur
    input <- layer_input(shape = c(time_steps, n_features))
    
    encoded <- input %>%
      layer_lstm(units = 32, return_sequences = FALSE)
    
    decoded <- encoded %>%
      layer_repeat_vector(time_steps) %>%
      layer_lstm(units = n_features, return_sequences = TRUE)
    
    lstm_ae <- keras_model(input, decoded)
    
    lstm_ae %>% compile(
      loss = "mse",
      optimizer = "adam"
    )
    
    # Entraînement
    lstm_ae %>% fit(
      x_train, x_train,
      epochs = 1000,
      batch_size = 32,
      shuffle = T,
      validation_split = 0.2,
      verbose = 1,
      callbacks = list(callback_early_stopping(patience = 10, restore_best_weights = TRUE))
    )
    
    
    
    #save(lstm_ae, file = paste0(filename, ".RData"))
  }else{
    lstm_ae <- get("lstm_ae")
  }
  
  x_test <- create_sequences(X_test)
  X_pred <- predict(lstm_ae, x_test)
  
  # Fonction d’erreur de reconstruction MSE (par séquence)
  reconstruction_errors <- apply(
    (x_test - X_pred)^2,
    MARGIN = 1,
    FUN = function(x) mean(x)
  )
  
  # Vous pouvez fixer un seuil manuellement, ou utiliser une règle statistique
  threshold <- mean(reconstruction_errors) + 3 * sd(reconstruction_errors)
  threshold <- quantile(reconstruction_errors, 0.90, na.rm = TRUE)
  
  # Marquez les anomalies
  anomalies <- reconstruction_errors > threshold
  anomalies <- factor(ifelse(reconstruction_errors > threshold, 1, 0), levels = levels(train_set$attacked))
  
  dt <- data.table(attacked = test_set[["attacked"]])
  x_test_attacked <- create_sequences(dt)
  x_test_att_2D <- x_test_attacked[ , , 1]
  
  get_majority <- function(x) {
    tab <- table(x)
    if (length(tab) == 2 && tab[1] == tab[2]) {
      return(1)
    } else {
      return(as.numeric(names(tab)[which.max(tab)]))
    }
  }
  #attacked_vec <- as.numeric(x_test_att_2D)
  
  attacked_seq_labels <- sapply(seq_len(dim(x_test_att_2D)[1]), function(i) {
    get_majority(x_test_att_2D[i,])
  })
  
  lim_label = length(attacked_seq_labels)
  
  dt <- data.table(attacked = factor(attacked_seq_labels, levels = levels(test_set$attacked)),
                   #t_start = x_test[,TIME_STEPS,"t_start"],
                   x_test[,TIME_STEPS,]
                   #apply(x_test, MARGIN = c(1,3), FUN = function(x) mean(x)) [1:lim_label,]
  )#[,TIME_STEPS,])
  dt$fmean_delay <- apply(x_test[,,"delay"], MARGIN = 1, FUN = mean)
  
  #dt <- data.table(attacked = factor(as.numeric(apply(x_test_att_2D, 1, unique)), levels = levels(test_set$attacked)))
  
  c(score, test_set) %<-% commun_info(dt, anomalies, filename) #[1:lim_label]
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp =  data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, c(names(score)) := score]
  # cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "unsupervised"), score)
  rm(lstm_ae)
  
  
  # Comparaison avec la vraie colonne 'attacked'
  #print(table(Predicted = predicted_anomalies, Actual = test_set$attacked))
  return (list(tmp, test_set))
}



do_ae_conv1d <- function(train_set, test_set, current_param)
{
  set.seed(1997)
  nb_hops = current_param$nb_hops
  nb_att = current_param$nb_att
  keep = setdiff(names(train_set), remove_col)#-which(names(train_set) %in% remove_col) #, "flow_size" c("attacked", "index", "packet_length")
  c(is_charged, filename) %<-% is_charge_before(current_param)
  
  # Preparation of data
  # Seperate target column
  # Calculer les min et max pour chaque colonne
  mins <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, min, na.rm = TRUE)]
  maxs <- rbindlist(list(train_set, test_set))[, ..keep][, lapply(.SD, max, na.rm = TRUE)]
  
  # X <- train_set[, ..keep][, lapply(.SD, normalize_me)] #train_set[, !names(train_set) %in% remove_col] #c("attacked", "index", "packet_length")
  X_train_tmp <- train_set[, ..keep]
  X <- X_train_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # #X_test <- test_set[, ..keep][, lapply(.SD, normalize_me)]
  X_test_tmp <- test_set[, ..keep]
  # Appliquer normalize_me à chaque colonne avec ses propres min et max
  X_test <- X_test_tmp[, Map(function(col, minv, maxv) {
    normalize_me(col, min_val = minv, max_val = maxv)
  }, .SD, mins, maxs)]
  
  # X <- as.data.frame(lapply(X, normalize_me))
  # X_test <- as.data.frame(lapply(X_test, normalize_me))
  # To matrix conversion
  X <- as.matrix(X)
  X_test <- as.matrix(X_test)
  
  if (is_charged != TRUE){
    
    TIME_STEPS <- current_param$group
    
    create_sequences <- function(values, time_steps = TIME_STEPS) {
      n <- nrow(values)
      
      output <- vector("list", n - time_steps + 1)
      for (i in seq_len(n - time_steps + 1)) {
        # Slice each sequence: [time_steps x features]
        output[[i]] <- values[i:(i + time_steps - 1), , drop = FALSE]
      }
      
      # Stack into a 3D array: [samples, time_steps, features]
      array_3d <- abind::abind(output, along = 3)  # [time_steps, features, samples]
      aperm(array_3d, c(3, 1, 2))  # Reorder to [samples, time_steps, features]
    }
    
    # Example usage:
    x_train <- create_sequences(X)
    cat("Training input shape:", paste(dim(x_train), collapse = " x "), "\n")
    # Paramètres
    latent_dim <- 16
    intermediate_dim <- 32
    time_steps <- dim(x_train)[2]
    n_features <- dim(x_train)[3]
    
    # model definition
    ## encoder
    input_layer <- layer_input(shape = c(time_steps, n_features))# input_dim)
    x <- layer_conv_1d(input_layer, filters=intermediate_dim, kernel_size=7, padding="same", strides=2, activation="relu")
    x <- layer_dropout(x, rate = 0.2)
    z <- layer_conv_1d(x, filters=latent_dim, kernel_size=7, padding="same", strides=2, activation="relu")
    encoder <- keras_model(input_layer, z, name="encoder")
    
    ## decoder
    x <- layer_conv_1d_transpose(z, filters=latent_dim, kernel_size=7, padding="same", strides=2, activation="relu")
    x <- layer_dropout(x, rate = 0.2)
    x <- layer_conv_1d_transpose(x, filters=intermediate_dim, kernel_size=7, padding="same", strides=2, activation="relu")
    x <- layer_conv_1d_transpose(x, filters=n_features, kernel_size=7, padding="same")
    
    
    # ===== FIX LENGTH MISMATCH =====
    # Lambda layer to match decoder output length to encoder input length
    options(tensorflow.extract.one_based = FALSE)
    match_length <- function(inputs) {
      original <- inputs[[1]]
      reconstructed <- inputs[[2]]
      
      orig_len <- tf$shape(original)[[2]]
      rec_len  <- tf$shape(reconstructed)[[2]]
      diff     <- orig_len - rec_len
      
      reconstructed <- tf$cond(
        diff > 0L,
        function() tf$pad(reconstructed, list(c(0L, 0L), c(0L, diff), c(0L, 0L))),
        function() tf$slice(
          reconstructed,
          begin = c(0L, 0L, 0L),
          size  = c(-1L, time_steps, -1L) #orig_len
        )
      )
      reconstructed
    }
    
    output_layer <- layer_lambda(f = match_length,
                                 output_shape = c(time_steps, n_features)   # explicitly define output shape
    )(list(input_layer, x))
    
    
    mod_ts_conv <- keras_model(input_layer, output_layer, name="mod_ts_conv")
    
    
    # Model compilation
    mod_ts_conv %>% compile(
      loss = "mse",
      optimizer = optimizer_adam(learning_rate = 0.001)
    )
    # Model training
    history <- mod_ts_conv %>% fit(
      x= x_train, y= x_train,  # Entrée = Sortie (car autoencodeur)
      epochs = 1000, #440,
      batch_size = floor(nrow(X)*0.1),
      shuffle = T,
      validation_split = 0.2,
      verbose = 1,
      callbacks = list(callback_early_stopping(patience = 10, restore_best_weights = TRUE))
    )
    
    
    
    
    #save(mod_ts_conv, file = paste0(filename, ".RData"))
  }else{
    mod_ts_conv <- get("mod_ts_conv")
  }
  
  x_test <- create_sequences(X_test)
  X_pred <- predict(mod_ts_conv, x_test)
  
  # Fonction d’erreur de reconstruction MSE (par séquence)
  reconstruction_errors <- apply(
    (x_test - X_pred)^2,
    MARGIN = 1,
    FUN = function(x) mean(x)
  )
  
  # Vous pouvez fixer un seuil manuellement, ou utiliser une règle statistique
  threshold <- mean(reconstruction_errors) + 3 * sd(reconstruction_errors)
  threshold <- quantile(reconstruction_errors, 0.95, na.rm = TRUE)
  
  # Marquez les anomalies
  anomalies <- reconstruction_errors > threshold
  anomalies <- factor(ifelse(reconstruction_errors > threshold, 1, 0), levels = levels(train_set$attacked))
  
  dt <- data.table(attacked = test_set[["attacked"]])
  x_test_attacked <- create_sequences(dt)
  x_test_att_2D <- x_test_attacked[ , , 1]
  
  get_majority <- function(x) {
    tab <- table(x)
    if (length(tab) == 2 && tab[1] == tab[2]) {
      return(1)
    } else {
      return(as.numeric(names(tab)[which.max(tab)]))
    }
  }
  #attacked_vec <- as.numeric(x_test_att_2D)
  
  attacked_seq_labels <- sapply(seq_len(dim(x_test_att_2D)[1]), function(i) {
    get_majority(x_test_att_2D[i,])
  })
  
  dt <- data.table(attacked = factor(attacked_seq_labels, levels = levels(test_set$attacked)),
                   #t_start = x_test[,TIME_STEPS,"t_start"],
                   x_test[,TIME_STEPS,])
  dt$fmean_delay <- apply(x_test[,,"delay"], MARGIN = 1, FUN = mean)
  
  #dt <- data.table(attacked = factor(as.numeric(apply(x_test_att_2D, 1, unique)), levels = levels(test_set$attacked)))
  
  c(score, test_set) %<-% commun_info(dt, anomalies, filename)
  print(paste0("F1 score ",current_param$model, ": ",score$F1_score))
  tmp =  data.table(
    path_length = nb_hops,
    nb_detour = nb_att,
    model = current_param$model,
    approach = "unsupervised"
  )[, c(names(score)) := score]
  # cbind(data.frame(path_length = nb_hops, nb_detour = nb_att, 
  #                         model = current_param$model, 
  #                         approach = "unsupervised"), score)
  rm(mod_ts_conv)
  
  
  # Comparaison avec la vraie colonne 'attacked'
  #print(table(Predicted = predicted_anomalies, Actual = test_set$attacked))
  return (list(tmp, test_set))
}
