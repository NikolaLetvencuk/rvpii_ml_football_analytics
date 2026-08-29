# ---- Pomocne funkcije (nemaju veze sa domenom) ------------------------------

# log_info(...)            -> ispis sa vremenskom oznakom u konzolu + outputs/logs
# meri_vreme(expr, opis)   -> izvrsi, izmeri i zabelezi trajanje (za HPC deo!)
# sacuvaj(obj, ime)        -> saveRDS u odgovarajuci folder
# ucitaj_sacuvano(ime)     -> readRDS
# sacuvaj_tabelu(dt, ime)  -> fwrite u PUT$tabele (za izvestaj)
# osiguraj_foldere()       -> dir.create svih putanja iz PUT ako ne postoje
