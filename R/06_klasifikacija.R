# ---- Klasifikacija: 3 metoda x 3 scenarija [15p] ----------------------------
# Ovde su SAMO funkcije. Konkretna mreza parametara i pozivi -> scripts/03_*.R
#
# Metodi (prema specifikaciji ideje):
#   1) Random Forest  (ranger)
#   2) XGBoost        (xgboost)
#   3) SVM            (e1071 ili kernlab)
#
# Preporuka: sve tri metode kroz `tidymodels` (parsnip + rsample + tune) da bi
# unakrsna validacija i mreza parametara bili identicni za sva tri -- tada je
# poredjenje posteno. Alternativa: `caret::train` sa trainControl(method="cv").

# podeli_podatke(dt, p = 0.75)  -> lista(train, test), stratifikovano po CILJ
# recept(train)                 -> preprocesiranje (dummy, normalizacija, ...)
# mreza_parametara(metod, scenario) -> data.frame parametara za 1 scenario
# istreniraj(metod, params, train) -> model
# oceni_cv(metod, params, train, k = CV_K) -> metrike po preklopima
# oceni_na_testu(model, test)     -> jedan red metrika + konfuziona matrica
# uporedi_scenarije(rezultati)    -> tabela svih (metod, scenario, params, metrike)
# izaberi_najbolji(rezultati, po = "f_mera") -> najbolji po metodu i ukupno
