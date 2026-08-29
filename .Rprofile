# Ucitava se automatski pri svakom startu R-a u ovom projektu.
# Ovde ide SAMO podesavanje sesije -- nikakva analiza.

options(
  stringsAsFactors = FALSE,
  scipen           = 999,          # bez eksponencijalne notacije u ispisu
  digits           = 4,
  repos            = c(CRAN = "https://cloud.r-project.org"),
  datatable.print.class = TRUE
)

# Veliki fajlovi -> dozvoli data.table da koristi sve jezgra osim jednog
if (requireNamespace("data.table", quietly = TRUE)) {
  data.table::setDTthreads(max(1L, parallel::detectCores() - 1L))
}

if (interactive()) {
  message("Projekat: Smestaj (Airbnb) | radni direktorijum: ", getwd())
}
