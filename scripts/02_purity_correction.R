library(sparklyr); library(dplyr)

PROJEKAT <- normalizePath(".", winslash = "/", mustWork = TRUE)
sp <- function(p) paste0("file:///", file.path(PROJEKAT, p, fsep = "/"))

conf <- spark_config()
conf$`sparklyr.shell.driver-memory` <- "8G"
conf$`spark.driver.maxResultSize`   <- "2G"
conf$spark.sql.shuffle.partitions   <- 32

sc <- spark_connect(master = "local[*]", version = "3.5", config = conf)
ev <- spark_read_parquet(sc, "ev_p", sp("data/interim/events_flat"))

DBI::dbExecute(sc, "
  CREATE OR REPLACE TEMP VIEW grp AS
  SELECT player_id, team_name,
    CASE
      WHEN position_name = 'Goalkeeper' THEN 'GK'
      WHEN position_name IN ('Right Center Back','Left Center Back','Center Back') THEN 'CB'
      WHEN position_name IN ('Left Back','Right Back','Left Wing Back','Right Wing Back') THEN 'FB'
      WHEN position_name IN ('Right Defensive Midfield','Left Defensive Midfield',
                             'Center Defensive Midfield','Right Center Midfield',
                             'Left Center Midfield') THEN 'DM_CM'
      WHEN position_name IN ('Right Wing','Left Wing','Center Attacking Midfield',
                             'Right Attacking Midfield','Right Midfield','Left Midfield') THEN 'AM_W'
      WHEN position_name IN ('Center Forward','Right Center Forward','Left Center Forward') THEN 'FW'
    END AS pos_grp
  FROM ev_p WHERE player_id IS NOT NULL AND position_name IS NOT NULL")

purity6 <- sdf_sql(sc, "
  SELECT player_id, team_name, pos_grp AS position_group6,
         ROUND(cnt/total, 3) AS purity6
  FROM (SELECT player_id, team_name, pos_grp, COUNT(*) AS cnt,
               SUM(COUNT(*)) OVER (PARTITION BY player_id, team_name) AS total,
               ROW_NUMBER() OVER (PARTITION BY player_id, team_name ORDER BY COUNT(*) DESC) AS rk
        FROM grp GROUP BY player_id, team_name, pos_grp)
  WHERE rk = 1") %>% collect()

summary(purity6$purity6); sum(purity6$purity6 < 0.5)

d <- read.csv("data/processed/player_features_spark.csv", stringsAsFactors = FALSE)

map6 <- c(
  "Goalkeeper" = "GK",
  "Right Center Back" = "CB", "Left Center Back" = "CB", "Center Back" = "CB",
  "Left Back" = "FB", "Right Back" = "FB",
  "Left Wing Back" = "FB", "Right Wing Back" = "FB",
  "Right Defensive Midfield" = "DM_CM", "Left Defensive Midfield" = "DM_CM",
  "Center Defensive Midfield" = "DM_CM",
  "Right Center Midfield" = "DM_CM", "Left Center Midfield" = "DM_CM",
  "Right Wing" = "AM_W", "Left Wing" = "AM_W",
  "Center Attacking Midfield" = "AM_W", "Right Attacking Midfield" = "AM_W",
  "Right Midfield" = "AM_W", "Left Midfield" = "AM_W",
  "Center Forward" = "FW", "Right Center Forward" = "FW", "Left Center Forward" = "FW"
)

d$position_group <- factor(map6[d$position],
                           levels = c("GK","CB","FB","DM_CM","AM_W","FW"))
stopifnot(!any(is.na(d$position_group)))

d <- merge(d, purity6[, c("player_id","team_name","purity6")],
           by.x = c("player_id","team"), by.y = c("player_id","team_name"),
           all.x = TRUE)

write.csv(d, "data/processed/player_features_labeled.csv", row.names = FALSE)

table(d$position_group)
sum(is.na(d$purity6))
d[which(d$purity6 < 0.5), c("player","team","position","position_group","purity6","minutes")]