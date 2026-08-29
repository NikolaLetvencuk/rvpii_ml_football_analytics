# ---- Klasterizacija: k-Means, 2 scenarija [6p] ------------------------------
# Pazi: k-means zahteva numericka i SKALIRANA obelezja.

# pripremi_za_klaster(dt, obelezja) -> matrica, scale()
# kmeans_scenario(m, k_vrednosti, nstart = 25) -> lista modela po k
# metod_lakta(m, k_max = 10)   -> tabela k | WSS   (za izbor k)
# silueta(m, klaster)          -> prosecna silueta (cluster::silhouette)
# profil_klastera(dt, klaster) -> po klasteru: velicina + srednje vrednosti
# uporedi_sa_ciljem(klaster, dt[[CILJ]]) -> kontingencija klaster vs room_type
