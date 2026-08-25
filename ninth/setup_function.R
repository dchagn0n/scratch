# Initialize results dataframe
initialize_dtf <- function() {
  data.table(
    nb_packets = integer(),
    path_length = integer(),
    nb_detour = integer(),
    prop_att = double(),
    size_group = integer(),
    model = character(),
    approach = character(),
    error = double(),
    all_err = double(),
    no_err = double(),
    Recall = double(),
    Precision = double(),
    F1_score = double()
  )
}
# Function to save results efficiently ####
save_results <- function(data, path) {
  if (!file.exists(path)) {
    write.csv(data, path, row.names = FALSE)
  } else {
    write.table(data, path, row.names = FALSE, col.names = FALSE, sep = ",", append = TRUE)
  }
}

# function to move maybe later ####
change_name <- function(nomcol, pre)
{
  if (nomcol %in% col_commun)
  {
    return (nomcol)
  }else{
    if (startsWith(nomcol, "start_") || startsWith(nomcol, "end_")) {
      return(nomcol)  # Ne pas doubler les préfixes
    }
    return (paste0(pre, nomcol))
  }
}

fusion_starttoend<- function(start, end, type)
{
  # Renommer les colonnes
  setnames(start, old = names(start), new = sapply(names(start), change_name, pre = "start_"))
  setnames(end, old = names(end), new = sapply(names(end), change_name, pre = "end_"))
  #names(start) <- sapply(names(start), change_name, pre= "start_")
  #names(end) <- sapply(names(end), change_name, pre= "end_")
  
  # Colonnes à garder dans 'end'
  end_col <- c("end_file", "end_packet_num", "end_timestamp")
  
  # Fusionner les deux tables par colonnes
  res <- cbind(start, end[, ..end_col])
  #res = cbind(start, end[,end_col])
  
  # Ajouter les nouvelles colonnes
  res[, delay_path := end_timestamp - start_timestamp]
  res[, type := type]
  # res$delay_path <- res$end_timestamp - res$start_timestamp
  # res$type <- type
  return (res)
}
do_flowchart_df <- function(tmp_att_bandwidth, nb_hops, nb_att)
{
  # initialisation
  flow_stats <- tmp_att_bandwidth %>%
    select(-c( )) %>%
    separate(hop, into = c("from", "to"), sep = " - linked ", remove = FALSE) %>%
    mutate(
      from = trimws(from), 
      to = trimws(to),
    )
  
  flow_stats[flow_stats$from == "A0" & flow_stats$to == "...","to"] = "D0"
  flow_stats[flow_stats$from == "D0" & flow_stats$to == "...","to"] = "A0"
  
  # initial links
  from = c("A0")
  to = c()
  for (i in seq(0, nb_hops-1, length.out = nb_hops))
  {
    next_hop = paste0("A", i+2)
    to = c(to, next_hop)
    from = c(from, next_hop)
    
  }
  to = c(to, "D0")
  
  from = c(from, "D0")
  to = c(to, "D1")
  from = c(from, "D1")
  to = c(to, "A1")
  
  for (i in seq.int(0, nb_hops-1, length.out = nb_hops))
  {
    next_hop = paste0("A", i+2)
    next_para = paste0("P", i+2)
    from = c(from, next_para)
    to = c(to, next_hop)
  }
  
  from = c(from, "D0")
  to = c(to, "D2")
  from = c(from, "D2")
  for (i in seq(0, nb_att-1, length.out = nb_att ))
  {
    next_hop = paste0("D", i+3)
    to = c(to, next_hop)
    from = c(from, next_hop)
    
  }
  to = c(to, "D1")
  
  for (i in seq.int(0, nb_att-1, length.out = nb_att))
  {
    next_hop = paste0("D", i+3)
    next_para = paste0("E", i+3)
    from = c(from, next_para)
    to = c(to, next_hop)
  }
  
  from = c(from, "E0")
  to = c(to, "D0")
  from = c(from, "E1")
  to = c(to, "D1")
  from = c(from, "E2")
  to = c(to, "D2")
  
  
  links <- data.table(from = from, to = to)
  type_factor = c("Access", rep("Access", nb_hops), "Distribution", "Distribution", rep("Extra", nb_hops), "Distribution", rep("Distribution", nb_att), rep("Extra", nb_att), "Extra", "Extra", "Extra", "Access")
  
  ## graph set up
  g = graph_from_data_frame(links, directed = TRUE)
  coords = layout_nicely(g) #layout_with_sugiyama(g)$layout #layout_on_grid(g) #layout_nicely(g)
  colnames(coords) = c("x", "y")
  
  output_df = as_tibble(coords) %>%
    mutate(step = vertex_attr(g, "name"),
           label = step, #gsub("\\d+$", "", step),
           x = x ,#*-1,
           y = y,
           type = factor(type_factor)
    )
  
  plot_nodes = output_df %>%
    mutate(xmin = x - 0.35,
           xmax = x + 0.35,
           ymin = y - 0.25,
           ymax = y + 0.25)
  
  
  plot_edges = links %>%
    mutate(id = row_number()) %>%
    pivot_longer(cols = c("from", "to"),
                 names_to = "s_e",
                 values_to = "step") %>%
    left_join(plot_nodes, by = "step") %>%
    select(-c(label, type, ymin, ymax)) %>%
    select(-c(xmin, xmax))
  
  plot_edge_segments <- plot_edges %>%
    group_by(id) %>%
    summarise(
      from = step[s_e == "from"],
      to   = step[s_e == "to"],
      x = mean(x),
      y = mean(y),
      .groups = "drop"
    ) 
  
  plot_edge_labels <- plot_edge_segments %>%
    left_join(flow_stats, by = c("from", "to"))%>%
    select(-c(id.y , hop)) %>%
    distinct(from, to, data_rate_Mbps, .keep_all = TRUE)
  
  label_data <- plot_edge_segments %>%
    inner_join(flow_stats, by = c("from", "to")) %>%
    mutate(
      label = paste0(round(data_rate_Mbps, 5), " Mbps (", path, ")"),
      y_offset = case_when(
        is_direct == "TRUE" ~  0.1,
        is_direct == "FALSE" ~ -0.1,
        TRUE             ~  0
      ))%>%
    distinct(from, to, data_rate_Mbps, .keep_all = TRUE)
  
  ## build flowchart
  p = ggplot()
  p = p + 
    geom_text(data = plot_nodes,
              mapping = aes(x = x, y = y+0.1, label = label, colour = type)
    ) 
  p = p + 
    geom_path(data = plot_edges,
              mapping = aes(x = x, y = y, group = id),
              colour = "#585c45",
              arrow = arrow(length = unit(0, "cm"), type = "open"))
  p = p + 
    geom_text(data = label_data,
              mapping = aes(x = x, y = y + y_offset, label = label),
              size = 3, vjust = 2
    )
  p = p + 
    labs(title = "Data Rate on each link",
         caption = "Tuto flowchart: https://www.r-bloggers.com/2022/06/creating-flowcharts-with-ggplot2/") 
  return (p)
}
do_flowchart <- function(tmp_att_bandwidth, nb_hops, nb_att) {
  # Convert to data.table
  setDT(tmp_att_bandwidth)
  
  # Handle 'hop' split into 'from' and 'to'
  tmp_att_bandwidth[, c("from", "to") := tstrsplit(hop, " - linked ", fixed = TRUE)]
  tmp_att_bandwidth[, `:=`(from = str_trim(from), to = str_trim(to))]
  
  # Adjust "..." to proper values
  tmp_att_bandwidth[from == "A0" & to == "...", to := "D0"]
  tmp_att_bandwidth[from == "D0" & to == "...", to := "A0"]
  
  # Initial links
  from <- c("A0")
  to <- character(0)
  for (i in seq(0, nb_hops - 1)) {
    next_hop <- paste0("A", i + 2)
    to <- c(to, next_hop)
    from <- c(from, next_hop)
  }
  to <- c(to, "D0")
  from <- c(from, "D0")
  to <- c(to, "D1")
  from <- c(from, "D1")
  to <- c(to, "A1")
  
  for (i in seq(0, nb_hops - 1)) {
    from <- c(from, paste0("P", i + 2))
    to <- c(to, paste0("A", i + 2))
  }
  
  from <- c(from, "D0")
  to <- c(to, "D2")
  from <- c(from, "D2")
  for (i in seq(0, nb_att - 1)) {
    hop <- paste0("D", i + 3)
    from <- c(from, hop)
    to <- c(to, hop)
  }
  to <- c(to, "D1")
  
  for (i in seq(0, nb_att - 1)) {
    from <- c(from, paste0("E", i + 3))
    to <- c(to, paste0("D", i + 3))
  }
  
  from <- c(from, "E0", "E1", "E2")
  to <- c(to, "D0", "D1", "D2")
  
  links <- data.table(from = from, to = to)
  type_factor <- c("Access", rep("Access", nb_hops), "Distribution", "Distribution", rep("Extra", nb_hops),
                   "Distribution", rep("Distribution", nb_att), rep("Extra", nb_att),
                   "Extra", "Extra", "Extra", "Access")
  
  g <- graph_from_data_frame(links, directed = TRUE)
  coords <- layout_nicely(g)
  setDT(coords)
  setnames(coords, c("x", "y"))
  output_df <- data.table(step = names(V(g)))
  output_df[, `:=`(x = coords$x, y = coords$y, label = step, type = factor(type_factor))]
  
  plot_nodes <- copy(output_df)
  plot_nodes[, `:=`(xmin = x - 0.35, xmax = x + 0.35, ymin = y - 0.25, ymax = y + 0.25)]
  
  plot_edges <- melt(links[, id := .I], measure.vars = c("from", "to"),
                     variable.name = "s_e", value.name = "step")
  plot_edges <- merge(plot_edges, plot_nodes, by = "step", all.x = TRUE)
  plot_edges <- plot_edges[, .(id, x, y)]
  
  plot_edge_segments <- plot_edges[, .(x = mean(x), y = mean(y)), by = id]
  plot_edge_segments[, c("from", "to") := links[id, .(from, to)]]
  
  plot_edge_labels <- merge(plot_edge_segments, tmp_att_bandwidth,
                            by = c("from", "to"), all.x = TRUE)
  label_data <- copy(plot_edge_labels)
  label_data[, `:=`(label = paste0(round(data_rate_Mbps, 5), " Mbps (", path, ")"),
                    y_offset = fifelse(is_direct == "TRUE", 0.1,
                                       fifelse(is_direct == "FALSE", -0.1, 0)))]
  
  p <- ggplot() +
    geom_text(data = plot_nodes, aes(x = x, y = y + 0.1, label = label, colour = type)) +
    geom_path(data = plot_edges, aes(x = x, y = y, group = id),
              colour = "#585c45", arrow = arrow(length = unit(0, "cm"), type = "open")) +
    geom_text(data = label_data, aes(x = x, y = y + y_offset, label = label), size = 3, vjust = 2) +
    labs(title = "Data Rate on each link",
         caption = "Adapted from: https://www.r-bloggers.com/2022/06/creating-flowcharts-with-ggplot2/")
  
  return(p)
}

transform_vector <- function(v) {
  sapply(v, function(x) {
    # Candidates: -1, 1, and nearest multiple of 9
    candidate_9 <- round(x / 9) * 9
    candidates <- c(-1, 1, candidate_9)
    candidates[which.min(abs(x - candidates))]
  })
}


