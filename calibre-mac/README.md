# Calibre Mac

Un'interfaccia **nativa macOS** per Calibre, scritta in SwiftUI, che sostituisce la GUI Qt mantenendo il motore di Calibre (database, conversione, metadati).

> Stato: **versione 0.3, in sviluppo**. Copre l'uso quotidiano della libreria; le funzioni avanzate di Calibre sono elencate in [Roadmap](#roadmap). Non è un prodotto ufficiale e non è affiliato a Calibre.

## Perché

La GUI di Calibre è potente ma costruita con Qt e pensata per tutte le piattaforme: su Mac risulta pesante e poco "mac". Questo progetto tiene tutto ciò che Calibre fa bene (formati, conversione, metadati, ricerca) e cambia solo l'interfaccia: sidebar, toolbar unificata, Liquid Glass, Quick Look, tema chiaro/scuro di sistema, menu e scorciatoie standard.

## Come funziona

La GUI Qt di Calibre **non viene mai avviata**. L'app usa Calibre come motore, in modalità headless:

```
┌──────────────────────────┐        HTTP /ajax (letture)         ┌─────────────────────┐
│  Calibre Mac (SwiftUI)   │ ──────────────────────────────────▶ │  calibre-server     │
│  sidebar · elenco ·      │                                     │  (processo figlio,  │
│  griglia · lettore       │ ── calibredb --with-library URL ──▶ │   solo localhost)   │
│                          │         (scritture)                 └─────────┬───────────┘
│                          │ ── ebook-convert / ebook-polish ─▶  libreria Calibre (metadata.db)
└──────────────────────────┘
```

- **Letture**: l'app avvia `calibre-server` su una porta locale libera e legge i metadati da `/ajax/books`, le copertine da `/get/thumb`.
- **Scritture**: ogni modifica passa da `calibredb` collegato al server (`--with-library http://127.0.0.1:PORTA/#libreria`), quindi non si accede mai direttamente al database.
- **Conversione, rifinitura, notizie, recupero metadati**: `ebook-convert`, `ebook-polish`, `fetch-ebook-metadata`.
- **Il server muore insieme all'app**, anche dopo un crash (un wrapper controlla il processo padre), e all'avvio vengono eliminati eventuali server rimasti da esecuzioni precedenti.

Serve quindi **Calibre installato** (viene usato solo come motore).

## Funzioni

| Area | Stato |
|---|---|
| Libreria: elenco con colonne personalizzabili (menu sull'intestazione), griglia con zoom, ordinamento | ✅ |
| Ricerca con operatori (`autore:`, `tag:`, `serie:`, `formato:`, `rating:`…) e ricerche salvate | ✅ |
| Ricerca nel testo completo dei libri (indice FTS di Calibre) | ✅ |
| Tag browser: autori, serie, tag, editori, formati, valutazioni, lingue; selezione multipla E/O, esclusione (NON), filtro, rinomina / unisci / rimuovi | ✅ |
| Dettagli del libro: copertina, valutazione a stelle, formati, identificatori, commenti | ✅ |
| Aggiungi libri (file, trascinamento, libro vuoto), rimuovi, salva su disco | ✅ |
| Modifica metadati singola e in blocco, navigazione precedente/successivo | ✅ |
| Cambio copertina (scelta file o trascinamento sull'inspector) | ✅ |
| Scarica metadati da fonti online (`fetch-ebook-metadata`) e applicali | ✅ |
| Conversione di formato con profilo dispositivo e rifinitura | ✅ |
| Lettore integrato: indice, segnalibri, cerca nel libro, carattere, tema automatico/bianco/seppia/scuro, posizione ricordata; PDF con PDFKit | ✅ |
| **Invio a e-reader** (Kindle, Kobo, volumi rimovibili) con conversione automatica ed espulsione | ✅ |
| Scarica notizie (ricette integrate di Calibre) | ✅ |
| Segna libri, libro a caso, Quick Look (spazio), Condividi (menu di sistema) | ✅ |
| Colonne personalizzate di Calibre | ⏳ |
| Librerie virtuali | ⏳ |
| Duplicati, controllo e ripristino libreria, cestino | ⏳ |
| Invio via email (Kindle), MTP, wireless | ⏳ |
| Editor del libro, modifica indice, catalogo, plugin, server contenuti, TTS | ⏳ |

### Invio a e-reader

Collega il lettore via USB, seleziona uno o più libri e usa **Invia a e-reader…** (⇧⌘D, pulsante in toolbar o menu contestuale).

| Dispositivo | Riconoscimento | Cartella | Formati preferiti |
|---|---|---|---|
| Kindle | volume con nome "Kindle" o cartelle `documents` + `system` | `documents/` | AZW3, MOBI, PDF, TXT |
| Kobo | cartella `.kobo` nella radice | radice del volume | KEPUB, EPUB, PDF |
| Altro e-reader USB | volume rimovibile | `Books/` se esiste, altrimenti radice | EPUB, PDF, MOBI, AZW3 |

Se il libro non ha un formato compatibile viene **convertito** (AZW3 per Kindle, EPUB per gli altri, con il profilo del dispositivo) prima della copia. Puoi cambiare la cartella di destinazione e scegliere se espellere il volume al termine. I lettori che usano solo MTP (non montano come disco) non sono ancora supportati.

## Requisiti

- macOS 26 (Tahoe) o successivo, Apple Silicon o Intel.
- [Calibre](https://calibre-ebook.com/download_osx) installato in `/Applications` (percorso modificabile in Impostazioni).

## Installazione

1. Genera il DMG (vedi sotto) oppure usa quello pronto, e trascina **Calibre Mac** in Applicazioni.
2. Al primo avvio l'app non è notarizzata: clic destro ▸ **Apri**.
3. Scegli la cartella della tua libreria Calibre (*File ▸ Apri libreria…*, ⇧⌘O) o creane una nuova.

> **Non usare questa app e il Calibre originale sulla stessa libreria nello stesso momento**: Calibre lo sconsiglia per evitare conflitti sul database. Chiudi uno dei due.

## Compilare dai sorgenti

Bastano le **Xcode Command Line Tools** (non serve Xcode completo).

```bash
cd calibre-mac
./build.sh        # build universale arm64 + x86_64 → build/Calibre Mac.app
./make-dmg.sh     # installer → build/Calibre Mac.dmg
```

> SwiftPM non è usato: con le sole Command Line Tools il manifest non compila su alcune versioni del toolchain, quindi la build passa direttamente da `swiftc`.

Per provare l'app senza toccare la tua libreria:

```bash
python3 dev/seed.py     # crea dev/TestLibrary con 13 libri TXT di prova
open -n --env CALIBREMAC_LIBRARY="$PWD/dev/TestLibrary" "build/Calibre Mac.app"
```

## Scorciatoie

| | |
|---|---|
| Aggiungi libri · Apri libreria | ⌘O · ⇧⌘O |
| Modifica metadati · Converti | ⌘E · ⇧⌘K |
| Leggi · Anteprima Quick Look | ⌘↩ · spazio / ⌘Y |
| Invia a e-reader | ⇧⌘D |
| Segna · Mostra nel Finder · Libro a caso | ⌘M · ⇧⌘R · ⌥⌘R |
| Rimuovi | ⌘⌫ |
| Elenco · Griglia · Dettagli | ⌘1 · ⌘2 · ⌥⌘I |

## Struttura del progetto

```
calibre-mac/
├── Sources/CalibreMac/
│   ├── App.swift            scene, menu e comandi
│   ├── Engine.swift         avvio calibre-server, esecuzione degli strumenti, API
│   ├── Store.swift          stato della libreria, filtri, azioni, lavori
│   ├── Models.swift         Book, categorie, parser delle query
│   ├── ContentView.swift    finestra, toolbar, barra filtri, stato, lavori
│   ├── SidebarView.swift    librerie, ricerche salvate, tag browser
│   ├── BookViews.swift      tabella (colonne personalizzabili), griglia, copertine
│   ├── InspectorView.swift  dettagli del libro
│   ├── Sheets.swift         metadati, conversione, notizie, impostazioni
│   ├── ReaderView.swift     lettore (WKWebView / PDFKit)
│   ├── DeviceScan.swift     rilevamento e-reader e piano di invio (logica pura)
│   └── Devices.swift        monitor dei volumi e foglio "Invia a e-reader"
├── tools/make_icon.swift    genera l'icona
├── prototype/index.html     prototipo HTML del redesign (UI di riferimento)
├── dev/seed.py              libreria di prova
├── build.sh · make-dmg.sh
```

## Verificato e non verificato

- ✅ Compila senza errori, universale arm64 + x86_64.
- ✅ Avvio del server, lettura di una libreria reale, ripristino dopo crash/kill dell'app.
- ✅ Rilevamento di Kindle, Kobo e volume generico (volumi di prova montati), piano di invio, nomi file, conversione TXT → AZW3 con profilo Kindle direttamente su un volume.
- ✅ Cambio copertina, impostazione identificatori e metadati tramite `calibredb` sul server.
- ⚠️ L'interfaccia è stata provata a mano dall'autore; **non esistono ancora test automatici della UI**.
- ⚠️ L'invio a un e-reader fisico non è stato provato su hardware reale (solo volumi simulati).
- ⚠️ "Scarica metadati" e "Scarica notizie" richiedono internet e dipendono dalle fonti di Calibre.

## Roadmap

Priorità concordata, in ordine:

1. **Colonne personalizzate** di Calibre: lettura, tabella, sidebar, ricerca (`#colonna:`), modifica per tipo (testo, numero, valutazione, sì/no, data, enumerazione, commenti).
2. **Librerie virtuali** vere (basate su ricerca) e cambio libreria rapido.
3. **Duplicati, controllo e ripristino libreria, cestino.**
4. Invio via **email** (Kindle), supporto **MTP** e wireless.
5. Editor del libro, modifica indice, catalogo, plugin, server contenuti, lettura vocale.
6. Firma e notarizzazione del DMG (serve un account Apple Developer).

## Licenza e crediti

Calibre è di Kovid Goyal e dei collaboratori, licenza GPLv3. Questo progetto vive nel fork del repository e usa Calibre solo come programma esterno (non ne include il codice). Vale la stessa licenza GPLv3 del repository.
