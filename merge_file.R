## merge_file.R — fusion des sorties *_error_model.csv
## Corrige : (1) segfault de fs::dir_ls(recurse=TRUE) sur arbre profond,
##           (2) batching O(N^2) du fichier temporaire,
##           (3) lenteur de read.table/write.table,
##           (4) nom de fichier de sortie invalide.

suppressPackageStartupMessages({
  library(data.table)
  library(getip)
})

# library(fs)
# library(purrr)
# library(dplyr)
# library(getip) # getip address
# library(data.table)

# ---- 1. Paramètres ----------------------------------------------------------
start_time <- format(Sys.time(), "%Y%m%d_%H%M%S")   # safe pour systèmes de fichiers
ipaddr     <- getip("internal")
root_dir   <- paste0(ipaddr, "/")
batch_size <- 100L
pattern    <- "_error_model\\.csv$"

if (!dir.exists(root_dir)) {
  stop("Répertoire racine introuvable : ", root_dir,
       " (vérifier que getip('internal') correspond bien à un dossier existant)")
}

# # Fonction pour trouver les répertoires "feuilles"
# find_leaf_directories <- function(root_dir) {
#   dirs <- dir_ls(root_dir, type = "directory", recurse = TRUE)
#   leaf_dirs <- dirs[sapply(dirs, function(d) length(dir_ls(d, type = "directory")) == 0)]
#   return(leaf_dirs)
# }

# ---- 2. Collecte des fichiers cibles ---------------------------------------
# list.files() est itératif côté C : pas de stack overflow, pas de double scan.
# Si l'arbre devient pathologiquement gros, basculer sur :
#   csv_files <- system2("find", c(root_dir, "-type", "f",
#                                  "-name", "*_error_model.csv"), stdout = TRUE)
csv_files <- list.files(
  path       = root_dir,
  pattern    = pattern,
  recursive  = TRUE,
  full.names = TRUE
)

n <- length(csv_files)
cat(sprintf("Fichiers trouvés : %d\n", n))
if (n == 0L) stop("Aucun fichier correspondant à ", pattern, " sous ", root_dir)

# ---- 2b. Tri par ordre de création des répertoires pid ----------------------
# list.files() retourne les chemins en ordre alphabétique ; on re-trie ici
# par la date de création (mtime) du répertoire pid correspondant à chaque
# fichier (= premier composant du chemin relatif sous root_dir).
#
# Sur Linux, file.info()$ctime est l'heure de *dernier changement* d'inode,
# pas la naissance réelle. file.info()$mtime (dernière modification du contenu
# du répertoire) est en pratique fixée à la création et constitue le meilleur
# proxy portable. Si votre fs supporte la birth-time (stat --format=%W), vous
# pouvez remplacer "mtime" par la colonne birth ci-dessous.

# 1. Extraire le nom du répertoire pid (1er niveau sous root_dir) par fichier
root_dir_norm <- sub("/*$", "/", root_dir)          # s'assurer du slash final
rel_paths     <- sub(paste0("^", root_dir_norm), "", csv_files)
pid_names     <- vapply(rel_paths,
                        function(p) strsplit(p, "/", fixed = TRUE)[[1L]][1L],
                        character(1L))

# 2. Récupérer les infos des répertoires pid (appel unique à file.info)
pid_full_paths <- file.path(root_dir_norm, pid_names)
pid_info       <- file.info(unique(pid_full_paths))   # une ligne par répertoire unique

# 3. Associer chaque fichier à la mtime de son répertoire pid
pid_mtime <- pid_info[pid_full_paths, "mtime"]        # vecteur de longueur n

# 4. Trier csv_files par mtime croissante (ordre de création des pid dirs)
ord       <- order(pid_mtime)
csv_files <- csv_files[ord]

cat(sprintf("Ordre de fusion : %d répertoires pid distincts (tri par mtime croissant)\n",
            length(unique(pid_names))))


# ---- 2c. Schéma global (union des colonnes) ---------------------------------
# Les exécutions récentes ont ajouté des colonnes (par exemple temporal_cov,
# cross_seed). Les anciens fichiers ne les ont pas. On lit uniquement l'entête
# de chaque fichier (fread nrows = 0, très rapide, gère les guillemets) et on
# construit l'union ordonnée des noms de colonnes. Chaque fichier sera ensuite
# ramené à ce schéma commun : les colonnes absentes sont ajoutées en NA, ce qui
# évite tout décalage lors de l'écriture en append.
get_header <- function(f) {
  tryCatch(names(fread(f, nrows = 0L, showProgress = FALSE)),
           error = function(e) character(0L))
}

all_cols <- character(0L)
for (f in csv_files) {
  h <- get_header(f)
  new_cols <- setdiff(h, all_cols)
  if (length(new_cols)) all_cols <- c(all_cols, new_cols)
}
cat(sprintf("Schéma global : %d colonnes distinctes\n", length(all_cols)))

# Ramène une table au schéma global : ajoute les colonnes manquantes en NA
# puis réordonne. L'alignement se fait par NOM, jamais par position.
align_to_schema <- function(dt, cols) {
  miss <- setdiff(cols, names(dt))
  if ("cross_seed"   %in% miss) dt[, cross_seed   := FALSE]
  if ("temporal_cov" %in% miss) dt[, temporal_cov := TRUE]
  if ("feature_set" %in% miss) dt[, feature_set := "full"]
  if ("n_features_reduced" %in% miss) dt[, n_features_reduced := 0]
  other <- setdiff(miss, c("cross_seed", "temporal_cov", "feature_set", "n_features_reduced"))
  if (length(other)) dt[, (other) := NA]
  setcolorder(dt, cols)
  dt
}

# ---- 3. Streaming en append --------------------------------------------------
# On écrit chaque batch en append dans le fichier final.
# -> I/O totales : O(N) lignes lues + O(N) lignes écrites, contre O(N^2) avant.
out_file       <- sprintf("final_data_%s_%s.csv", ipaddr, start_time)
if (file.exists(out_file)) file.remove(out_file)
header_written <- FALSE

read_one <- function(f) {
  dt <- tryCatch(
    fread(f, showProgress = FALSE, fill = TRUE),
    error = function(e) {
      warning("Lecture impossible : ", f, " — ", conditionMessage(e),
              call. = FALSE)
      NULL
    }
  )
  if (is.null(dt) || nrow(dt) == 0L) return(NULL)
  # Normalisation du champ size_group si présent et mal typé
  if ("size_group" %in% names(dt) && is.character(dt$size_group)) {
    dt[, size_group := -1L]
  }
  dt <- align_to_schema(dt, all_cols)   # colonnes manquantes ajoutées en NA
  unique(dt, fromLast = TRUE)   # garde la DERNIÈRE occurrence en cas de doublon
}


n_batches <- (n - 1L) %/% batch_size + 1L
for (i in seq(1L, n, by = batch_size)) {
  idx <- i:min(i + batch_size - 1L, n)
  cat(sprintf("Batch %d/%d  (%d fichiers)\n",
              (i - 1L) %/% batch_size + 1L, n_batches, length(idx)))
  
  batch <- rbindlist(
    lapply(csv_files[idx], read_one),
    fill = TRUE, use.names = TRUE
  )
  if (nrow(batch) == 0L) next
  batch <- unique(batch, fromLast = TRUE)   # garde la DERNIÈRE occurrence
  
  fwrite(batch, out_file,
         append = header_written,
         col.names = !header_written)
  header_written <- TRUE
}


# ---- 4. Dédoublonnage final --------------------------------------------------
# Une seule relecture, contre une par batch dans la version précédente.
final <- unique(fread(out_file, showProgress = FALSE, fill = TRUE), fromLast = TRUE)  # garde la DERNIÈRE
fwrite(final, out_file)

cat(sprintf("Terminé. Sortie : %s  (%d lignes uniques)\n",
            out_file, nrow(final)))
# # Exemple d'utilisation
# start_time <- as.POSIXct(format(Sys.time(), "%Y-%m-%d %H:%M:%OS6"))
# ipaddr <- getip("internal")
# root_directory <- paste0(ipaddr,"/")
# final_data <- process_csv_files_in_batches(root_directory)
# 
# # Sauvegarder le résultat final
# write.table(final_data, paste0("final_data_", ipaddr,"_", start_time, ".csv"), row.names = FALSE, sep = ",")
# 
# # Afficher les premières lignes du résultat
# head(final_data)
