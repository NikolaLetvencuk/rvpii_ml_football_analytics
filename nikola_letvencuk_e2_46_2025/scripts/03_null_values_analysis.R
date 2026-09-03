library(sparklyr); library(dplyr)
PROJEKAT <- normalizePath(".", winslash = "/", mustWork = TRUE)
sp <- function(p) paste0("file:///", file.path(PROJEKAT, p, fsep = "/"))
conf <- spark_config(); conf$`sparklyr.shell.driver-memory` <- "8G"
sc <- spark_connect(master = "local[*]", version = "3.5", config = conf)
ev <- spark_read_parquet(sc, "ev_p", sp("data/interim/events_flat"))

cols <- colnames(ev)
na_sql <- paste(sprintf("SUM(CASE WHEN %s IS NULL THEN 1 ELSE 0 END) AS %s", cols, cols),
                collapse = ", ")
na_prof <- sdf_sql(sc, sprintf("SELECT COUNT(*) AS n_total, %s FROM ev_p", na_sql)) %>% collect()

n_tot <- na_prof$n_total
na_tbl <- data.frame(
  kolona = cols,
  n_na   = as.numeric(na_prof[1, cols]),
  pct_na = round(100 * as.numeric(na_prof[1, cols]) / n_tot, 1)
)
na_tbl <- na_tbl[order(-na_tbl$pct_na), ]
print(na_tbl, row.names = FALSE)

sdf_sql(sc, "
  SELECT CASE WHEN event_type='Pass' THEN 'Pass' ELSE 'ostalo' END AS grupa,
         COUNT(*) AS n,
         SUM(CASE WHEN pass_outcome IS NULL THEN 1 ELSE 0 END) AS n_null,
         ROUND(100.0*SUM(CASE WHEN pass_outcome IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_null
  FROM ev_p GROUP BY 1") %>% collect() %>% print()

ev %>% filter(!is.na(pass_outcome)) %>% count(pass_outcome, sort = TRUE) %>% collect() %>% print()

sdf_sql(sc, "
  SELECT event_type, COUNT(*) AS n,
    ROUND(100.0*SUM(CASE WHEN shot_xg   IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_na_xg,
    ROUND(100.0*SUM(CASE WHEN loc_x     IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_na_loc,
    ROUND(100.0*SUM(CASE WHEN player_id IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_na_player
  FROM ev_p GROUP BY event_type ORDER BY n DESC") %>% collect() %>% print(n = 40)

ev %>% filter(is.na(player_id)) %>% count(event_type, sort = TRUE) %>% collect() %>% print()

spark_disconnect(sc)