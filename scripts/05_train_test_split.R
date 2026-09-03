library(sparklyr); library(dplyr)
PROJEKAT <- normalizePath(".", winslash = "/", mustWork = TRUE)
sp <- function(p) paste0("file:///", file.path(PROJEKAT, p, fsep = "/"))
conf <- spark_config(); conf$`sparklyr.shell.driver-memory` <- "8G"
conf$spark.sql.shuffle.partitions <- 32
sc <- spark_connect(master = "local[*]", version = "3.5", config = conf)
set.seed(42)
dir.create("results", showWarnings = FALSE)

d <- read.csv("data/processed/player_features_labeled.csv", stringsAsFactors = FALSE)
num <- setdiff(names(d)[sapply(d, is.numeric)],
               c("player_id","pos_purity","purity6","minutes"))
feat_cols <- setdiff(num, c("passes_completed_p90","dribbles_completed_p90"))
saveRDS(feat_cols, "results/feat_cols.rds"); length(feat_cols)

tbl <- copy_to(sc, d[, c("player","team","position_group", feat_cols)],
               "players", overwrite = TRUE)

strat <- tbl %>%
  group_by(position_group) %>%
  mutate(rk = percent_rank(rand(42L))) %>%
  ungroup()

train <- strat %>% filter(rk <= 0.8) %>% select(-rk) %>% compute("train")
test  <- strat %>% filter(rk >  0.8) %>% select(-rk) %>% compute("test")

train %>% count(position_group) %>% collect() %>% print()
test  %>% count(position_group) %>% collect() %>% print()
sdf_nrow(train); sdf_nrow(test)

spark_write_parquet(train, sp("data/interim/train"), mode = "overwrite")
spark_write_parquet(test,  sp("data/interim/test"),  mode = "overwrite")