# ---- Jednokratna instalacija paketa -----------------------------------------
# Pokreni JEDNOM:  Rscript scripts/00_instaliraj_pakete.R
# Ovo NIJE deo pipeline-a (main.R ga ne poziva).

paketi <- c(
  # rad sa velikim podacima
  # R.utils je OBAVEZAN da bi fread() citao .csv.gz direktno
  "data.table", "R.utils", "arrow", "fst",
  # transformacije i grafika
  "dplyr", "tidyr", "stringr", "lubridate", "ggplot2", "scales", "patchwork",
  # modelovanje
  # NAPOMENA: paket `vip` (grafici vaznosti obelezja) nije dostupan za R 4.6.
  # Zameni ga ugradjenim mehanizmima:
  #   ranger:  ranger(..., importance = "permutation") -> model$variable.importance
  #   xgboost: xgboost::xgb.importance(model = m)
  "tidymodels", "ranger", "xgboost", "e1071", "kernlab",
  # klasterizacija
  "cluster", "factoextra",
  # paralelizacija (HPC deo predmeta)
  "future", "doFuture", "parallelly",
  # izvestavanje
  "rmarkdown", "knitr", "kableExtra", "DT",
  # testiranje
  "testthat"
)

nedostaju <- setdiff(paketi, rownames(installed.packages()))
if (length(nedostaju)) {
  install.packages(nedostaju, repos = "https://cloud.r-project.org")
} else {
  message("Svi paketi su vec instalirani.")
}
