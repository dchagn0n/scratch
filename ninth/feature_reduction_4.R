# ============================================================
#  feature_reduction.R  —  Instruction E : reduction du jeu de variables
#
#  PRINCIPE
#  --------
#  Ce script ne recalcule RIEN. Il se branche sur le cache produit par
#  feature_analysis_section32.R (fichier `cache/collected_data.rds`,
#  et si present `cache/families.rds`), puis :
#
#    1. construit le pool de variables candidates (toutes les colonnes
#       numeriques de all_flows, moins les colonnes de metadonnees) ;
#    2. calcule la matrice de correlation de Spearman et le
#       dendrogramme (meme distance 1 - |rho| qu'en section 3.2) ;
#    3. calcule l'AUC univariee symetrique de chaque variable ;
#    4. pour chaque k, coupe le dendrogramme et retient un representant
#       par groupe : la variable dont l'AUC est la plus eloignee de 0,5 ;
#    5. ecrit reduced_features_k<k>.rds, consommable par setup_param.R.
#
#  DIFFERENCES ASSUMEES AVEC LE SNIPPET DE L'INSTRUCTION E
#  -------------------------------------------------------
#   - `dtf_feat` n'existe pas dans feature_analysis_section32.R : l'objet
#     reel est `all_flows`. Le snippet ne pouvait pas s'executer.
#   - Le pool n'est PAS restreint a `avail_feats` (44 variables du
#     catalogue de la section 3.2). Il couvre toutes les colonnes
#     numeriques, sans quoi les variables presentes dans les listes des
#     modeles mais absentes du catalogue (facf_lag3..facf_lag10,
#     fQ095_Q005, duty, run_max...) seraient supprimees par
#     `intersect(model_features, reduced_feature_set)` sans que ce soit
#     une decision de redondance. Voir le diagnostic COUVERTURE ci-dessous.
#   - Les variables a taux de NA eleve (fhill est structurellement
#     indefini a n = 9) sont ecartees AVANT le calcul de la matrice de
#     correlation. Sans cela `hclust()` echoue sur des NA.
#   - Le linkage est parametrable et vaut ward.D2 par defaut, pour rester
#     coherent avec le dendrogramme de l'annexe feature_redundancy.tex.
#
#  MISE EN GARDE METHODOLOGIQUE (a citer dans le manuscrit)
#  -------------------------------------------------------
#  La selection utilise les etiquettes `attacked` de la totalite du jeu
#  charge. Si le meme jeu sert ensuite a evaluer les modeles, il y a
#  fuite de selection et les F1 obtenus avec le jeu reduit sont
#  optimistes. Protocole recommande : calculer la reduction sur UNE
#  execution (une graine) et evaluer les modeles sur les autres.
#
#  USAGE
#  -----
#    Rscript feature_reduction.R \
#            --cacheDir feature_analysis_output/<scenario_tag> \
#            --k 8,12,15 \
#            --outDir ./scratch/ninth/feature_reduction
#
#  Si --cacheDir est omis, le repertoire d'analyse le plus recent
#  contenant un cache exploitable est choisi automatiquement.
# ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(optparse)
  library(pROC)
  library(cluster)
})

# ------------------------------------------------------------
#  0. Arguments
# ------------------------------------------------------------
option_list <- list(
  make_option("--cacheDir", type = "character", default = "",
              help = "Repertoire d'analyse (ou son sous-repertoire cache/) produit par feature_analysis_section32.R. Vide = detection automatique."),
  make_option("--anaRoot", type = "character", default = "./feature_analysis_output",
              help = "Racine exploree en detection automatique [defaut: %default]"),
  make_option("--outDir", type = "character", default = "./scratch/ninth/feature_reduction",
              help = "Repertoire de sortie [defaut: %default]"),
  make_option("--k", type = "character", default = "auto,8,12,15",
              help = "Nombres de groupes a tester, separes par des virgules. Le jeton 'auto' ajoute le k maximisant la silhouette moyenne sur le pool effectivement utilise ; c'est ce k qui est designe comme coupe retenue [defaut: %default]"),
  make_option("--kMin", type = "integer", default = 3L,
              help = "Borne inferieure du balayage de silhouette [defaut: %default]"),
  make_option("--kMax", type = "integer", default = 30L,
              help = "Borne superieure du balayage de silhouette [defaut: %default]"),
  make_option("--linkage", type = "character", default = "ward.D2",
              help = "Methode d'agregation hierarchique : ward.D2 (coherent avec la section 3.2) ou average [defaut: %default]"),
  make_option("--minFinite", type = "double", default = 0.80,
              help = "Fraction minimale de valeurs finies pour qu'une variable entre dans le pool [defaut: %default]"),
  make_option("--poolFile", type = "character", default = "",
              help = "Fichier texte (un nom de variable par ligne) restreignant le pool candidat. Vide = toutes les colonnes numeriques. Utiliser p.ex. la liste des 44 variables du catalogue de la section 3.2 pour rester strictement coherent avec le dendrogramme de l'annexe."),
  make_option("--calibFrac", type = "double", default = 0.70,
              help = "Fraction temporelle initiale de chaque scenario utilisee pour calculer les AUC de selection. 0.70 = meme fenetre que le train de partition(), ce qui evite de selectionner sur les flux de test. 1 = selection sur la totalite [defaut: %default]"),
  make_option("--preview", type = "logical", default = TRUE,
              help = "Apercu multivarie : AUC en validation croisee 5 blocs d'une regression logistique, jeu complet vs jeux reduits [defaut: %default]"),
  make_option("--figFormat", type = "character", default = "pdf",
              help = "Format des dendrogrammes : pdf, png ou both [defaut: %default]"),
  make_option("--dropTemporal", type = "logical", default = TRUE,
              help = "Exclure t_start et t_end du pool (coherent avec l'instruction C) [defaut: %default]"),
  make_option("--minRepAUC", type = "double", default = 0,
              help = "AUC symetrique minimale exigee d'un representant. Une variable qui ne correlle avec rien forme un groupe singleton parfait et se voit attribuer une place quel que soit son pouvoir discriminant : facf_lag0 (0.513), fSpec_peak_freq (0.519) et t_start (0.539) occupent ainsi trois des onze places de la coupe retenue. 0 = aucun filtre (comportement historique) ; 0.55 ecarte ces representants non informatifs [defaut: %default]"),
  make_option("--repScope", type = "character", default = "per_model",
              help = "Choix des representants. 'global' : un representant par groupe, le meilleur toutes listes confondues -- un groupe dont le representant n'appartient pas a la liste d'un modele devient ALORS totalement absent pour ce modele, meme s'il contenait quinze de ses variables. 'per_model' : un representant par groupe ET par modele, puis union -- chaque modele recoit un representant de chacun de ses groupes [defaut: %default]"),
  make_option("--dropLabelDependent", type = "logical", default = TRUE,
              help = "Ecarter du pool les variables dont la definition depend des etiquettes (d_alpha, d_masd, d_cv, d_beta : ecart a une mediane calculee sur les flux benins). Leur valeur dans le cache d'analyse n'est pas celle que les modeles voient, et leur AUC hors ligne est optimiste. Ne passer a FALSE qu'apres avoir rendu leur calcul etanche des deux cotes [defaut: %default]"),
  make_option("--modelFile", type = "character", default = "./scratch/ninth/model_function.R",
              help = "model_function.R, lu en lecture seule pour le diagnostic de couverture. Vide = diagnostic desactive."),
  make_option("--setupParam", type = "character", default = "",
              help = "setup_param.R, source uniquement pour recuperer remove_col. Vide = ignore.")
)
opt <- parse_args(OptionParser(option_list = option_list))

k_tokens  <- trimws(strsplit(opt$k, ",")[[1]])
auto_k    <- any(tolower(k_tokens) == "auto")
ks_fixed  <- suppressWarnings(as.integer(k_tokens[tolower(k_tokens) != "auto"]))
ks_fixed  <- sort(unique(ks_fixed[!is.na(ks_fixed) & ks_fixed >= 2L]))
if (length(ks_fixed) == 0L && !auto_k)
  stop("[ERROR] --k ne contient aucune valeur valide.")
if (opt$kMin < 2L) opt$kMin <- 2L
if (opt$kMax <= opt$kMin) stop("[ERROR] --kMax doit etre superieur a --kMin.")
# Plafond utilise par les gardes tant que le k optimal n'est pas encore connu
k_ceiling <- max(c(ks_fixed, if (auto_k) opt$kMax else 0L))
ks        <- ks_fixed

dir.create(opt$outDir, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
#  Suffixe de traçabilite
#  Deux executions qui ne different que par --minRepAUC produiraient des
#  fichiers de meme nom, donc un meme `feature_set` dans les resultats du
#  pipeline et deux campagnes indiscernables. Le seuil est donc inscrit dans
#  le nom de chaque sortie.
# ------------------------------------------------------------
TAG <- if (opt$minRepAUC > 0)
  sprintf("_minauc%03d", round(opt$minRepAUC * 1000)) else ""
out_file <- function(...) file.path(opt$outDir, paste0(...))
if (nzchar(TAG))
  cat("[TAG] Suffixe applique aux sorties :", TAG, "\n")

# ------------------------------------------------------------
#  1. Localisation et chargement du cache
# ------------------------------------------------------------
find_cache_dir <- function(cache_dir, ana_root) {
  if (nzchar(cache_dir)) {
    p <- if (basename(cache_dir) == "cache") cache_dir else file.path(cache_dir, "cache")
    if (!file.exists(file.path(p, "collected_data.rds")))
      stop("[ERROR] collected_data.rds introuvable dans : ", p)
    return(p)
  }
  if (!dir.exists(ana_root))
    stop("[ERROR] Racine d'analyse introuvable : ", ana_root,
         "\n        Lancez d'abord feature_analysis_section32.R, ou passez --cacheDir.")
  roots <- list.dirs(ana_root, recursive = FALSE)
  cands <- file.path(roots, "cache", "collected_data.rds")
  cands <- cands[file.exists(cands)]
  if (length(cands) == 0L)
    stop("[ERROR] Aucun cache collected_data.rds sous ", ana_root)
  chosen <- cands[which.max(file.info(cands)$mtime)]
  cat("[AUTO] Cache retenu (le plus recent) :", dirname(chosen), "\n")
  dirname(chosen)
}

CACHE_DIR <- find_cache_dir(opt$cacheDir, opt$anaRoot)
cat("[INFO] Cache          :", CACHE_DIR, "\n")

data_cache <- readRDS(file.path(CACHE_DIR, "collected_data.rds"))
all_flows  <- data.table::as.data.table(data_cache$all_flows)
rm(data_cache); invisible(gc())
cat("[INFO] Flux charges   :", nrow(all_flows), "lignes,",
    ncol(all_flows), "colonnes\n")

if (!"attacked" %in% names(all_flows))
  stop("[ERROR] Colonne `attacked` absente de all_flows.")

y <- suppressWarnings(as.integer(as.character(all_flows$attacked)))
if (any(is.na(y)))
  stop("[ERROR] `attacked` n'est pas convertible en 0/1.")
cat("[INFO] Prevalence     :", round(mean(y), 4),
    " (", sum(y), "flux detournes /", length(y), ")\n")
if (length(unique(y)) < 2L)
  stop("[ERROR] Une seule classe presente : AUC non definie.")

# k optimal de la section 3.2, s'il a ete mis en cache
fam_path <- file.path(CACHE_DIR, "families.rds")
k_opt_32 <- NA_integer_
if (file.exists(fam_path)) {
  fam <- tryCatch(readRDS(fam_path), error = function(e) NULL)
  if (!is.null(fam) && !is.null(fam$k)) {
    k_opt_32 <- as.integer(fam$k)
    cat("[INFO] k optimal de la section 3.2 (silhouette) :", k_opt_32, "\n")
    cat("[INFO]   valeur reportee a titre de comparaison uniquement : elle a ete\n")
    cat("[INFO]   obtenue sur le catalogue de 44 variables, pas sur le pool utilise ici.\n")
  }
}

# ------------------------------------------------------------
#  1bis. Fenetre de calibration (attenuation de la fuite de selection)
#  Les AUC servant a designer les representants sont calculees sur la
#  premiere fraction temporelle de CHAQUE scenario, c'est-a-dire la meme
#  fenetre que le jeu d'entrainement de partition(). La matrice de
#  correlation, elle, n'utilise pas les etiquettes et reste calculee sur
#  la totalite des flux (estimation plus stable, aucune fuite possible).
# ------------------------------------------------------------
sc_cols <- intersect(c("sc_proto", "sc_hops", "sc_att", "sc_rate"), names(all_flows))
calib_idx <- seq_len(nrow(all_flows))
if (opt$calibFrac < 1) {
  tmp <- data.table(row = seq_len(nrow(all_flows)))
  if (length(sc_cols)) tmp <- cbind(tmp, all_flows[, ..sc_cols])
  tmp[, ord := if ("t_start" %in% names(all_flows))
    suppressWarnings(as.numeric(all_flows[["t_start"]])) else row]
  tmp[!is.finite(ord), ord := Inf]
  data.table::setorderv(tmp, c(sc_cols, "ord"))
  calib_idx <- if (length(sc_cols)) {
    sort(tmp[, .(row = row[seq_len(max(1L, floor(.N * opt$calibFrac)))]),
             by = sc_cols]$row)
  } else {
    sort(tmp$row[seq_len(max(1L, floor(nrow(tmp) * opt$calibFrac)))])
  }
  cat("[CALIB] AUC calculees sur", length(calib_idx), "/", nrow(all_flows),
      "flux (", round(100 * opt$calibFrac), "% initiaux de chaque scenario ),",
      "prevalence =", round(mean(y[calib_idx]), 4), "\n")
  if (length(unique(y[calib_idx])) < 2L)
    stop("[ERROR] La fenetre de calibration ne contient qu'une seule classe. Augmentez --calibFrac.")
} else {
  cat("[CALIB] --calibFrac = 1 : selection sur la totalite des flux (fuite de selection assumee).\n")
}

# ------------------------------------------------------------
#  2. Construction du pool de variables candidates
# ------------------------------------------------------------
EXCLUDE_COLS <- c(
  "attacked", "index", "group", "group_num", "run_id", "seed",
  "sc_proto", "sc_hops", "sc_att", "sc_rate",
  "extra_router", "extra_detour", "parasite_rate",
  "src_ip", "dst_ip", "file", "proto", "protocol",
  "nb_packets", "packet_size"
  ,"packet_length", "simulation_time"
  ,"src_port", "dst_port",
  # Statistiques numeriquement degenerees a 9 paquets (CV ~ 1e17).
  "diff_mean", "diff_median", "diff_min", "diff_max",
  "fmean_mean", "fmedian_median"
)
if (nzchar(opt$setupParam) && file.exists(opt$setupParam)) {
  ok <- tryCatch({ source(opt$setupParam, local = TRUE); TRUE },
                 error = function(e) { cat("[WARN] setup_param.R non sourcable :",
                                           conditionMessage(e), "\n"); FALSE })
  if (ok && exists("remove_col", inherits = TRUE)) {
    EXCLUDE_COLS <- union(EXCLUDE_COLS, get("remove_col"))
    cat("[INFO] remove_col recupere depuis setup_param.R.\n")
  }
}
if (isTRUE(opt$dropTemporal))
  EXCLUDE_COLS <- union(EXCLUDE_COLS, c("t_start", "t_end"))
# Variables de deviation a une reference conditionnelle a la classe.
# feature_analysis_section32.R les calcule par rapport a la mediane des flux
# benins de TOUT le scenario, tandis que model_function.R les calcule par
# rapport a la mediane des flux benins du seul jeu d'entrainement. Les colonnes
# du cache ne sont donc pas celles que les modeles recoivent, et leur AUC hors
# ligne est optimiste : les retenir comme representantes de groupe revient a
# selectionner sur une fuite.
LABEL_DEPENDENT <- c("d_alpha", "d_masd", "d_cv", "d_beta")
if (isTRUE(opt$dropLabelDependent)) {
  EXCLUDE_COLS <- union(EXCLUDE_COLS, LABEL_DEPENDENT)
  cat("[POOL] Variables dependantes des etiquettes ecartees :",
      paste(LABEL_DEPENDENT, collapse = ", "), "\n")
  cat("        (--dropLabelDependent FALSE pour les conserver)\n")
} else {
  cat("[WARN] --dropLabelDependent FALSE : les variables",
      paste(LABEL_DEPENDENT, collapse = ", "), "\n")
  cat("[WARN] entrent dans le pool alors que leur AUC hors ligne est optimiste.\n")
}
num_cols <- names(all_flows)[vapply(all_flows, is.numeric, logical(1))]
cand     <- setdiff(num_cols, EXCLUDE_COLS)
if (nzchar(opt$poolFile)) {
  if (!file.exists(opt$poolFile))
    stop("[ERROR] --poolFile introuvable : ", opt$poolFile)
  raw_pool <- trimws(readLines(opt$poolFile, warn = FALSE))
  # Tolerance : si le fichier est en realite un CSV exporte (une ligne par
  # variable, colonnes separees par ; ou , ou tabulation), on ne garde que le
  # premier champ. Sans cela une seule ligne mal formee fait disparaitre
  # silencieusement une variable du pool.
  sep_hits <- grepl("[;,\t]", raw_pool)
  if (any(sep_hits)) {
    cat("[POOL] ", sum(sep_hits), " ligne(s) de --poolFile contiennent un separateur",
        " (; , ou tabulation) : seul le premier champ est retenu.\n", sep = "")
    raw_pool <- sub("[;,\t].*$", "", raw_pool)
  }
  wanted  <- trimws(raw_pool)
  # Retrait d'un eventuel en-tete de colonne
  hdr <- tolower(wanted) %in% c("feature", "features", "name", "variable", "var")
  if (any(hdr)) {
    cat("[POOL] En-tete ignore dans --poolFile :",
        paste(unique(wanted[hdr]), collapse = ", "), "\n")
    wanted <- wanted[!hdr]
  }
  # wanted  <- trimws(readLines(opt$poolFile, warn = FALSE))
  wanted  <- wanted[nzchar(wanted) & !startsWith(wanted, "#")]
  absent  <- setdiff(wanted, cand)
  if (length(absent))
    cat("[POOL] Demandees via --poolFile mais absentes du pool candidat\n")
  cat("        (soit introuvables dans les donnees, soit exclues comme\n")
  cat("         metadonnees ou par --dropTemporal) :",
      paste(absent, collapse = ", "), "\n")
  cand <- intersect(cand, wanted)
  cat("[POOL] Pool restreint par --poolFile :", length(cand), "variables\n")
}
cat("[POOL] Colonnes numeriques :", length(num_cols),
    "| candidates apres exclusion des metadonnees :", length(cand), "\n")

diag_pool <- data.table(
  feature     = cand,
  frac_finite = vapply(cand, function(f) mean(is.finite(all_flows[[f]])), numeric(1)),
  n_unique    = vapply(cand, function(f) {
    v <- all_flows[[f]]; length(unique(v[is.finite(v)]))
  }, integer(1))
)
diag_pool[, keep_finite := frac_finite >= opt$minFinite]
diag_pool[, keep_var    := n_unique > 1L]
diag_pool[, in_pool     := keep_finite & keep_var]

dropped <- diag_pool[in_pool == FALSE]
if (nrow(dropped) > 0L) {
  cat("[POOL] Variables ecartees (", nrow(dropped), ") :\n", sep = "")
  for (i in seq_len(nrow(dropped))) {
    r <- dropped[i]
    cat(sprintf("        %-22s finite=%.2f  n_unique=%d  -> %s\n",
                r$feature, r$frac_finite, r$n_unique,
                if (!r$keep_finite) "trop de NA/Inf" else "constante"))
  }
}
# Ecran de doublons exacts, identique a celui de feature_analysis_section32.R :
# une variable strictement egale a une autre n'est pas un cas de redondance
# statistique mais un defaut de definition a cette taille de flux.
pool <- diag_pool[in_pool == TRUE, feature]
if (length(pool) > 1L) {
  sig <- lapply(pool, function(f) {
    v <- suppressWarnings(as.numeric(all_flows[[f]]))
    v[!is.finite(v)] <- NA_real_
    v
  })
  names(sig) <- pool
  drop_dup <- character(0)
  for (i in seq_along(pool)) {
    if (pool[i] %in% drop_dup) next
    for (j in seq_len(i - 1L)) {
      if (pool[j] %in% drop_dup) next
      if (isTRUE(all.equal(sig[[i]], sig[[j]], tolerance = 1e-12,
                           check.attributes = FALSE))) {
        cat("[POOL] ", pool[i], " strictement identique a ", pool[j],
            " : ecartee\n", sep = "")
        drop_dup <- c(drop_dup, pool[i]); break
      }
    }
  }
  pool <- setdiff(pool, drop_dup)
  diag_pool[feature %in% drop_dup, in_pool := FALSE]
}
if (length(pool) < k_ceiling)
  stop("[ERROR] Pool de ", length(pool),
       " variables insuffisant pour k = ", k_ceiling, ".")
cat("[POOL] Taille finale  :", length(pool), "variables\n")

# ------------------------------------------------------------
#  3. Diagnostic de COUVERTURE des listes de variables des modeles
#     (lecture seule de model_function.R ; purement informatif)
# ------------------------------------------------------------
parse_model_features <- function(path) {
  if (!nzchar(path) || !file.exists(path)) return(NULL)
  raw <- readLines(path, warn = FALSE)
  txt <- sub("#.*$", "", raw)                     # retrait des commentaires
  starts <- grep("^\\s*(reglog|svm|vae|dae)_features\\s*<-\\s*c\\(", txt)
  out <- list()
  for (s in starts) {
    nm    <- sub("^\\s*([a-z]+)_features.*$", "\\1", txt[s])
    depth <- 0L; buf <- character(0)
    for (i in seq(s, length(txt))) {
      buf    <- c(buf, txt[i])
      opens  <- lengths(regmatches(txt[i], gregexpr("\\(", txt[i])))
      closes <- lengths(regmatches(txt[i], gregexpr("\\)", txt[i])))
      depth  <- depth + opens - closes
      if (depth <= 0L) break
    }
    one   <- paste(buf, collapse = " ")
    # Ignorer les affectations d'AJOUT du type
    #   reglog_features <- c(reglog_features, "t_start", "t_end")
    # qui correspondent aux blocs d'ablation et non a la definition de la
    # liste. Sans ce test, la derniere affectation rencontree ecrase la vraie
    # liste et le diagnostic de couverture devient faux.
    rhs <- sub("^[^(]*\\(", "", one)
    if (grepl(paste0(nm, "_features"), rhs)) next
    feats <- gsub('"', '', unlist(regmatches(one, gregexpr('"[^"]+"', one))))
    if (length(feats)) out[[nm]] <- unique(feats)
  }
  out
}

model_feats <- parse_model_features(opt$modelFile)
if (!is.null(model_feats) && length(model_feats)) {
  cat("\n[COUVERTURE] Variables des modeles absentes du pool.\n")
  cat("             Elles seront supprimees par intersect() SANS avoir ete\n")
  cat("             analysees. A verifier avant d'activer reduced_feature_set.\n")
  for (nm in names(model_feats)) {
    miss <- setdiff(model_feats[[nm]], pool)
    miss <- setdiff(miss, c("t_start", "t_end"))   # traites par l'instruction C
    cat(sprintf("  %-7s : %2d / %2d couvertes",
                nm, length(intersect(model_feats[[nm]], pool)),
                length(model_feats[[nm]])))
    if (length(miss)) cat("  | absentes : ", paste(miss, collapse = ", "))
    cat("\n")
  }
  cat("\n")
}

# ------------------------------------------------------------
#  4. AUC univariee symetrique
# ------------------------------------------------------------
cat("[AUC] Calcul des AUC univariees...\n")
y_cal <- y[calib_idx]
auc_sym <- function(f) {
  v  <- suppressWarnings(as.numeric(all_flows[[f]]))[calib_idx]
  ok <- is.finite(v)
  if (sum(ok) < 10L) return(NA_real_)
  yy <- y_cal[ok]; vv <- v[ok]
  if (length(unique(yy)) < 2L || length(unique(vv)) < 2L) return(NA_real_)
  a <- tryCatch(as.numeric(pROC::auc(pROC::roc(yy, vv, quiet = TRUE,
                                               direction = "auto"))),
                error = function(e) NA_real_)
  if (is.na(a)) return(NA_real_)
  max(a, 1 - a)                    # AUC symetrique, comme au critere 2
}
auc_vec <- vapply(pool, auc_sym, numeric(1))
names(auc_vec) <- pool
cat("[AUC] ", sum(!is.na(auc_vec)), "/", length(pool),
    " AUC calculees | mediane = ",
    sprintf("%.3f", median(auc_vec, na.rm = TRUE)), "\n", sep = "")

# ------------------------------------------------------------
#  5. Correlation de Spearman et dendrogramme
# ------------------------------------------------------------
cat("[CORR] Matrice de Spearman sur", length(pool), "variables...\n")
X <- as.matrix(all_flows[, ..pool])
X[!is.finite(X)] <- NA_real_
M <- suppressWarnings(cor(X, method = "spearman", use = "pairwise.complete.obs"))
rm(X); invisible(gc())

# Retrait iteratif des variables dont la ligne de correlation reste
# indeterminee (paires sans recouvrement suffisant).
guard <- 0L
while (anyNA(M) && nrow(M) > k_ceiling && guard < 200L) {
  guard <- guard + 1L
  bad   <- which.max(colSums(is.na(M)))
  cat("[CORR] Retrait de", colnames(M)[bad], "(",
      colSums(is.na(M))[bad], "correlations indeterminees )\n")
  M <- M[-bad, -bad, drop = FALSE]
}
if (anyNA(M)) stop("[ERROR] Matrice de correlation encore indeterminee apres nettoyage.")

pool    <- colnames(M)
auc_vec <- auc_vec[pool]
D       <- as.dist(1 - abs(M))
hc      <- hclust(D, method = opt$linkage)
cat("[CORR] Dendrogramme :", opt$linkage, "sur", length(pool), "variables\n")

# ------------------------------------------------------------
#  5bis. Nombre de groupes optimal par silhouette
#
#  Meme critere qu'en section 3.2 (derive_families), mais applique au
#  pool effectivement utilise ici et non au catalogue de 44 variables :
#  le k optimal des deux analyses n'a aucune raison de coincider.
#
#  LIMITE A ENONCER DANS LE MANUSCRIT : la silhouette mesure la qualite
#  du partitionnement de la STRUCTURE DE CORRELATION. Elle ne dit rien
#  du nombre de variables necessaires a la DETECTION. Le k retenu est
#  donc un choix principe et non arbitraire, mais la reponse empirique
#  a la question « combien de variables suffisent ? » reste le tableau
#  des F1 obtenus pour plusieurs coupes.
# ------------------------------------------------------------
k_opt   <- NA_integer_
sil_dt  <- data.table(k = integer(0), mean_silhouette = numeric(0))
k_range <- seq.int(opt$kMin, min(opt$kMax, length(pool) - 1L))
if (length(k_range) < 1L)
  stop("[ERROR] Intervalle de k vide : pool de ", length(pool), " variables.")

cat("[SIL] Balayage k =", min(k_range), "..", max(k_range), "\n")
sil_vals <- vapply(k_range, function(k) {
  cl <- cutree(hc, k = k)
  if (length(unique(cl)) < 2L) return(NA_real_)
  s <- tryCatch(cluster::silhouette(cl, D), error = function(e) NULL)
  if (is.null(s)) return(NA_real_)
  mean(s[, "sil_width"], na.rm = TRUE)
}, numeric(1))
sil_dt <- data.table(k = k_range, mean_silhouette = round(sil_vals, 4))
fwrite(sil_dt, out_file("silhouette_scores", TAG, ".csv"), sep = ";")

if (all(is.na(sil_vals))) {
  cat("[SIL] Silhouette non calculable : aucun k automatique.\n")
} else {
  k_opt <- k_range[which.max(sil_vals)]
  cat(sprintf("[SIL] k optimal = %d  (silhouette moyenne = %.4f)\n",
              k_opt, max(sil_vals, na.rm = TRUE)))
  top <- sil_dt[order(-mean_silhouette)][seq_len(min(5L, .N))]
  cat("[SIL] Cinq meilleures coupes :",
      paste(sprintf("k=%d (%.3f)", top$k, top$mean_silhouette),
            collapse = "  "), "\n")
  if (!is.na(k_opt_32) && k_opt_32 != k_opt)
    cat("[SIL] Ecart avec la section 3.2 (k =", k_opt_32,
        ") : normal, les pools different.\n")
  if (auto_k) ks <- sort(unique(c(ks, k_opt)))
}
if (length(ks) == 0L)
  stop("[ERROR] Aucune coupe a evaluer : silhouette indisponible et --k sans valeur numerique.")

# Courbe de silhouette (figure de justification du k retenu)
if (nrow(sil_dt) > 1L) {
  sil_base <- out_file("silhouette_curve", TAG)
  sil_devs <- switch(opt$figFormat,
                     "pdf"  = list(pdf = paste0(sil_base, ".pdf")),
                     "png"  = list(png = paste0(sil_base, ".png")),
                     "both" = list(pdf = paste0(sil_base, ".pdf"),
                                   png = paste0(sil_base, ".png")),
                     list(pdf = paste0(sil_base, ".pdf")))
  for (nm in names(sil_devs)) {
    if (nm == "pdf") grDevices::pdf(sil_devs[[nm]], width = 7, height = 4.5)
    else grDevices::png(sil_devs[[nm]], width = 840, height = 540, res = 120)
    op <- graphics::par(mar = c(4.5, 4.5, 2.5, 1))
    graphics::plot(sil_dt$k, sil_dt$mean_silhouette, type = "b", pch = 19,
                   xlab = "Number of groups k",
                   ylab = "Mean silhouette width",
                   main = sprintf("Silhouette selection on %d features (%s linkage)",
                                  length(pool), opt$linkage))
    if (!is.na(k_opt)) {
      graphics::abline(v = k_opt, lty = 2, col = "steelblue")
      graphics::mtext(sprintf("k = %d", k_opt), side = 3, at = k_opt,
                      col = "steelblue", cex = 0.85)
    }
    graphics::par(op); grDevices::dev.off()
  }
}

# ------------------------------------------------------------
#  6. Coupes et selection des representants
# ------------------------------------------------------------
membership <- data.table(feature = pool, auc = round(auc_vec[pool], 4))
rho_max_vec <- vapply(pool, function(f)
  max(abs(M[f, setdiff(pool, f)]), na.rm = TRUE), numeric(1))
membership[, rho_max := round(rho_max_vec[feature], 3)]

reduced_sets <- list()
tex_rows     <- character(0)
fig_files    <- character(0)

# Representant alternatif : medoide du groupe (variable la plus centrale au
# sens de la distance 1 - |rho|). Reporte a titre de comparaison : si medoide
# et representant AUC coincident, le choix du critere n'influe pas.
medoid_of <- function(g) {
  if (length(g) == 1L) return(g)
  sub <- 1 - abs(M[g, g, drop = FALSE])
  g[which.min(rowMeans(sub))]
}

# Dendrogramme annote : les representants sont suffixes d'une asterisque et
# les groupes encadres. C'est CETTE figure qui doit remplacer celle de
# l'annexe feature_redundancy.tex, pour que l'arbre montre et l'arbre coupe
# soient le meme objet.
draw_dendro <- function(k, reps, base_path) {
  labs <- ifelse(hc$labels %in% reps, paste0(hc$labels, " *"), hc$labels)
  hcp  <- hc; hcp$labels <- labs
  w <- max(9, 0.20 * length(pool)); h <- 7.5
  devs <- switch(opt$figFormat,
                 "pdf"  = list(pdf = paste0(base_path, ".pdf")),
                 "png"  = list(png = paste0(base_path, ".png")),
                 "both" = list(pdf = paste0(base_path, ".pdf"),
                               png = paste0(base_path, ".png")),
                 list(pdf = paste0(base_path, ".pdf")))
  for (nm in names(devs)) {
    if (nm == "pdf") grDevices::pdf(devs[[nm]], width = w, height = h)
    else grDevices::png(devs[[nm]], width = round(w * 120),
                        height = round(h * 120), res = 120)
    op <- graphics::par(mar = c(11, 4.5, 3, 1))
    graphics::plot(hcp, main = sprintf(
      "Hierarchical clustering of the %d candidate features (%s linkage), k = %d",
      length(pool), opt$linkage, k),
      xlab = "", sub = "", ylab = expression(1 - group("|", rho[s], "|")),
      cex = 0.72, hang = -1)
    stats::rect.hclust(hc, k = k, border = "steelblue")
    graphics::par(op); grDevices::dev.off()
  }
  unlist(devs, use.names = FALSE)
}

pick_best <- function(g) {
  s <- abs(auc_vec[g] - 0.5)
  if (all(is.na(s))) return(NA_character_)
  g[which.max(s)]
}

for (k in ks) {
  # grp  <- cutree(hc, k = k)
  # reps <- vapply(split(names(grp), grp), function(g) {
  #   s <- abs(auc_vec[g] - 0.5)
  #   if (all(is.na(s))) return(NA_character_)
  #   g[which.max(s)]
  # }, character(1))
  # reps <- unname(reps[!is.na(reps)])
  grp     <- cutree(hc, k = k)
  clusters <- split(names(grp), grp)
  
  reps_global <- unname(vapply(clusters, pick_best, character(1)))
  reps_global <- reps_global[!is.na(reps_global)]
  
  # ---- Representants par modele ----
  # Un representant choisi globalement peut n'appartenir a la liste d'aucun
  # modele donne. Le groupe disparait alors entierement pour ce modele, meme
  # s'il contenait un grand nombre de ses variables : c'est ce qui fait
  # s'effondrer un modele auquel il ne reste plus aucune variable de niveau de
  # delai. On choisit donc, pour chaque modele, le meilleur representant PARMI
  # SES PROPRES variables, et le jeu livre est l'union de ces choix. Sa taille
  # depasse k, mais chaque modele n'en recoit au plus qu'un par groupe.
  reps_by_model <- list()
  if (!is.null(model_feats) && length(model_feats)) {
    for (nm in names(model_feats)) {
      own <- vapply(clusters, function(g) pick_best(intersect(g, model_feats[[nm]])),
                    character(1))
      reps_by_model[[nm]] <- unname(own[!is.na(own)])
    }
  }
  
  reps <- if (identical(opt$repScope, "per_model") && length(reps_by_model)) {
    sort(unique(unlist(reps_by_model, use.names = FALSE)))
  } else {
    reps_global
  }
  
  # ---- Filtre optionnel sur le pouvoir discriminant du representant ----
  # La silhouette optimise la structure de correlation, pas la detection. Une
  # variable orthogonale a toutes les autres forme un singleton parfait et
  # obtient une place quelle que soit son AUC. Ce filtre les ecarte.
  if (opt$minRepAUC > 0) {
    weak <- reps[!is.na(auc_vec[reps]) & auc_vec[reps] < opt$minRepAUC]
    if (length(weak)) {
      cat("   [minRepAUC] representants ecartes (AUC < ",
          sprintf("%.3f", opt$minRepAUC), ") : ",
          paste(sprintf("%s (%.3f)", weak, auc_vec[weak]), collapse = ", "),
          "\n", sep = "")
      reps <- setdiff(reps, weak)
      reps_by_model <- lapply(reps_by_model, function(v) setdiff(v, weak))
    }
    if (length(reps) == 0L)
      stop("[ERROR] --minRepAUC = ", opt$minRepAUC,
           " ne laisse aucun representant pour k = ", k, ".")
  }
  
  membership[, (paste0("cluster_k", k)) := grp[feature]]
  membership[, (paste0("rep_k", k))     := feature %in% reps]
  
  reduced_sets[[as.character(k)]] <- reps
  
  rds_path <- out_file(sprintf("reduced_features_k%d", k), TAG, ".rds")
  saveRDS(reps, rds_path)
  if (!is.na(k_opt) && k == k_opt) {
    # Nom stable, independant de la valeur de k : c'est ce fichier que
    # setup_param.R ou --reducedFeatures doivent viser par defaut.
    saveRDS(reps, out_file("reduced_features_kopt", TAG, ".rds"))
  }
  
  detail <- data.table(
    cluster = as.integer(names(split(names(grp), grp))),
    size    = vapply(split(names(grp), grp), length, integer(1)),
    rep     = vapply(split(names(grp), grp), function(g) {
      s <- abs(auc_vec[g] - 0.5)
      if (all(is.na(s))) NA_character_ else g[which.max(s)]
    }, character(1)),
    members = vapply(split(names(grp), grp),
                     function(g) paste(g, collapse = " "), character(1))
  )
  # detail[, rep_auc := round(auc_vec[rep], 4)]
  setnames(detail, "rep", "rep_global")
  detail[, rep_auc := round(auc_vec[rep_global], 4)]
  detail[, medoid := vapply(split(names(grp), grp), medoid_of, character(1))]
  # detail[, medoid_is_rep := medoid == rep]
  detail[, medoid_is_rep := medoid == rep_global]
  # Representant effectivement retenu POUR CHAQUE MODELE. Sans ces colonnes le
  # tableau des groupes annonce un representant global qui, en portee
  # per_model, ne figure pas necessairement dans le jeu livre.
  if (length(reps_by_model)) {
    for (nm in names(reps_by_model)) {
      own <- vapply(clusters, function(g)
        pick_best(intersect(g, model_feats[[nm]])), character(1))
      detail[, (paste0("rep_", nm)) := unname(own)]
    }
  }
  detail[, in_delivered := rep_global %in% reps]
  
  fwrite(detail, out_file(sprintf("clusters_k%d", k), TAG, ".csv"), sep = ";")
  
  fig_files <- c(fig_files, draw_dendro(
    k, reps, out_file(sprintf("dendrogram_reduction_k%d", k), TAG)))
  
  is_kopt <- !is.na(k_opt) && k == k_opt
  cat("\n=== k =", k, "===",
      if (is_kopt) "<< COUPE RETENUE (silhouette maximale) >>" else "", "\n")
  cat("  ", length(reps), "representants :", paste(sort(reps), collapse = ", "), "\n")
  mdl_cols <- grep("^rep_(reglog|svm|vae|dae)$", names(detail), value = TRUE)
  for (i in seq_len(nrow(detail))) {
    r <- detail[i]
    # cat(sprintf("   C%-2d (n=%2d) rep=%-20s AUC=%s\n",
    #             r$cluster, r$size, r$rep,
    #             if (is.na(r$rep_auc)) "  N/A" else sprintf("%.3f", r$rep_auc)))
    
    cat(sprintf("   C%-2d (n=%2d) global=%-20s AUC=%s%s\n",
                r$cluster, r$size, r$rep_global,
                if (is.na(r$rep_auc)) "  N/A" else sprintf("%.3f", r$rep_auc),
                if (isTRUE(r$in_delivered)) "" else "   [non livre tel quel]"))
    if (length(mdl_cols)) {
      per <- unlist(r[, ..mdl_cols])
      per <- per[!is.na(per)]
      # if (length(per) && length(unique(per)) > 1L)
      # Afficher le detail par modele des que le choix retenu differe du
      # representant global, y compris quand les quatre modeles s'accordent
      # entre eux : sinon la ligne « non livre tel quel » n'indique pas ce
      # qui est livre a la place.
      if (length(per) &&
          (length(unique(per)) > 1L ||
           !identical(unname(unique(per)), r$rep_global)))
        cat("        par modele : ",
            paste(sprintf("%s=%s", sub("^rep_", "", names(per)), per),
                  collapse = "  "), "\n", sep = "")
    }
  }
  cat("  -> ", rds_path, "\n", sep = "")
  cat("   concordance medoide / representant AUC : ",
      sum(detail$medoid_is_rep, na.rm = TRUE), "/", nrow(detail), "\n", sep = "")
  # ---- Nombre de variables que chaque modele recevra effectivement ----
  # C'est la quantite qui determine si le jeu reduit est exploitable. Un
  # modele qui ne recoit que quelques variables ne produira pas un resultat
  # de reduction mais un modele casse.
  if (!is.null(model_feats) && length(model_feats)) {
    cat("   jeu livre : ", length(reps), " variables (portee : ",
        opt$repScope, ")\n", sep = "")
    cat("   variables effectivement recues apres intersect() :\n")
    for (nm in names(model_feats)) {
      # eff <- intersect(model_feats[[nm]], reps)
      eff  <- intersect(model_feats[[nm]], reps)
      # Nombre de groupes du modele qui restent representes : c'est la
      # quantite qui compte, pas le nombre brut de variables.
      cl_own   <- vapply(clusters, function(g)
        length(intersect(g, model_feats[[nm]])) > 0L, logical(1))
      cl_kept  <- vapply(clusters, function(g)
        length(intersect(g, eff)) > 0L, logical(1))
      lost <- names(clusters)[cl_own & !cl_kept]
      flag <- if (length(eff) == 0L) "  <<< AUCUNE : jeu reduit inutilisable"
      # else if (length(eff) < 5L) "  <<< TRES PEU : resultat non interpretable"
      # else ""
      # cat(sprintf("        %-7s %2d / %2d representants%s\n",
      #             nm, length(eff), length(reps), flag))
      # if (length(eff) > 0L && length(eff) < 5L)
      #   cat("               ", paste(eff, collapse = ", "), "\n")
      else if (length(lost)) "  <<< GROUPES PERDUS" else ""
      cat(sprintf("        %-7s %2d variables | %2d/%2d de ses groupes representes%s\n",
                  nm, length(eff), sum(cl_kept), sum(cl_own), flag))
      if (length(lost)) {
        for (cid in lost) {
          mem <- intersect(clusters[[cid]], model_feats[[nm]])
          cat(sprintf("               C%-3s perdu (%d variables du modele) : %s\n",
                      cid, length(mem),
                      paste(utils::head(mem, 6), collapse = ", ")))
        }
      }
    }
    saveRDS(reps_by_model,
            out_file(sprintf("reps_by_model_k%d", k), TAG, ".rds"))
  }
  # Les noms de variables partent en mode texte : l'underscore doit etre
  # echappe, faute de quoi le fragment ne compile pas. Et le marqueur de coupe
  # retenue doit rester DANS le mode mathematique, sinon "$k = 11$$^{\dagger}$"
  # ouvre un environnement mathematique hors ligne.
  tex_esc <- function(x) gsub("_", "\\_", x, fixed = TRUE)
  tex_rows <- c(tex_rows, sprintf(
    "$k = %d%s$ & %d & %s & PREVIEW_k%d & \\textit{a completer} \\\\",
    k, if (is_kopt) "^{\\dagger}" else "",
    length(reps),
    paste(vapply(sort(reps), function(f) paste0("\\texttt{", tex_esc(f), "}"),
                 character(1)), collapse = ", "), k))
}

fwrite(membership, out_file("reduction_membership", TAG, ".csv"), sep = ";")
fwrite(diag_pool,  out_file("pool_diagnostics", TAG, ".csv"), sep = ";")

# ------------------------------------------------------------
#  6bis. Apercu multivarie
#  Un filtre univarie ignore les effets conditionnels : une variable
#  d'AUC proche de 0,5 peut etre decisive une fois les autres controlees.
#  Cette regression logistique en validation croisee 5 blocs donne, en
#  quelques secondes, un ordre de grandeur de la perte associee a chaque
#  coupe AVANT de lancer le pipeline complet. Ce n'est PAS un resultat du
#  manuscrit : les F1 du tableau restent ceux de generation_unified.R.
# ------------------------------------------------------------
preview_dt <- data.table(set = character(0), n_features = integer(0),
                         cv_auc = numeric(0))
cv_auc_glm <- function(feats, folds = 5L, max_n = 20000L) {
  feats <- intersect(feats, names(all_flows))
  if (length(feats) == 0L) return(NA_real_)
  set.seed(1997L)
  idx <- calib_idx
  if (length(idx) > max_n) idx <- sort(sample(idx, max_n))
  D <- as.data.frame(lapply(feats, function(f) {
    v <- suppressWarnings(as.numeric(all_flows[[f]]))[idx]
    v[!is.finite(v)] <- NA_real_
    m <- stats::median(v, na.rm = TRUE); if (!is.finite(m)) m <- 0
    v[is.na(v)] <- m
    s <- stats::sd(v); if (!is.finite(s) || s == 0) s <- 1
    (v - mean(v)) / s
  }), stringsAsFactors = FALSE)
  names(D) <- make.names(feats)
  D$.y <- y[idx]
  fold <- sample(rep_len(seq_len(folds), nrow(D)))
  aucs <- vapply(seq_len(folds), function(kk) {
    tr <- fold != kk; te <- !tr
    if (length(unique(D$.y[tr])) < 2L || length(unique(D$.y[te])) < 2L)
      return(NA_real_)
    fit <- tryCatch(suppressWarnings(
      stats::glm(.y ~ ., data = D[tr, , drop = FALSE], family = stats::binomial())),
      error = function(e) NULL)
    if (is.null(fit)) return(NA_real_)
    p <- tryCatch(stats::predict(fit, newdata = D[te, , drop = FALSE],
                                 type = "response"), error = function(e) NULL)
    if (is.null(p) || all(!is.finite(p))) return(NA_real_)
    tryCatch(as.numeric(pROC::auc(pROC::roc(D$.y[te], as.numeric(p), quiet = TRUE))),
             error = function(e) NA_real_)
  }, numeric(1))
  mean(aucs, na.rm = TRUE)
}

if (isTRUE(opt$preview)) {
  cat("\n[PREVIEW] Regression logistique, validation croisee 5 blocs...\n")
  a_full <- cv_auc_glm(pool)
  preview_dt <- rbind(preview_dt, data.table(set = "full", n_features = length(pool),
                                             cv_auc = round(a_full, 4)))
  cat(sprintf("  full  (%2d vars) : AUC = %.4f\n", length(pool), a_full))
  for (k in ks) {
    r  <- reduced_sets[[as.character(k)]]
    ak <- cv_auc_glm(r)
    preview_dt <- rbind(preview_dt, data.table(set = paste0("k", k),
                                               n_features = length(r),
                                               cv_auc = round(ak, 4)))
    cat(sprintf("  k=%-3d (%2d vars) : AUC = %.4f   (delta = %+.4f)\n",
                k, length(r), ak, ak - a_full))
  }
  fwrite(preview_dt, out_file("preview_cv_auc", TAG, ".csv"), sep = ";")
}

get_preview <- function(tag) {
  if (!nrow(preview_dt)) return("---")
  v <- preview_dt[set == tag, cv_auc]
  if (!length(v) || is.na(v[1])) "---" else sprintf("%.3f", v[1])
}
for (k in ks)
  tex_rows <- sub(sprintf("PREVIEW_k%d", k), get_preview(paste0("k", k)),
                  tex_rows, fixed = TRUE)

# ------------------------------------------------------------
#  7. Fragment LaTeX pour l'annexe feature_redundancy.tex
# ------------------------------------------------------------
tex <- c(
  "% Genere par feature_reduction.R (instruction E). Ne pas editer a la main.",
  "\\begin{table}[htbp]",
  "  \\centering",
  "  \\caption{Effect of feature-set reduction on detection performance. Groups are",
  "  obtained by cutting the dendrogram of Figure~\\ref{fig:feat-dendro} at $k$ groups",
  sprintf("  (distance $1-|\\rho_s|$, %s linkage); the representative of each group is the", opt$linkage),
  # "  feature whose univariate AUC is farthest from $0.5$, computed on the first",
  "  feature whose univariate AUC is farthest from $0.5$ among the inputs of that",
  "  model, so that no group is left unrepresented for any model; the delivered set",
  "  is the union of these per-model choices and is therefore larger than $k$. A model",
  "  may receive more than one feature from a group, when the representative chosen",
  "  for another model also belongs to its own input list. AUCs are computed on the first",
  sprintf("  %d\\%% of each scenario. The cross-validated AUC of a logistic model is reported", round(100 * opt$calibFrac)),
  "  as an indication only; the $F_1$-scores are medians over the runs of the",
  "  reference scenario, obtained with the full detection pipeline.",
  "  $^{\\dagger}$~Cut retained by silhouette maximisation over the feature",
  "  correlation structure.}",
  "  \\label{tab:feature-reduction}",
  "  \\begin{tabular}{l r p{6cm} c c}",
  "  \\toprule",
  "  \\textbf{Feature set} & \\textbf{\\#} & \\textbf{Features} & \\textbf{CV AUC} & \\textbf{$F_1$ (REG\\_LOG)} \\\\",
  "  \\midrule",
  sprintf("  Full set & %d & --- & %s & \\textit{a completer} \\\\",
          length(pool), get_preview("full")),
  paste0("  ", tex_rows),
  "  \\bottomrule",
  "  \\end{tabular}",
  "\\end{table}"
)
writeLines(tex, out_file("feature_reduction_table", TAG, ".tex"))

# ------------------------------------------------------------
#  8. Recapitulatif
# ------------------------------------------------------------
cat("\n", strrep("=", 66), "\n", sep = "")
cat("  REDUCTION DU JEU DE VARIABLES — TERMINEE\n")
cat(strrep("=", 66), "\n", sep = "")
cat("  Cache source     : ", CACHE_DIR, "\n", sep = "")
cat("  Flux analyses    : ", nrow(all_flows), "\n", sep = "")
cat("  Pool final       : ", length(pool), " variables\n", sep = "")
cat("  Coupes testees   : ", paste(ks, collapse = ", "), "\n", sep = "")
cat("  Coupe retenue    : ",
    if (is.na(k_opt)) "aucune (silhouette indisponible)"
    else sprintf("k = %d  (silhouette moyenne = %.4f)", k_opt,
                 max(sil_dt$mean_silhouette, na.rm = TRUE)), "\n", sep = "")
if (!is.na(k_opt_32))
  cat("  Rappel sect. 3.2 : k = ", k_opt_32,
      " (catalogue de 44 variables, pool different)\n", sep = "")
cat("  Sorties          : ", opt$outDir, "\n", sep = "")
cat("      reduced_features_kopt.rds   (coupe retenue, nom stable)\n")
cat("      reduced_features_k<k>.rds   (coupes de comparaison)\n")
cat("      silhouette_scores.csv       (silhouette moyenne par k)\n")
cat("      silhouette_curve            (figure de justification du k retenu)\n")
cat("      dendrogram_reduction_k<k>   (figure a substituer dans l'annexe)\n")
cat("      clusters_k<k>.csv           (composition, representant, medoide)\n")
cat("      reduction_membership.csv    (AUC, rho_max, appartenance)\n")
cat("      pool_diagnostics.csv        (variables ecartees et pourquoi)\n")
cat("      preview_cv_auc.csv          (apercu multivarie, indicatif)\n")
cat("      feature_reduction_table.tex (squelette du tableau d'annexe)\n\n")
cat("  Pour activer un jeu reduit, dans setup_param.R :\n")
cat(sprintf("      reduced_feature_set <- readRDS(\"%s\")\n",
            if (is.na(k_opt)) out_file(sprintf("reduced_features_k%d", ks[1]), TAG, ".rds")
            else out_file("reduced_features_kopt", TAG, ".rds")))
cat("  ou, sans modifier setup_param.R :\n")
cat("      Rscript generation_unified.R ... --reducedFeatures <chemin.rds>\n")
cat(strrep("=", 66), "\n", sep = "")
