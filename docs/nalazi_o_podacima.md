# Nalazi o podacima (provereno na stvarnim fajlovima)

Provereno 23.08.2026. Ovo su izmerene vrednosti, ne pretpostavke —
koristi ih u sekciji "priprema podataka" i "nedostajuće vrednosti" izveštaja.

## 1. Barcelona nema cene — uopšte

`bcn_listings.csv.gz` (18.177 oglasa): kolona `price` je **prazna u svih
18.177 redova** (1 unikatna vrednost = `""`). `bcn_calendar.csv.gz`
(6.634.623 reda) ima `price` i `adjusted_price` koje se čitaju kao
`logical NA` — takođe prazne.

**Posledica:** Barcelona se ne može koristiti kao primarni skup ako je cena
prediktor, kao što je predviđeno u specifikaciji ideje.

## 2. London radi — koristi njega kao primarni skup

`london_listings.csv.gz`: **96.871 oglas, 79 obeležja**. `price` je u formatu
`"$70.00"` i popunjen je u 64% redova.

Nedostajuće vrednosti po ključnim obeležjima:

| Obeležje | NA |
|---|---|
| `price` | 36,0% |
| `beds` | 36,0% |
| `estimated_revenue_l365d` | 36,0% |
| `review_scores_rating` | 24,9% |
| `bedrooms` | 13,2% |
| `host_is_superhost` | 1,8% |
| `bathrooms_text` | 0,2% |
| `accommodates`, `property_type`, `neighbourhood_cleansed`, `latitude`, `estimated_occupancy_l365d` | 0,0% |

`price`, `beds` i `estimated_revenue_l365d` imaju **identičnih 36%** — verovatno
isti podskup oglasa (neaktivni/nedostupni). Proveri da li su to isti redovi:
ako jesu, to je jedna odluka o izbacivanju, a ne tri odvojene imputacije.

`london_calendar.csv.gz` **takođe ima praznu kolonu `price`** — cena se ne može
rekonstruisati iz kalendara. Kalendar koristi za `available` i `minimum_nights`.

## 3. Ciljno obeležje je ekstremno neizbalansirano

London `room_type`:

| Klasa | N | % |
|---|---|---|
| Entire home/apt | 62.907 | 64,9% |
| Private room | 33.643 | 34,7% |
| Shared room | 212 | 0,22% |
| Hotel room | 109 | 0,11% |

**Ovo je najveći rizik za deo od 15 poena.** Sa 0,1–0,2% u dve klase:

- Model koji uvek predviđa `Entire home/apt` ima tačnost 65% — zato **tačnost
  sama po sebi ne znači ništa** i mora se prijaviti i macro F-mera.
- Macro-usrednjena F-mera je dominirana dvema sitnim klasama; modeli će ih
  praktično ignorisati i macro F1 će biti nizak bez obzira na kvalitet modela.
- Uz `CV_K = 5` preklopa, `Hotel room` daje ~22 primera po preklopu.
  **Stratifikacija po ciljnom obeležju je obavezna** (`rsample::vfold_cv(strata = room_type)`),
  inače neki preklop može ostati bez ijednog primera te klase.

Opcije (izaberi i **obrazloži u izveštaju** — to je poenta zadatka):

1. Zadrži 4 klase + težine klasa (`class.weights` u `e1071::svm`,
   `case_weights` u parsnip) i prijavi i macro i weighted F-meru.
2. Spoji `Shared room` + `Hotel room` u klasu `Ostalo` → 3 uravnoteženije klase.
3. Zadrži 2 dominantne klase (binarni problem) — najčistije metrike, ali
   odbacuje deo podataka.

Preporuka: **opcija 1 kao osnovni scenario**, uz opciju 2 kao poređenje —
tako imaš materijal za "ispitivanje odnosa između parametara i performansi".

## 4. Obim (zahtev "reda veličine GB")

Sirovi fajlovi su ~195 MB komprimovano. Ali:

- `bcn_calendar.csv.gz` = **6,63 miliona redova**, 0,22 GB u RAM-u
- `london_calendar.csv.gz` je 5× veći fajl → red veličine 35M redova

Kombinovani kalendari **prelaze GB u memoriji**, što ispunjava zahtev i daje
pravi razlog za `data.table` i paralelizaciju. Obavezno izmeri i prijavi
vremena učitavanja i obrade (`R/99_utils.R::meri_vreme`) — to je HPC deo predmeta.

## 5. Tehnička napomena

`fread()` ne čita `.csv.gz` bez paketa **`R.utils`**. Već je instaliran.

Referentno vreme: `bcn_listings.csv.gz` (18k × 85) = 3,2 s na 21 nitI.
