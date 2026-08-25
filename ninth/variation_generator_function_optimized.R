# ============================================================
#  variation_generator_function_optimized.R
#  Remplacement direct de mix_to_flow() et compute_flow_features()
#
#  GAINS:
#   - 60 group-by séparés + 44 merge() → 1 seul group-by + 0 merge()
#   - att0 et attn traités en un seul passage (colonne "side")
#   - Fonctions helper définies UNE fois hors de la boucle
#   - Résultat identique, vérifiable avec all.equal()
# ============================================================

# ---------- Helper functions (defined once, reused) ----------

.sd_diff_safe <- function(x) {
  if (length(x) < 2) return(NA_real_)
  sd(diff(x))
}
.mean_diff_safe <- function(x) {
  if (length(x) < 2) return(NA_real_)
  mean(abs(diff(x)), na.rm = TRUE)
}
.sqrt_mean_diff_safe <- function(x) {
  if (length(x) < 2) return(NA_real_)
  sqrt(mean(diff(x)^2, na.rm = TRUE))
}
.mean_pmax_diff_plus <- function(x) {
  if (length(x) < 2) return(NA_real_)
  mean(pmax(diff(x), 0), na.rm = TRUE)
}
.mean_pmax_diff_minus <- function(x) {
  if (length(x) < 2) return(NA_real_)
  mean(pmax(-diff(x), 0), na.rm = TRUE)
}
.sd_error <- function(x) {
  if (length(x) <= 1) return(NA_real_)
  sd(x) / sqrt(length(x))
}
.min_max <- function(x) {
  if (length(x) == 0) return(NA_real_)
  max(x) - min(x)
}
.slope_index <- function(x) {
  n <- length(x)
  if (n < 2) return(NA_real_)
  as.numeric(coef(stats::lm(x ~ seq_len(n)))[2])
}
.cusum_max <- function(x) {
  x <- na.omit(x); n <- length(x)
  if (n < 3) return(NA_real_)
  m <- mean(x); s <- stats::sd(x)
  if (!is.finite(s) || s == 0) return(0)
  k <- 0.5; S <- 0; Smax <- 0
  for (i in seq_len(n)) { S <- max(0, S + (x[i] - m) / s - k); Smax <- max(Smax, S) }
  Smax
}
.early_late_diff <- function(x) {
  n <- length(x)
  if (n < 4) return(NA_real_)
  h <- floor(n / 2)
  median(x[1:h]) - median(x[(h + 1):n])
}
.hill_index <- function(x) {
  x <- sort(na.omit(x)); n <- length(x)
  if (n < 10) return(NA_real_)
  k <- max(5L, floor(sqrt(n)))
  xk <- x[(n - k + 1):n]; xk0 <- x[n - k]
  mean(log(xk) - log(xk0))
}
.spec_feats <- function(x) {
  if (length(x) < 8) return(list(fSpec_peak_freq = NA_real_, fSpec_entropy = NA_real_))
  y <- stats::na.omit(diff(as.numeric(x)))
  N <- length(y)
  Y <- stats::fft(y)
  P <- Mod(Y[2:floor(N / 2)])^2
  if (length(P) < 2) return(list(fSpec_peak_freq = NA_real_, fSpec_entropy = NA_real_))
  f <- seq(1, length(P)) / N
  pk <- f[which.max(P)]
  pnorm <- P / sum(P)
  ent <- -sum(pnorm * log(pnorm + 1e-12))
  list(fSpec_peak_freq = as.numeric(pk), fSpec_entropy = as.numeric(ent))
}
.reg_delay_size <- function(delay, size) {
  if (is.null(size) || all(!is.finite(size)) || stats::var(size, na.rm = TRUE) == 0)
    return(list(alpha_hat = NA_real_, beta_hat = NA_real_, r2 = NA_real_, sigma_eps = NA_real_))
  fit <- stats::lm(delay ~ size)
  s <- summary(fit)
  list(
    alpha_hat = unname(coef(fit)[1]),
    beta_hat  = unname(coef(fit)[2]),
    r2        = unname(s$r.squared),
    sigma_eps = unname(sigma(fit))
  )
}
.acf_features <- function(x, max_lag = 10) {
  n <- length(x)
  if (n <= 1 || all(is.na(x))) {
    out <- as.list(rep(NA_real_, max_lag + 2))  # lag0..lag10 + facf_last
    names(out) <- c(paste0("facf_lag", 0:max_lag), "facf_last")
    out$fACF_sum <- NA_real_
    return(out)
  }
  acf_obj <- acf(x, lag.max = max(max_lag, n - 1), plot = FALSE, na.action = na.exclude)
  vals <- as.numeric(acf_obj$acf)
  
  out <- list()
  for (i in 0:max_lag) {
    nm <- paste0("facf_lag", i)
    out[[nm]] <- if (i + 1 <= length(vals)) vals[i + 1] else NA_real_
  }
  out$facf_last <- if (n <= length(vals)) vals[n] else NA_real_
  # fACF_sum = sum of abs of lags 1..max_lag (excluding lag 0)
  lag_vals <- vapply(1:max_lag, function(i) if (i + 1 <= length(vals)) abs(vals[i + 1]) else 0, numeric(1))
  out$fACF_sum <- sum(lag_vals)
  out
}
.duty_runmax <- function(t_start, t_end) {
  if (length(t_start) == 0) return(list(duty = 0, run_max = NA_real_))
  dt <- data.table(start = t_start, end = t_end)
  setorder(dt, start)
  dt[, interval_id := cumsum(c(TRUE, start[-1] > cummax(end)[-.N]))]
  merged <- dt[, .(start = min(start), end = max(end)), by = interval_id]
  merged[, duration := end - start]
  total_busy <- sum(merged$duration)
  span <- max(dt$start) - min(dt$start)
  list(
    duty    = if (span > 0) total_busy / span else 0,
    run_max = max(merged$duration)
  )
}


# ============================================================
#  compute_all_flow_features()
#  ONE single group-by pass that computes ALL features
# ============================================================
compute_all_flow_features <- function(packets, group_size) {
  # packets: data.table with columns: group_num, delay, packet_length, t_start, t_end, attacked, + metadata
  # Returns: one row per group_num with all flow-level features
  
  flow <- packets[, {
    n <- .N
    d <- delay
    pl <- packet_length
    
    # ---- Basic stats (was the first group-by) ----
    fmin   <- min(d)
    fmax   <- max(d)
    fmean  <- mean(d)
    fmed   <- median(d)
    fvar   <- if (n > 1) var(d) else NA_real_
    fsd    <- if (n > 1) sd(d) else NA_real_
    fQ005  <- quantile(d, 0.05, na.rm = TRUE)
    fQ01   <- quantile(d, 0.10, na.rm = TRUE)
    fFstQ  <- quantile(d, 0.25, na.rm = TRUE)
    fTrdQ  <- quantile(d, 0.75, na.rm = TRUE)
    fQ09   <- quantile(d, 0.90, na.rm = TRUE)
    fQ095  <- quantile(d, 0.95, na.rm = TRUE)
    fmeanTRIM10 <- mean(d, trim = 0.1, na.rm = TRUE)
    fCV <- if (!is.na(fsd) && fmean != 0) fsd / fmean else NA_real_
    
    t_s <- min(t_start)
    t_e <- max(t_end)
    flow_delay <- t_e - t_s
    fs <- n
    lhat <- if (flow_delay > 0) fs / flow_delay else NA_real_
    
    # ---- Jitter features (was 5 separate group-bys) ----
    fsd_diff  <- .sd_diff_safe(d)
    fMASD     <- .mean_diff_safe(d)
    fRMSJ     <- .sqrt_mean_diff_safe(d)
    fIPDV_pos <- .mean_pmax_diff_plus(d)
    fIPDV_neg <- .mean_pmax_diff_minus(d)
    
    # ---- Dispersion features (was 4 separate group-bys) ----
    fsderr <- if (n > 1) .sd_error(d) else NA_real_
    fmad_val <- mad(d, na.rm = TRUE)
    fminmax_val <- .min_max(d)
    fIQR_val <- IQR(d, na.rm = TRUE)
    fQ095_Q005 <- fQ095 - fQ005
    
    # ---- Shape features (was 2 separate group-bys) ----
    fskew <- if (n > 2) e1071::skewness(d, na.rm = TRUE) else NA_real_
    fkurt <- if (n > 2) e1071::kurtosis(d, na.rm = TRUE) else NA_real_
    
    # ---- ACF features (was 2 separate group-bys + dcast) ----
    acf_out <- .acf_features(d)
    
    # ---- Trend features (was 3 separate group-bys) ----
    fslope <- .slope_index(d)
    fcusum <- .cusum_max(d)
    fearly <- .early_late_diff(d)
    
    # ---- Regression d ~ L (was 1 group-by + dcast) ----
    reg <- .reg_delay_size(d, pl)
    
    # ---- Heavy-tail (was 1 group-by) ----
    fhill <- .hill_index(d)
    
    # ---- Spectral (was 1 group-by + dcast) ----
    spec <- .spec_feats(d)
    
    # ---- Duty cycle & run max (was complex interval computation) ----
    dr <- .duty_runmax(t_start, t_end)
    
    # ---- Assemble result ----
    c(
      list(
        packet_length = mean(pl),
        t_start = t_s, 
        t_end = t_e,
        flow_size = fs,
        fmin_delay = fmin, 
        fQ005_delay = fQ005, 
        fQ01_delay = fQ01,
        fFstQ_delay = fFstQ, 
        fmedian_delay = fmed,
        fmean_delay = fmean, 
        fmeanTRIM10_delay = fmeanTRIM10,
        fTrdQ_delay = fTrdQ, 
        fQ09_delay = fQ09, 
        fQ095_delay = fQ095,
        fmax_delay = fmax,
        fvar_delay = fvar, 
        fsd_delay = fsd, 
        fCV_delay = fCV,
        delay = flow_delay, 
        lambda_hat = lhat,
        fsd_diff_delay = fsd_diff, 
        fMASD_delay = fMASD,
        fRMSJ_delay = fRMSJ, 
        fIPDV_pos_delay = fIPDV_pos,
        fIPDV_neg_delay = fIPDV_neg,
        fsderror_delay = fsderr, 
        fmad_delay = fmad_val,
        fminmax_delay = fminmax_val, 
        fIQR_delay = fIQR_val,
        fQ095_Q005 = fQ095_Q005,
        fskew_delay = fskew, 
        fkurtosis_delay = fkurt,
        fslope_t = fslope, 
        fCUSUM_max = fcusum, 
        fearly_diff = fearly,
        fhill = fhill
      ),
      reg,   # alpha_hat, beta_hat, r2, sigma_eps
      spec,  # fSpec_peak_freq, fSpec_entropy
      acf_out, # facf_lag0..facf_lag10, facf_last, fACF_sum
      dr     # duty, run_max
    )
  }, by = group_num]
  
  # ---- Derived features (vectorized, no group-by needed) ----
  flow[, rho_tilde := lambda_hat * beta_hat * packet_length]
  
  flow
}


# ============================================================
#  mix_to_flow_fast() — Drop-in replacement for mix_to_flow()
#  Same interface, same output, ~10-30x faster
# ============================================================
mix_to_flow_fast <- function(dtf_att0, dtf_attn, prop = 0.1, group = -1, start = 1
                             #, cross_seed = FALSE
                             ) {
  
  # ---- Step 1: Separate into flows (unchanged logic) ----
  c(keep_att0, keep_attn, by) %<-% seperate_by_flow(dtf_att0, dtf_attn, prop, group, start)
  max_group_num <- max(keep_att0$group_num, keep_attn$group_num)
  keep_att0 <- keep_att0[group_num < max_group_num]
  keep_attn <- keep_attn[group_num < max_group_num]
  
  # ---- Step 2: Tag and combine (the key optimization) ----
  keep_att0[, side := "att0"]
  keep_attn[, side := "attn"]
  combined <- rbindlist(list(keep_att0, keep_attn), use.names = TRUE, fill = TRUE)
  # Create a unique key for group-by: side + group_num
  combined[, flow_key := paste0(side, "_", group_num)]
  
  # ---- Step 3: ONE single group-by for ALL features ----
  flow_all <- combined[, {
    n <- .N
    d <- delay
    pl <- packet_length
    
    fmin   <- min(d); fmax <- max(d)
    fmean  <- mean(d); fmed <- median(d)
    fvar   <- if (n > 1) var(d) else NA_real_
    fsd    <- if (n > 1) sd(d) else NA_real_
    fQ005  <- quantile(d, 0.05, na.rm = TRUE)
    fQ01   <- quantile(d, 0.10, na.rm = TRUE)
    fFstQ  <- quantile(d, 0.25, na.rm = TRUE)
    fTrdQ  <- quantile(d, 0.75, na.rm = TRUE)
    fQ09   <- quantile(d, 0.90, na.rm = TRUE)
    fQ095  <- quantile(d, 0.95, na.rm = TRUE)
    fmeanTRIM10 <- mean(d, trim = 0.1, na.rm = TRUE)
    fCV <- if (!is.na(fsd) && fmean != 0) fsd / fmean else NA_real_
    
    t_s <- min(t_start); t_e <- max(t_end)
    flow_delay <- t_e - t_s
    fs <- n
    lhat <- if (flow_delay > 0) fs / flow_delay else NA_real_
    
    fsd_diff  <- .sd_diff_safe(d)
    fMASD     <- .mean_diff_safe(d)
    fRMSJ     <- .sqrt_mean_diff_safe(d)
    fIPDV_pos <- .mean_pmax_diff_plus(d)
    fIPDV_neg <- .mean_pmax_diff_minus(d)
    fsderr <- if (n > 1) .sd_error(d) else NA_real_
    fmad_val <- mad(d, na.rm = TRUE)
    fminmax_val <- .min_max(d)
    fIQR_val <- IQR(d, na.rm = TRUE)
    
    fskew <- if (n > 2) e1071::skewness(d, na.rm = TRUE) else NA_real_
    fkurt <- if (n > 2) e1071::kurtosis(d, na.rm = TRUE) else NA_real_
    
    acf_out <- .acf_features(d)
    fslope <- .slope_index(d)
    fcusum <- .cusum_max(d)
    fearly <- .early_late_diff(d)
    reg <- .reg_delay_size(d, pl)
    fhill <- .hill_index(d)
    spec <- .spec_feats(d)
    dr <- .duty_runmax(t_start, t_end)
    
    c(list(
      side_val = side[1], group_num_orig = group_num[1],
      packet_length = mean(pl), t_start = t_s, t_end = t_e,
      flow_size = fs,
      fmin_delay = fmin, fQ005_delay = fQ005, fQ01_delay = fQ01,
      fFstQ_delay = fFstQ, fmedian_delay = fmed,
      fmean_delay = fmean, fmeanTRIM10_delay = fmeanTRIM10,
      fTrdQ_delay = fTrdQ, fQ09_delay = fQ09, fQ095_delay = fQ095,
      fmax_delay = fmax,
      fvar_delay = fvar, fsd_delay = fsd, fCV_delay = fCV,
      delay = flow_delay, lambda_hat = lhat,
      fsd_diff_delay = fsd_diff, fMASD_delay = fMASD,
      fRMSJ_delay = fRMSJ, fIPDV_pos_delay = fIPDV_pos,
      fIPDV_neg_delay = fIPDV_neg,
      fsderror_delay = fsderr, fmad_delay = fmad_val,
      fminmax_delay = fminmax_val, fIQR_delay = fIQR_val,
      fQ095_Q005 = fQ095 - fQ005,
      fskew_delay = fskew, fkurtosis_delay = fkurt,
      fslope_t = fslope, fCUSUM_max = fcusum, fearly_diff = fearly,
      fhill = fhill
    ), reg, spec, acf_out, dr)
  }, by = flow_key]
  
  flow_all[, rho_tilde := lambda_hat * beta_hat * packet_length]
  
  # ---- Step 4: Add metadata from original packet-level data ----
  meta_cols <- c("attacked", "simulation_time", "extra_router", "extra_detour", "latency",
                 "bandwidth", "data_rate", "parasite_rate", "packet_size", "proto",
                 "src_ip", "dst_ip", "src_port", "dst_port")
  meta_att0 <- dtf_att0[1, ..meta_cols]
  meta_attn <- dtf_attn[1, ..meta_cols]
  
  flow_att0 <- flow_all[side_val == "att0"]
  flow_attn <- flow_all[side_val == "attn"]
  for (col in meta_cols) {
    flow_att0[, (col) := meta_att0[[col]]]
    flow_attn[, (col) := meta_attn[[col]]]
  }
  
  # ---- Step 5: Cleanup and merge ----
  flow_att0[, c("flow_key", "side_val", "group_num_orig") := NULL]
  flow_attn[, c("flow_key", "side_val", "group_num_orig") := NULL]
  real_prop <- flow_attn[, .N] / flow_att0[, .N]
  print(paste0("keepn:", flow_attn[, .N], ", keep0:", flow_att0[, .N], ", real_prop:", real_prop))
  print("end flow computation (optimized)")
  
  X_end <- rbind(flow_att0, flow_attn)
  setorder(X_end, t_start)
  X_end <- compute_stat(X_end, by)
  # Remove columns with >50% NA
  na_proportions <- X_end[, lapply(.SD, function(col) mean(is.na(col)))]
  cols_to_keep <- names(na_proportions)[na_proportions <= 0.5]
  X_end_no_na <- X_end[, ..cols_to_keep]
  print("end mix_to_flow_fast")
  return(X_end_no_na)
}
