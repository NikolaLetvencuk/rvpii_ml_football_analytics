# =============================================================
#  INPUT : data/raw/statsbomb/events/*.json
#  OUTPUT: data/interim/events_flat/        (Parquet, L1)
#          data/interim/player_features/    (Parquet, L2)
#          data/processed/player_features_spark.csv
#
#  Key: player_id + team
# =============================================================

library(sparklyr)
library(dplyr)

PROJEKAT <- normalizePath(".", winslash = "/", mustWork = TRUE)
sp <- function(p) paste0("file:///", file.path(PROJEKAT, p, fsep = "/"))

EVENTS      <- "data/raw/statsbomb/events"
OUT_L1      <- "data/interim/events_flat"
OUT_L2      <- "data/interim/player_features"
OUT_CSV     <- "data/processed/player_features_spark.csv"
MIN_MINUTES <- 450

dir.create("data/interim",  recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)


# --- 1. Konekcija ----------------------------------------------
conf <- spark_config()
conf$`sparklyr.shell.driver-memory` <- "8G"
conf$`spark.driver.maxResultSize`   <- "2G"
conf$spark.sql.shuffle.partitions   <- 32
sc <- spark_connect(master = "local[*]", version = "3.5", config = conf)

cat("Spark", as.character(spark_version(sc)), "| jezgara:", parallel::detectCores(), "\n")

# --- 2. Ucitavanje JSON-a --------------------------------------
t_read <- system.time({
  spark_read_json(sc, "raw", sp(EVENTS),
                  options = list(multiLine = "true"), memory = FALSE)
  
  DBI::dbExecute(sc, "
    CREATE OR REPLACE TEMP VIEW raw_id AS
    SELECT *,
           CAST(regexp_extract(input_file_name(), '([0-9]+)\\\\.json$', 1) AS INT) AS match_id
    FROM raw")
  
  DBI::dbExecute(sc, "
    CREATE OR REPLACE TEMP VIEW ev AS
    SELECT
      match_id,
      minute, second,
      type.name                        AS event_type,
      player.id                        AS player_id,
      player.name                      AS player_name,
      team.name                        AS team_name,
      position.name                    AS position_name,
      pass.outcome.name                AS pass_outcome,
      pass.length                      AS pass_length,
      pass.goal_assist                 AS pass_goal_assist,
      pass.shot_assist                 AS pass_shot_assist,
      shot.statsbomb_xg                AS shot_xg,
      shot.outcome.name                AS shot_outcome,
      dribble.outcome.name             AS dribble_outcome,
      duel.type.name                   AS duel_type,
      location[0]                      AS loc_x,
      location[1]                      AS loc_y
    FROM raw_id")
  
  spark_write_parquet(tbl(sc, "ev"), sp(OUT_L1), mode = "overwrite")
})
cat("Ucitavanje + Parquet:", round(t_read[["elapsed"]], 1), "s\n")

ev <- spark_read_parquet(sc, "ev_p", sp(OUT_L1))
cat("Dogadjaja:", sdf_nrow(ev), "| utakmica:",
    ev %>% summarise(n = n_distinct(match_id)) %>% pull(n), "\n")


# --- 3. Minuti po utakmici -------------------------------------
# Ista logika kao u staroj skripti:
#   kraj utakmice = max(minute) medju "Half End" dogadjajima
#   starteri      = ceo mec
#   izasli        = do minuta zamene
#   usli          = od minuta zamene do kraja

DBI::dbExecute(sc, "
  CREATE OR REPLACE TEMP VIEW match_end AS
  SELECT match_id, MAX(minute + second/60.0) AS end_min
  FROM raw_id WHERE type.name = 'Half End'
  GROUP BY match_id")

DBI::dbExecute(sc, "
  CREATE OR REPLACE TEMP VIEW starters AS
  SELECT r.match_id, p.player.id AS player_id, r.team.name AS team_name
  FROM raw_id r
  LATERAL VIEW explode(r.tactics.lineup) lu AS p
  WHERE r.type.name = 'Starting XI'")

DBI::dbExecute(sc, "
  CREATE OR REPLACE TEMP VIEW subs AS
  SELECT match_id,
         player.id                     AS off_id,
         substitution.replacement.id   AS on_id,
         team.name                     AS team_name,
         minute + second/60.0          AS sub_min
  FROM raw_id WHERE type.name = 'Substitution'")

DBI::dbExecute(sc, "
  CREATE OR REPLACE TEMP VIEW minutes_match AS
  SELECT s.match_id, s.player_id, s.team_name,
         COALESCE(sb.sub_min, m.end_min) AS mins
  FROM starters s
  JOIN match_end m ON m.match_id = s.match_id
  LEFT JOIN subs sb ON sb.match_id = s.match_id AND sb.off_id = s.player_id
  UNION ALL
  SELECT sb.match_id, sb.on_id AS player_id, sb.team_name,
         m.end_min - sb.sub_min AS mins
  FROM subs sb
  JOIN match_end m ON m.match_id = sb.match_id")

DBI::dbExecute(sc, "
  CREATE OR REPLACE TEMP VIEW minutes_total AS
  SELECT player_id, team_name, SUM(mins) AS minutes
  FROM minutes_match
  GROUP BY player_id, team_name")


# --- 4. Modalna pozicija (po igracu i timu) --------------------
DBI::dbExecute(sc, "
  CREATE OR REPLACE TEMP VIEW pos_rank AS
  SELECT player_id, team_name, position_name, cnt, total,
         ROW_NUMBER() OVER (PARTITION BY player_id, team_name ORDER BY cnt DESC) AS rk
  FROM (
    SELECT player_id, team_name, position_name,
           COUNT(*) AS cnt,
           SUM(COUNT(*)) OVER (PARTITION BY player_id, team_name) AS total
    FROM ev_p
    WHERE player_id IS NOT NULL AND position_name IS NOT NULL
    GROUP BY player_id, team_name, position_name)")

DBI::dbExecute(sc, "
  CREATE OR REPLACE TEMP VIEW positions AS
  SELECT player_id, team_name,
         position_name              AS position,
         ROUND(cnt / total, 3)      AS pos_purity
  FROM pos_rank WHERE rk = 1")


# --- 5. Brojaci dogadjaja --------------------------------------
DBI::dbExecute(sc, "
  CREATE OR REPLACE TEMP VIEW counts AS
  SELECT
    player_id,
    team_name,
    MAX(player_name) AS player,
    SUM(CASE WHEN event_type='Pass' THEN 1 ELSE 0 END)                                AS passes,
    SUM(CASE WHEN event_type='Pass' AND pass_outcome IS NULL THEN 1 ELSE 0 END)       AS passes_completed,
    SUM(CASE WHEN event_type='Pass' AND pass_length >= 30 THEN 1 ELSE 0 END)          AS long_passes,
    SUM(CASE WHEN pass_shot_assist = true THEN 1 ELSE 0 END)                          AS key_passes,
    SUM(CASE WHEN pass_goal_assist = true THEN 1 ELSE 0 END)                          AS assists,
    SUM(CASE WHEN event_type='Carry' THEN 1 ELSE 0 END)                               AS carries,
    SUM(CASE WHEN event_type='Shot' THEN 1 ELSE 0 END)                                AS shots,
    SUM(CASE WHEN shot_outcome='Goal' THEN 1 ELSE 0 END)                              AS goals,
    SUM(COALESCE(shot_xg, 0))                                                         AS xg,
    SUM(CASE WHEN event_type='Dribble' THEN 1 ELSE 0 END)                             AS dribbles,
    SUM(CASE WHEN event_type='Dribble' AND dribble_outcome='Complete' THEN 1 ELSE 0 END) AS dribbles_completed,
    SUM(CASE WHEN event_type='Pressure' THEN 1 ELSE 0 END)                            AS pressures,
    SUM(CASE WHEN event_type='Ball Recovery' THEN 1 ELSE 0 END)                       AS ball_recoveries,
    SUM(CASE WHEN event_type='Interception' THEN 1 ELSE 0 END)                        AS interceptions,
    SUM(CASE WHEN event_type='Clearance' THEN 1 ELSE 0 END)                           AS clearances,
    SUM(CASE WHEN event_type='Block' THEN 1 ELSE 0 END)                               AS blocks,
    SUM(CASE WHEN event_type='Duel' THEN 1 ELSE 0 END)                                AS duels,
    SUM(CASE WHEN event_type='Duel' AND duel_type='Tackle' THEN 1 ELSE 0 END)         AS tackles,
    SUM(CASE WHEN event_type='Foul Committed' THEN 1 ELSE 0 END)                      AS fouls,
    SUM(CASE WHEN event_type='Dispossessed' THEN 1 ELSE 0 END)                        AS dispossessed,
    SUM(CASE WHEN event_type='Miscontrol' THEN 1 ELSE 0 END)                          AS miscontrols,
    SUM(CASE WHEN event_type='Ball Receipt*' THEN 1 ELSE 0 END)                       AS ball_receipts,
    SUM(CASE WHEN event_type='Pass' THEN COALESCE(pass_length,0) ELSE 0 END)          AS pass_length_sum,
    AVG(loc_x)                                                                        AS mean_x,
    AVG(loc_y)                                                                        AS mean_y,
    STDDEV(loc_x)                                                                     AS sd_x,
    STDDEV(loc_y)                                                                     AS sd_y,
    SUM(CASE WHEN loc_x >= 80 THEN 1 ELSE 0 END)                                      AS touches_f3,
    SUM(CASE WHEN loc_x <= 40 THEN 1 ELSE 0 END)                                      AS touches_d3,
    COUNT(*)                                                                          AS n_events
  FROM ev_p
  WHERE player_id IS NOT NULL
  GROUP BY player_id, team_name")


# --- 6. Spajanje + normalizacija na 90 minuta ------------------
cnt_fields <- c("passes","passes_completed","long_passes","key_passes","assists",
                "carries","shots","goals","xg","dribbles","dribbles_completed",
                "pressures","ball_recoveries","interceptions","clearances",
                "blocks","duels","tackles","fouls","dispossessed","miscontrols",
                "ball_receipts")

p90_sql <- paste(sprintf("ROUND(c.%s / m.minutes * 90, 3) AS %s_p90", cnt_fields, cnt_fields),
                 collapse = ",\n    ")

final_sql <- sprintf("
  SELECT
    c.player_id, c.player, c.team_name AS team,
    p.position, p.pos_purity,
    ROUND(m.minutes, 1) AS minutes,
    %s,
    ROUND(c.passes_completed   / GREATEST(c.passes, 1),   3) AS pass_completion_pct,
    ROUND(c.dribbles_completed / GREATEST(c.dribbles, 1), 3) AS dribble_success_pct,
    ROUND(c.pass_length_sum    / GREATEST(c.passes, 1),   2) AS avg_pass_length,
    ROUND(c.mean_x, 2) AS mean_x, ROUND(c.mean_y, 2) AS mean_y,
    ROUND(c.sd_x, 2)   AS sd_x,   ROUND(c.sd_y, 2)   AS sd_y,
    ROUND(c.touches_f3 / c.n_events, 3) AS f3_share,
    ROUND(c.touches_d3 / c.n_events, 3) AS d3_share
  FROM counts c
  JOIN minutes_total m ON m.player_id = c.player_id AND m.team_name = c.team_name
  LEFT JOIN positions p ON p.player_id = c.player_id AND p.team_name = c.team_name
  WHERE m.minutes >= %d", p90_sql, MIN_MINUTES)

t_agg <- system.time({
  feat <- sdf_sql(sc, final_sql)
  spark_write_parquet(sdf_repartition(feat, 1), sp(OUT_L2), mode = "overwrite")
})
cat("Agregacija:", round(t_agg[["elapsed"]], 1), "s\n")


# --- 7. Prikupljanje u R i CSV ---------------------------------
d <- collect(spark_read_parquet(sc, "l2", sp(OUT_L2)))
write.csv(d, OUT_CSV, row.names = FALSE)

cat(sprintf("\nSacuvano: %s  (%d redova x %d kolona)\n", OUT_CSV, nrow(d), ncol(d)))
cat("Ukupno vreme:", round(t_read[["elapsed"]] + t_agg[["elapsed"]], 1), "s\n\n")

cat("Raspodela pozicija:\n"); print(sort(table(d$position), decreasing = TRUE))
cat("\nMinuti:\n"); print(summary(d$minutes))
cat("\nTop 6 po minutima:\n")
print(head(d[order(-d$minutes), c("player","team","position","minutes",
                                  "passes_p90","shots_p90","tackles_p90",
                                  "pass_completion_pct")], 6))

spark_disconnect(sc)