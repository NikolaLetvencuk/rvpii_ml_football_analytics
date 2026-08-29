# Klasterizacija i klasifikacija fudbalskih igrača na osnovu StatsBomb podataka

Analiza stila i pozicija fudbalskih igrača primenom mašinskog učenja nad
StatsBomb Open Data skupom, u jeziku R. Projekat za predmet
*Računarstvo visokih performansi u informacionom inženjeringu* (FTN Novi Sad).

## Skup podataka

- **Izvor:** [StatsBomb Open Data](https://github.com/statsbomb/open-data) —
  slobodno i javno dostupan, bez procedura za pristup (nekomercijalna,
  istraživačka upotreba uz navođenje izvora).
- **Priroda:** detaljni podaci o događajima (event data) — svaki zapis je
  jedna akcija na terenu (dodavanje, šut, dribl, pritisak, oduzimanje...) sa
  koordinatama, igračem, timom, ishodom i xG.
- **Obim:** preko 350 utakmica iz 4 lige (Premier League, La Liga, Ligue 1,
  Serie A), > 1 GB u JSON formatu (~1,3 miliona događaja).

## Tehnologije

- **R** — kompletna obrada, analiza i modelovanje
- **Markdown** — izveštavanje
- Paketi: `jsonlite`, `dplyr`, `tidyr`, `readr`, `ggplot2`, `graphics`,
  `caret`, `class`, `rpart`, `rpart.plot`, `randomForest`, `cluster`,
  `factoextra`

## Struktura projekta

```
projekat/
├── data/
│   ├── raw/statsbomb/events/        # 356 sirovih JSON fajlova (~1 GB)
│   ├── raw/statsbomb/matches/       # metapodaci o utakmicama
│   └── processed/                   # obrađene tabele (CSV)
├── scripts/
│   ├── 00_prikupljanje_podataka.R   # preuzimanje event podataka
│   ├── 01_build_feature_table.R     # JSON -> tabela obeležja po igraču
│   ├── 02_priprema_i_analiza.R      # priprema + preliminarna analiza
│   ├── 04_klasifikacija.R           # KNN, stablo, random forest
│   └── 05_klasterizacija.R          # k-Means
├── figures/                         # generisani grafikoni
└── README.md
```

## Tok rada i status

### ✅ Prikupljanje podataka (`00`)
Preuzeto 356 utakmica (round-robin po ligama) do ~1 GB event podataka.

### ✅ Formiranje tabele obeležja (`01`)
Parsiranje i agregacija ~1,3M događaja u tabelu na nivou igrača:
**770 igrača × 25+ numeričkih obeležja**, normalizovanih na 90 minuta
(dodavanja, šutevi, xG, driblinzi, pritisci, oduzimanja, tackles...).
Filtriran minimum od 450 minuta. Izlaz: `data/processed/player_features.csv`.

### ✅ Priprema i preliminarna analiza (`02`)
- učitavanje i uređivanje (tipovi, faktori)
- ispitivanje nedostajućih vrednosti (nema pravih NA; obeležja su brojači,
  pa izostanak akcije daje 0; jedini slučaj 0/0 kod stopa uspešnosti
  postavljen na 0 uz napomenu)
- deskriptivne statistike po obeležjima
- vizualizacija raspodela (histogram, gustina, boxplot, Q-Q, bar) —
  `graphics` i `ggplot2`
- ispitivanje odnosa obeležja (scatter, korelaciona matrica)

Izlaz: `data/processed/player_features_clean.csv`, `figures/`

### ✅ Klasifikacija [15p] (`04`)
Ciljno obeležje: **poziciona grupa (6 klasa: GK/CB/FB/DM_CM/AM_W/FW)**.
Tri metode, svaka sa 3 scenarija parametara:
- **KNN** — parametar `k` (1 / 15 / 50)
- **Stablo odlučivanja** — parametar `cp` (0 / 0.01 / 0.05)
- **Random Forest** — parametar `mtry` (2 / √p / p)

Ocena: 10-fold unakrsna validacija, pokazatelji ACC/PREC/SENS/SPEC/F1
(makro-prosek), odnos parametara i performansi, izbor najboljeg rešenja
po metodi i ukupno. Izlaz: `data/processed/classification_results.csv`

### ✅ Klasterizacija [6p] (`05`)
**k-Means**, dva scenarija broja klastera (k), ispitivanje strukture
klastera (profili, silueta, poređenje sa pozicijama), vizualizacija
odnosa obeležja i pripadnosti klasteru.
Izlaz: `data/processed/player_clusters.csv`

## Pokretanje

Redosled (iz korenskog foldera projekta):

```bash
Rscript scripts/00_prikupljanje_podataka.R   # ~1 GB, traje duže
Rscript scripts/01_build_feature_table.R     # parsiranje JSON-a
Rscript scripts/02_priprema_i_analiza.R
Rscript scripts/04_klasifikacija.R
Rscript scripts/05_klasterizacija.R
```

> Napomena: skripte `04` i `05` imaju parametre koji se biraju na osnovu
> pomoćnih grafikona (elbow/silhouette za k, k-vs-tačnost za KNN) — pokrenuti
> jednom, pogledati grafikone, po potrebi podesiti i pokrenuti ponovo.

## Preostalo

- [ ] Interpretacija rezultata i imenovanje klastera (arhetipovi)
- [ ] Finalni Markdown izveštaj
