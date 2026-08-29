# ============================================================
#  main.R  --  ULAZNA TACKA PROJEKTA (ekvivalent Main.java)
# ============================================================
#  Ovde se NE pise logika. Ovde se samo:
#    1) ucitavaju sve funkcije iz R/
#    2) pozivaju skripte iz scripts/ u ispravnom redosledu
#
#  Pokretanje iz terminala:  Rscript main.R
#  Pokretanje iz RStudija:   source("main.R")
# ============================================================

# --- 1. Ucitavanje svih funkcija (nista se ne izvrsava, samo se definise) ---
for (f in list.files("R", pattern = "[.][Rr]$", full.names = TRUE)) {
  source(f, encoding = "UTF-8")
}

# --- 2. Pipeline ------------------------------------------------------------
# Zakomentarisi korak koji ne zelis da ponovo izvrsavas (npr. klasifikacija
# traje dugo, a rezultati su vec sacuvani u outputs/models/).

source("scripts/01_priprema_podataka.R",   encoding = "UTF-8")  # [3p]
source("scripts/02_preliminarna_analiza.R", encoding = "UTF-8")  # [3p]
source("scripts/03_klasifikacija.R",        encoding = "UTF-8")  # [15p]
source("scripts/04_klasterizacija.R",       encoding = "UTF-8")  # [6p]
source("scripts/05_render_izvestaj.R",      encoding = "UTF-8")  # [3p]

message("\n=== Pipeline zavrsen ===")
