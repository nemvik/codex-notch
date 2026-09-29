# Codex Notch

Tenký barevný lem na spodním okraji notche ukazuje, kdy místní Codex pracuje, čeká na tebe nebo dokončil úlohu. Přibliž kurzor k notchi: objeví se malá připojená záložka, kterou kliknutím rozbalíš na přesné počty a přehled chatů. SwiftUI + AppKit, macOS 13+, bez externích knihoven, API klíčů nebo předplatného navíc.

[English](README.md) · [Vydání](https://github.com/nemvik/codex-notch/releases) · [Nahlásit problém](https://github.com/nemvik/codex-notch/issues/new/choose)

![Tenký barevný lem pod notchem uvnitř horní lišty](docs/assets/notch.png)

![Dočasná klikací záložka vysunutá při přiblížení kurzoru k notchi](docs/assets/reveal.png)

![Černá plocha napojená na notch a rozbalená kliknutím na přehled Codexu](docs/assets/popover.png)

*Ilustrace vykreslené ze skutečných SwiftUI pohledů s ukázkovými daty v ilustračním prostředí plochy. Aplikace je zatím v češtině.*

## Spuštění

Je potřeba Xcode s dostupným Swift toolchainem. Pro živé stavy musí běžet místní desktopový Codex.

```bash
git clone https://github.com/nemvik/codex-notch.git
cd codex-notch
./scripts/run.sh
```

Kvůli kompatibilitě sestavená aplikace zůstává v `build/Codex Island.app`, binárka se jmenuje `CodexIsland`. Pro další spuštění stačí tuto aplikaci otevřít. Není potřeba instalace do Applications.

**Doporučené je sestavení ze zdrojového kódu.** Plánované předběžné vydání `Codex-Notch-v0.1.0-arm64.zip` je pro Apple Silicon s podpisem ad-hoc, bez Developer ID a notarizace. Dostupnost ověř na stránce Vydání; macOS může otevření staženého balíčku zablokovat. Na Intelu použij sestavení ze zdrojů; chování na Intel hardwaru zatím není ověřené.

## Ovládání

- Barevný lem rozlišuje běžící práci, čekání na lidskou odpověď nebo schválení, nové výsledky, selhání, klid a odpojení. Automatická schválení se nepočítají jako lidský zásah.
- Odpojení není totéž jako nulová aktivita. Pokud není dostupný živý stav Codexu, aplikace ukáže stav napojení.
- Přibliž kurzor k notchi a krátce se zastav. Vysune se malá klikací záložka, která po odjetí kurzoru zase zmizí. Kliknutím rozbalíš stejnou připojenou plochu na přesné počty úloh a subagentů a seznam chatů. Celý přehled se samotným najetím neotevře. Kliknout lze také přímo na notch; v náhradním režimu použij položku v menu baru.
- Kliknutí na řádek otevře chat v Codexu; u subagenta se použije hlavní chat, pokud je známý.
- Přečtením přehledu se potvrdí nové výsledky. Dokončené řádky zůstávají v přehledu deset minut. Přerušení práce ani ztráta spojení nejsou úspěšné dokončení.
- Přehled zavřeš kliknutím mimo něj, opětovným kliknutím na notch nebo klávesou Escape, když má fokus. V jeho ovládání lze obnovit napojení nebo aplikaci ukončit.
- Volba **Spouštět po přihlášení** registruje aplikaci přes macOS ServiceManagement. macOS může požadovat zapnutí v Nastavení systému → Obecné → Přihlašovací položky. Po registraci nepřesouvej aplikaci bez vypnutí a opětovného zapnutí této volby.

## Nativní rozhraní

V klidu je vidět pouze lem v bezpečném vykreslitelném pásu pod fyzickým výřezem kamery, celý uvnitř horní lišty. Žádný trvalý panel nepřekrývá pracovní plochu.

Při přiblížení kurzoru se dočasně vysune černá záložka 32 bodů pod lištu, která po dobu zobrazení může překrýt horní část okna aplikace. Kliknutím se rozšíří na přehled široký 336 bodů. Oba stavy navazují na notch a nemají boční křídla přes ikony menu baru. Rozhraní používá systémové písmo, SF Symbols a SwiftUI uvnitř AppKitu.

Standardní položka v menu baru s nativním popoverem slouží jen jako náhrada na Macu bez notche nebo když není dostupný bezpečný pás pro vykreslení lemu. V tomto režimu potřebuje místo mezi ostatními položkami horní lišty.

## Jak funguje napojení

Aplikace čte `~/.codex/state_<verze>.sqlite` pouze pro identifikátory nearchivovaných místních chatů. Živé stavy získává z existujícího desktopového socketu `~/.codex/ipc/ipc.sock`: zaregistruje se jako pozorovatel a odebírá snapshoty a změny `thread-stream-state-changed`. Neupravuje konfiguraci, nepřebírá vlastnictví chatů, neschvaluje příkazy a nespouští agenty.

Příchozí zprávy mohou přechodně obsahovat texty konverzací, výstupy nástrojů a diffy; aplikace je po přijetí zahazuje. Pro panel drží v paměti jen metadata potřebná pro názvy chatů a stavy. Nic neposílá na internet ani nezapisuje historii chatů. Nové chaty dohledává každých 15 sekund; změny existujících chatů přicházejí živě. Socket musí patřit přihlášenému uživateli a mít bezpečná oprávnění.

**Omezení:** Desktop IPC je interní, nezdokumentované rozhraní, ověřené s místním Codex CLI 0.159.0 a streamem verze 11. Aktualizace Codexu může vyžadovat úpravu adaptéru. Veřejně dokumentovaný App Server poskytuje stejné druhy stavů, ale samostatně spuštěný server neposkytuje automaticky živé stavy desktopu. Neznámá verze streamu zobrazí chybu napojení. Tato verze nezahrnuje VPS, samostatné CLI procesy bez sdíleného desktopového streamu ani cloudové ChatGPT konverzace. Subagenti se započítají, pokud desktop poskytne jejich samostatný živý stav.

Výchozí umístění lze změnit proměnnou `CODEX_HOME`, když se spouští přímo binárka z terminálu. Úvodní snapshoty staré historie nevytvářejí oznámení o dokončení. Nezobrazuje odhadovaná procenta dokončení.

Ne všechny modely Maců, režimy škálování a kombinace externích displejů jsou ověřené na skutečném hardwaru. Projekt není propojený s OpenAI ani Applem a není jejich oficiálním produktem.

## Ověření a vývoj

```bash
swift test
./scripts/build.sh
python3 scripts/test-adapter.py
"build/Codex Island.app/Contents/MacOS/CodexIsland" --diagnose
open "build/Codex Island.app" --args --demo --expanded
```

Diagnostika deset sekund čte skutečné desktopové napojení a vypíše pouze stav spojení a počty, bez textů chatů. Vrací úspěch, pokud se připojí a obdrží alespoň jeden živý snapshot; pokud žádný chat není načtený, vrací 1 i při dostupném socketu.

Demo je označené ukázkovými daty a nepřipojuje se ke Codexu. Před spuštěním jiné instance aplikaci ukonči přes menu bar.

Swift testy pokrývají protokol, katalog, stavy aktivit a prezentační chování: fragmentované IPC rámce, chybné zprávy, revize a obnovení snapshotů, lidská a automatická schválení, stavy subagentů, dokončení/přerušení/odpojení a čtení katalogu bez zápisu. Aplikace se podepisuje lokálně ad-hoc; není notarizovaná pro veřejnou distribuci.

Volitelný test adaptéru používá Python 3 a dočasné lokální sockety/databáze, bez čtení skutečného Codexu. Ověřuje živý stav, obnovu po chybějící revizi a odmítnutí neznámé verze protokolu; trvá přibližně 30 sekund.

Odkaz: [Codex App Server](https://developers.openai.com/codex/app-server/).

Projekt vzniká pro radost. Hlášení chyb i drobné příspěvky jsou vítané; viz [Contributing](CONTRIBUTING.md). Bezpečnostní problémy hlaste soukromě podle [Security](SECURITY.md). Kontakt: [codexnotch@nemvik.com](mailto:codexnotch@nemvik.com). Zdrojový kód je pod [licencí MIT](LICENSE).
