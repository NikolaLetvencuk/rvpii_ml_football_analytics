# ---- Ucitavanje podataka [priprema podataka, 3p] ----------------------------
# Funkcije koje CITAJU sa diska i vracaju data.table. Bez transformacija.
# Koristi data.table::fread -- cita .csv.gz direktno i visenitno.

# ucitaj_oglase(putanja, kolone = NULL, n = Inf) -> data.table
# ucitaj_kalendar(putanja) -> data.table
# ucitaj_sve() -> lista tabela za sve gradove, sa kolonom `grad`
