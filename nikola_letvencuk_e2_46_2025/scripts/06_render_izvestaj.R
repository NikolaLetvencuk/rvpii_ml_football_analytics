# ============================================================
#  05  IZVESTAVANJE  [3p]
# ------------------------------------------------------------
#  Renderuje reports/izvestaj.Rmd -> reports/izvestaj.html
# ============================================================

rmarkdown::render(
  input       = file.path("reports", "izvestaj.Rmd"),
  output_file = "izvestaj.html",
  encoding    = "UTF-8"
)
