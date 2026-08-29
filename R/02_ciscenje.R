# ---- Uredjivanje i nedostajuce vrednosti [priprema podataka, 3p] ------------
# Cista transformacija: data.table ulazi -> data.table izlazi. Bez citanja/pisanja.

# parsiraj_cenu(x)         -> numeric  ("$1,234.00" -> 1234)
# parsiraj_procenat(x)     -> numeric  ("95%" -> 95)
# parsiraj_kupatila(x)     -> numeric  ("1.5 shared baths" -> 1.5)
# tipiziraj_obelezja(dt)   -> factor / Date / numeric u pravim kolonama
# izvestaj_nedostajucih(dt)-> tabela: obelezje | broj NA | procenat NA
# obradi_nedostajuce(dt)   -> imputacija / izbacivanje (dokumentuj odluku!)
# izgradi_analiticki_skup(dt) -> finalni skup samo sa obelezjima za modele
