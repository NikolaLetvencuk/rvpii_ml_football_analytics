# Data downloade:
# Premier League, La Liga, Ligue 1 and Serie A
# Source: https://github.com/statsbomb/open-data
# License: free for research/personal use, non-commercial,
#          attribution to StatsBomb required in any write-up.

if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite")
library(jsonlite)

base_url <- "https://raw.githubusercontent.com/statsbomb/open-data/master/data"
out_dir <- file.path("data", "raw", "statsbomb")
events_dir <- file.path(out_dir, "events")
matches_dir <- file.path(out_dir, "matches")
dir.create(events_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(matches_dir, recursive = TRUE, showWarnings = FALSE)

target_bytes <- 1 * 1024^3
target_leagues <- c("Premier League", "La Liga", "Ligue 1", "Serie A")

cat("Fetching competitions list...\n")
competitions <- fromJSON(file.path(base_url, "competitions.json"))
cand <- competitions[competitions$competition_name %in% target_leagues, ]

get_match_count <- function(comp_id, season_id) {
  url <- sprintf("%s/matches/%s/%s.json", base_url, comp_id, season_id)
  tryCatch(nrow(fromJSON(url)), error = function(e) NA_integer_)
}

cat("Checking match counts per season (this takes a minute)...\n")
cand$n_matches <- mapply(get_match_count, cand$competition_id, cand$season_id)

best_season <- do.call(rbind, lapply(split(cand, cand$competition_name), function(df) {
  df[which.max(df$n_matches), ]
}))

cat("\nSelected season per league:\n")
print(best_season[, c("competition_name", "season_name", "n_matches")], row.names = FALSE)
cat("\n")

match_lists <- list()
for (i in seq_len(nrow(best_season))) {
  comp_id   <- best_season$competition_id[i]
  season_id <- best_season$season_id[i]
  league    <- best_season$competition_name[i]
  url <- sprintf("%s/matches/%s/%s.json", base_url, comp_id, season_id)
  m <- fromJSON(url, flatten = TRUE)
  m$league <- league
  match_lists[[league]] <- m
}

all_matches_meta <- do.call(rbind, lapply(match_lists, function(m) {
  m[, intersect(c("match_id", "match_date", "kick_off", "league",
                  "home_team.home_team_name", "away_team.away_team_name",
                  "home_score", "away_score", "competition_stage.name",
                  "stadium.name", "referee.name"), names(m))]
}))
write.csv(all_matches_meta, file.path(matches_dir, "all_matches_meta.csv"), row.names = FALSE)
cat(sprintf("Saved match-level metadata for %d matches to matches/all_matches_meta.csv\n\n",
            nrow(all_matches_meta)))

downloaded_bytes <- 0
downloaded_ids <- c()
max_n <- max(sapply(match_lists, nrow))

cat("Downloading event data (round-robin across leagues)...\n")
for (row in seq_len(max_n)) {
  if (downloaded_bytes >= target_bytes) break
  
  for (league in names(match_lists)) {
    if (downloaded_bytes >= target_bytes) break
    
    m <- match_lists[[league]]
    if (row > nrow(m)) next  # this league ran out of matches (Ligue 1 has 377 vs 380)
    
    match_id <- m$match_id[row]
    dest <- file.path(events_dir, paste0(match_id, ".json"))
    if (file.exists(dest)) {
      downloaded_bytes <- downloaded_bytes + file.info(dest)$size
      downloaded_ids   <- c(downloaded_ids, match_id)
      next
    }
    
    ev_url <- sprintf("%s/events/%s.json", base_url, match_id)
    ok <- tryCatch({
      download.file(ev_url, dest, quiet = TRUE, mode = "wb")
      TRUE
    }, error = function(e) FALSE)
    
    fsize <- if (ok && file.exists(dest)) file.info(dest)$size else 0
    if (fsize == 0) {
      unlink(dest)   
    } else {
      downloaded_bytes <- downloaded_bytes + fsize
      downloaded_ids <- c(downloaded_ids, match_id)
      cat(sprintf("  [%-15s] match %s  (running total: %.1f MB)\n",
                  league, match_id, downloaded_bytes / 1024^2))
    }
    Sys.sleep(0.05)  
  }
}

cat(sprintf("\nDone. Downloaded %d matches, %.2f GB total, saved in '%s/events/'.\n",
            length(downloaded_ids), downloaded_bytes / 1024^3, out_dir))

manifest <- all_matches_meta[all_matches_meta$match_id %in% downloaded_ids, ]
write.csv(manifest, file.path(out_dir, "downloaded_matches_manifest.csv"), row.names = FALSE)
cat(sprintf("Manifest of downloaded matches (with league/team/score) saved to '%s'.\n",
            file.path(out_dir, "downloaded_matches_manifest.csv")))