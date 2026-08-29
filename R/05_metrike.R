# ---- Pokazatelji performansi [deo klasifikacije, 15p] -----------------------
# Cist racun iz (stvarno, predvidjeno). Bez modela, bez treniranja.
# Visekasna varijanta: macro i weighted usrednjavanje.

# konfuziona_matrica(stvarno, predvidjeno) -> table
# tacnost(cm)                              -> accuracy
# preciznost(cm, avg = "macro")            -> precision
# osetljivost(cm, avg = "macro")           -> recall / sensitivity
# f_mera(cm, avg = "macro")                -> F1
# kappa(cm)                                -> Cohen's kappa
# sve_metrike(stvarno, predvidjeno)        -> jedan red data.table sa svime
