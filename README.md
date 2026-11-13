# OneXPlayer 1S — Utility (Windows 11)

Utility grafica WPF in PowerShell ispirata a **Chris Titus WinUtil** per il **OneXPlayer 1S** su **Windows 11**. Tre schede:

- **Driver**: scarica e installa in sequenza silenziosa i 13 driver del 1S.
- **Gioco**: installa con winget i programmi utili per giocare (librerie, negozi, strumenti per le prestazioni, streaming, emulatori).
- **Schermo**: orientamento, blocco della rotazione automatica, risoluzione e diagnosi del touch.

## Avvio rapido (stile WinUtil)

Apri **PowerShell** (anche non come amministratore, lo script chiede l'elevazione UAC automaticamente) ed esegui:

```powershell
irm 070293.xyz/oxp-win | iex
```

Oppure direttamente da GitHub:

```powershell
irm https://raw.githubusercontent.com/dilfal/onexplayer-1s-drivers/main/oxp1s.ps1 | iex
```

### Uso offline (senza download)

Se hai già copiato gli archivi `.zip` in locale (ad esempio nella sottocartella `drivers\` oppure nella stessa cartella dello script), avvia [Avvia.cmd](Avvia.cmd) oppure passa `-LocalDriversPath`:

```powershell
.\oxp1s.ps1 -LocalDriversPath "C:\Percorso\Drivers"
```

La scheda Gioco e i comandi della scheda Schermo non usano gli archivi: i programmi si scaricano con winget (serve Internet).

## Caratteristiche

- **Interfaccia WPF scura in Italiano** con tre schede (Driver, Gioco, Schermo), barre di avanzamento e log in tempo reale comuni.
- **Scheda Driver**: selezione singola o tramite preset (`Seleziona Tutti`, `Solo Mancanti / Aggiornabili`, `Solo Essenziali`), rilevamento automatico dei driver già installati e dei dispositivi con errori, Punto di Ripristino automatico (disattivabile), installazione 100% silenziosa in ordine di dipendenza e **riavvio unico finale**.
- **Scheda Gioco**: 23 programmi con categoria, descrizione e stato sul PC (rilevato in background, circa 30 secondi); preset `Consigliati`, `Tutti`, `Nessuno`; installazione con `winget` una voce alla volta.
- **Scheda Schermo**: rotazioni relative (90, 180, 270 gradi), blocco/sblocco della rotazione automatica, risoluzione `Nativa` / `1920 x 1200` / `1280 x 800`, diagnosi e riparazione del touch. **Ogni cambio di schermo chiede conferma per 15 secondi** e, se non rispondi Sì, torna da solo allo stato precedente.
- Il pulsante in basso cambia con la scheda: «Installa Driver Selezionati» (Driver), «Installa Programmi Selezionati» (Gioco), disattivato (Schermo). `Annulla` ferma la coda in corso tra un elemento e l'altro.

## Driver inclusi (in ordine sequenziale)

1. **Intel Chipset Device Software** (`10.1.18460.8229`) — `SetupChipset.exe /s /norestart`
2. **Intel Serial IO (GPIO / I2C / SPI / UART)** (`30.100.2013.5`) — `SetupSerialIO.exe /s`
3. **Intel Management Engine (MEI + DAL + iCLS)** (`2108.100.0.1053`) — `heci.inf`, `DAL.inf`, `iclsClient.inf` via `pnputil`
4. **Intel GNA Scoring Accelerator** (`02.00.00.1010`) — `pnputil /add-driver ... /install`
5. **Intel Dynamic Tuning Technology (DTT)** (`8.7.10400.15556`) — `Dtt_8.7.10400.15556_Install.exe /s`
6. **Intel Iris Xe Graphics** (`27.20.100.9616`) — INF diretti via `pnputil`
7. **Realtek High Definition Audio** (`6.0.1.7541`) — INF `Vista64` via `pnputil`
8. **Intel Wi-Fi (UWD Win64)** (`21.110.1.1`) — INF `UWD\Win64\Drivers` via `pnputil`
9. **Intel Wireless Bluetooth (UWD x64)** (`21.110.0.3`) — INF `INF_INSTALL\Win10_UWD\x64` via `pnputil`
10. **Intel Thunderbolt DCH** (`1.41.1054.0`) — INF driver via `pnputil` (senza app Appx)
11. **Realtek Card Reader** (`RtsUer`) — INF via `pnputil`
12. **Bosch BMA2x2 Accelerometer** (`1.0.1.2`) — INF `UMDF_2.0_BMA2x2_1.0.1.2_RS5_signed` via `pnputil`
13. **FocalTech Fingerprint Reader** (`2.0.3.71`) — `ftWbioUmdfDriverV2.inf` via `pnputil`

Management Engine, Thunderbolt e lettore di impronte vengono dal pacchetto del produttore «ONEXPLAYER 8.4 Drivers V1.0» (maggio 2021), più recente per questi tre componenti; gli altri dieci dal pacchetto del 1S. Il download complessivo è di circa 0,9 GB.

*(Escluso: `intel(r) pch chipset_init kit` perché contiene solo file binari `.bin` per flashing BIOS/SPI OEM non installabili da Windows).*

**Grafica aggiornata:** il driver Iris Xe del pacchetto è quello del produttore. Per averlo sempre aggiornato installa dalla scheda Gioco **Intel Driver & Support Assistant**, che aggiorna grafica Iris Xe, Wi-Fi e Bluetooth alle versioni Intel correnti.

## Programmi della scheda Gioco

I programmi marcati **(C)** sono quelli selezionati con il preset `Consigliati` (e all'avvio).

| Categoria | Programmi |
|---|---|
| Librerie | Visual C++ 2015-2022 x64 **(C)** e x86 **(C)**, DirectX End-User Runtime **(C)**, .NET Desktop Runtime 8 **(C)** |
| Grafica | Intel Driver & Support Assistant **(C)**, Intel Graphics Command Center **(C)** (dallo Store) |
| Negozi | Steam **(C)**, Playnite **(C)**, Heroic Games Launcher, GOG Galaxy, Epic Games Launcher, EA app, Ubisoft Connect |
| Prestazioni | RivaTuner Statistics Server **(C)**, MSI Afterburner, HWiNFO, Handheld Companion (il 1S non è tra i dispositivi elencati: da provare), ThrottleStop |
| Streaming | GeForce NOW, Moonlight |
| Emulazione | RetroArch, PCSX2 |
| Utilità | 7-Zip **(C)** |

Lo stato («Installato» / «Non installato») viene letto con `winget export` (voci winget) e `Get-AppxPackage` (Intel Graphics Command Center). Se `winget` manca, la coda non parte: aggiorna «Programma di installazione app» dal Microsoft Store (sulle edizioni LTSC winget non è incluso e va installato a parte). Al termine della coda compare un riepilogo, senza richiesta di riavvio.

## Scheda Schermo

- **Orientamento**: `Ruota di 90 gradi`, `Capovolgi (180 gradi)`, `Ruota di 270 gradi`. Sono rotazioni relative all'orientamento attuale.
- **Rotazione automatica**: `Blocca` / `Sblocca` (valore `Enable` in `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AutoRotation`); può servire uscire e rientrare in Windows.
- **Risoluzione**: `Nativa`, `1920 x 1200`, `1280 x 800`. 1280 x 800 è la metà esatta della nativa: con la scalatura a numeri interi di Intel Graphics Command Center resta nitida e i giochi girano molto più leggeri. Se il driver video non elenca la modalità richiesta (succede con il driver di base) non viene applicato nulla.
- **Conferma**: ogni cambio chiede «Mantenere questa impostazione dello schermo?» per 15 secondi; senza Sì torna allo stato precedente.
- **Touch**: `Diagnosi touch` controlla Intel Serial IO, i dispositivi HID su I2C e il touch screen e scrive l'esito; `Ripara touch` riattiva e riavvia i dispositivi coinvolti. Se manca Serial IO propone di selezionare solo quel driver nella scheda Driver.

## Pubblicazione su GitHub Releases

Per creare il repository pubblico `dilfal/onexplayer-1s-drivers`, fare il push e caricare i 13 `.zip` su GitHub Releases `v1.0.0`:

```powershell
.\publish-release.ps1
```
