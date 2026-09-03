# ============================================================
#  01  PRIPREMA PODATAKA  [3p]
# ------------------------------------------------------------
#  ULAZ:   data/raw/*.csv.gz
#  IZLAZ:  data/processed/analiticki_skup.fst  (ili .rds)
#
#  Zadaci iz specifikacije:
#    - ucitavanje podataka
#    - uredjivanje ucitanih podataka
#    - ispitivanje prisustva nedostajucih vrednosti
#
#  Ovde pises POZIVE funkcija iz R/01_ucitavanje.R i R/02_ciscenje.R.
#  Ako pises `function(...)` -- na pogresnom si mestu, to ide u R/.
# ============================================================

library(data.table)

# 1. ucitavanje

# 2. uredjivanje (tipovi, parsiranje cene, izvedena obelezja)

# 3. nedostajuce vrednosti -> tabela u outputs/tables/ za izvestaj

# 4. snimanje analitickog skupa u data/processed/
