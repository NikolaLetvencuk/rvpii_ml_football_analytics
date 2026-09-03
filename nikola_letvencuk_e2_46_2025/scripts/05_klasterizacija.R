# ============================================================
#  04  KLASTERIZACIJA  [6p]
# ------------------------------------------------------------
#  ULAZ:   data/processed/analiticki_skup
#  IZLAZ:  outputs/models/kmeans_*.rds, outputs/tables/profil_klastera.csv,
#          outputs/figures/klasteri_*.png
#
#  Metod: k-Means (jedan metod je dovoljan po specifikaciji).
#
#  Zadaci:
#    - klasteri za razlicite vrednosti parametara prema DVA scenarija
#      (npr. scenario A = razlicite vrednosti k; scenario B = drugi skup
#       obelezja ili drugacija normalizacija)
#    - ispitivanje strukture dobijenih klastera
#    - vizualizacija odnosa vrednosti obelezja i pripadnosti klasteru
# ============================================================

set.seed(SEED)

# 1. izbor i skaliranje numerickih obelezja

# 2. scenario A: k = 2..8  -> metod lakta + silueta

# 3. scenario B: drugaciji skup obelezja / normalizacija

# 4. struktura: velicina klastera + profil (srednje vrednosti po klasteru)

# 5. vizualizacija (PCA projekcija, boxplot po klasteru, mapa)
