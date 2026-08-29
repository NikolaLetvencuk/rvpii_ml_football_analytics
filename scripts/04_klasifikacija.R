# ============================================================
#  03  KLASIFIKACIJA  [15p]  <-- najvredniji deo, ovde je najvise rada
# ------------------------------------------------------------
#  ULAZ:   data/processed/analiticki_skup
#  IZLAZ:  outputs/models/*.rds, outputs/tables/performanse.csv,
#          outputs/figures/performanse_*.png
#
#  Ciljno obelezje: CILJ (= "room_type"), isto za sva tri metoda.
#
#  Zadaci:
#    - 3 metoda x 3 scenarija vrednosti parametara
#    - vise brojcanih pokazatelja performansi (tacnost, preciznost,
#      osetljivost, F-mera, + matrica konfuzije)
#    - unakrsna validacija (CV_K preklopa)
#    - odnos izmedju vrednosti parametara i performansi
#    - izbor resenja PO METODU i NA NIVOU SVIH METODA
# ============================================================

set.seed(SEED)

# 1. podela na trening/test (stratifikovano)

# 2. Random Forest -- scenariji 1..3 (npr. mtry / num.trees / min.node.size)

# 3. XGBoost -- scenariji 1..3 (npr. max_depth / eta / nrounds)

# 4. SVM -- scenariji 1..3 (npr. kernel / C / gamma)

# 5. sve u jednu tabelu: metod | scenario | parametri | metrike (CV + test)

# 6. grafici: parametar vs performansa; poredjenje metoda

# 7. izbor najboljeg po metodu i ukupno + obrazlozenje (tekst ide u izvestaj)
