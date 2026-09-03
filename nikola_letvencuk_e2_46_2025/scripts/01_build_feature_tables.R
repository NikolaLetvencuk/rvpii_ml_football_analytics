# INPUT : data/raw/statsbomb/events/*
# OUTPUT: data/processed/player_features.csv
#
# One row per player with >= MIN_MINUTES minutes played.
# Numeric per-90 columns for clustering.

if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite")
if (!requireNamespace("dplyr", quietly = TRUE))    install.packages("dplyr")
library(jsonlite)
library(dplyr)

events_dir <- file.path("data", "raw", "statsbomb", "events")
out_dir    <- file.path("data", "processed")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

MIN_MINUTES <- 450  

files <- list.files(events_dir, pattern = "\\.json$", full.names = TRUE)
cat(sprintf("Found %d event files.\n", length(files)))

S <- new.env()
S$acc         <- list()
S$pos_count   <- list()
S$player_name <- list()
S$player_team <- list()

g <- function(x, ...) {
  for (k in c(...)) {
    if (is.null(x) || is.null(x[[k]])) return(NA)
    x <- x[[k]]
  }
  x
}

add <- function(pid, field, by = 1) {
  a <- S$acc[[pid]]; if (is.null(a)) a <- list()
  cur <- a[[field]]
  a[[field]] <- (if (is.null(cur)) 0 else cur) + by
  S$acc[[pid]] <- a
}

nrow_or_len <- function(x) if (is.data.frame(x)) nrow(x) else length(x)
get_row     <- function(x, i) if (is.data.frame(x)) as.list(x[i, ]) else x[[i]]

match_minutes <- function(events) {
  he <- Filter(function(e) e$type$name == "Half End", events)
  if (length(he) == 0) return(list())
  end_min <- max(sapply(he, function(e) e$minute + e$second / 60))
  mins <- list()
  sxi <- Filter(function(e) e$type$name == "Starting XI", events)
  for (e in sxi) {
    lu <- e$tactics$lineup
    for (i in seq_len(nrow_or_len(lu))) {
      row <- get_row(lu, i)
      mins[[as.character(row$player$id)]] <- end_min
    }
  }
  subs <- Filter(function(e) e$type$name == "Substitution", events)
  for (e in subs) {
    off_pid <- as.character(e$player$id)
    on_pid  <- as.character(e$substitution$replacement$id)
    sub_min <- e$minute + e$second / 60
    if (!is.null(mins[[off_pid]])) mins[[off_pid]] <- sub_min
    mins[[on_pid]] <- end_min - sub_min
  }
  mins
}

process_match <- function(path) {
  events <- fromJSON(path, simplifyVector = FALSE)
  mins <- match_minutes(events)
  for (e in events) {
    pid_raw <- g(e, "player", "id"); if (is.na(pid_raw)) next
    pid <- as.character(pid_raw)
    
    if (is.null(S$player_name[[pid]])) S$player_name[[pid]] <- g(e, "player", "name")
    tm <- g(e, "team", "name"); if (!is.na(tm)) S$player_team[[pid]] <- tm
    
    pos <- g(e, "position", "name")
    if (!is.na(pos)) {
      pv <- S$pos_count[[pid]]; if (is.null(pv)) pv <- c()
      prev <- pv[pos]
      pv[pos] <- (if (length(prev) == 0 || is.na(prev)) 0 else prev) + 1
      S$pos_count[[pid]] <- pv
    }
    
    et <- e$type$name
    if (et == "Pass") {
      add(pid, "passes")
      if (is.na(g(e, "pass", "outcome", "name"))) add(pid, "passes_completed")
      len <- g(e, "pass", "length")
      if (!is.na(len)) { add(pid, "pass_length_sum", by = len); if (len >= 30) add(pid, "long_passes") }
      if (isTRUE(g(e, "pass", "goal_assist"))) add(pid, "assists")
      if (isTRUE(g(e, "pass", "shot_assist"))) add(pid, "key_passes")
    } else if (et == "Carry") { add(pid, "carries")
    } else if (et == "Shot") {
      add(pid, "shots")
      xg <- g(e, "shot", "statsbomb_xg"); if (!is.na(xg)) add(pid, "xg", by = xg)
      if (identical(g(e, "shot", "outcome", "name"), "Goal")) add(pid, "goals")
    } else if (et == "Dribble") {
      add(pid, "dribbles")
      if (identical(g(e, "dribble", "outcome", "name"), "Complete")) add(pid, "dribbles_completed")
    } else if (et == "Pressure") { add(pid, "pressures")
    } else if (et == "Ball Recovery") { add(pid, "ball_recoveries")
    } else if (et == "Interception") { add(pid, "interceptions")
    } else if (et == "Clearance") { add(pid, "clearances")
    } else if (et == "Block") { add(pid, "blocks")
    } else if (et == "Duel") {
      add(pid, "duels")
      if (identical(g(e, "duel", "type", "name"), "Tackle")) add(pid, "tackles")
    } else if (et == "Foul Committed") { add(pid, "fouls")
    } else if (et == "Dispossessed") { add(pid, "dispossessed")
    } else if (et == "Miscontrol") { add(pid, "miscontrols")
    } else if (et == "Ball Receipt*") { add(pid, "ball_receipts") }
  }
  for (pid in names(mins)) add(pid, "minutes", by = mins[[pid]])
}

t0 <- Sys.time()
for (i in seq_along(files)) {
  process_match(files[i])
  if (i %% 20 == 0)
    cat(sprintf("  processed %d/%d (%.0fs)\n", i, length(files),
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}
cat("Done processing. Building table...\n")

count_fields <- c("passes","passes_completed","long_passes","key_passes","assists",
                  "carries","shots","goals","xg","dribbles","dribbles_completed",
                  "pressures","ball_recoveries","interceptions","clearances",
                  "blocks","duels","tackles","fouls","dispossessed","miscontrols",
                  "ball_receipts")

rows <- lapply(names(S$acc), function(pid) {
  a <- S$acc[[pid]]
  get <- function(f) if (is.null(a[[f]])) 0 else a[[f]]
  pv <- S$pos_count[[pid]]
  base <- data.frame(
    player_id  = pid,
    player     = if (is.null(S$player_name[[pid]])) NA else S$player_name[[pid]],
    team       = if (is.null(S$player_team[[pid]])) NA else S$player_team[[pid]],
    position   = if (is.null(pv)) NA else names(which.max(pv)),
    pos_purity = if (is.null(pv)) NA else round(max(pv) / sum(pv), 3),
    minutes    = round(get("minutes"), 1),
    pass_length_sum = get("pass_length_sum"),
    stringsAsFactors = FALSE
  )
  cbind(base, setNames(as.data.frame(as.list(sapply(count_fields, get))), count_fields))
})
df <- bind_rows(rows)

df <- df[df$minutes >= MIN_MINUTES, ]
cat(sprintf("Players with >= %d minutes: %d\n", MIN_MINUTES, nrow(df)))

per90 <- df[, c("player_id","player","team","position","pos_purity","minutes")]
for (f in count_fields)
  per90[[paste0(f, "_p90")]] <- round(df[[f]] / df$minutes * 90, 3)

per90$pass_completion_pct <- round(df$passes_completed / pmax(df$passes, 1), 3)
per90$dribble_success_pct <- round(df$dribbles_completed / pmax(df$dribbles, 1), 3)
per90$avg_pass_length     <- round(df$pass_length_sum / pmax(df$passes, 1), 2)

out_path <- file.path(out_dir, "player_features.csv")
write.csv(per90, out_path, row.names = FALSE)

cat(sprintf("\nSaved feature table: %s  (%d players x %d cols)\n",
            out_path, nrow(per90), ncol(per90)))
cat("\nPosition distribution:\n")
print(sort(table(per90$position), decreasing = TRUE))
cat("\nTop-6 by minutes:\n")
print(head(per90[order(-per90$minutes),
                 c("player","position","minutes","passes_p90","shots_p90","tackles_p90","pass_completion_pct")], 6))