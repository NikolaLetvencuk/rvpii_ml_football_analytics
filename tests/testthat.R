# Pokretanje svih testova:  Rscript tests/testthat.R
library(testthat)
for (f in list.files("R", pattern = "[.][Rr]$", full.names = TRUE)) {
  source(f, encoding = "UTF-8")
}
test_dir("tests/testthat")
