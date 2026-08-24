**Das Symbol in der Menüleiste**

- Eine **Länderflagge** steht für das Land deines tatsächlichen Internet-Austritts — dort
  sieht der Rest der Welt deinen Datenverkehr herkommen. Sie wechselt, sobald ein VPN die
  Standardroute übernimmt. Unter Einstellungen ▸ Menüleistenstil geht stattdessen auch ein
  schlichter **ISO-Code** (`DE`) oder ein Flaggenbild; bei 16 px ist der ISO-Code am besten
  zu lesen.
- Ein **durchgestrichenes WLAN-Symbol** heißt, dass gerade nichts wirklich lädt — egal, was
  das WLAN behauptet. Ein **Fragezeichen** heißt, der Austritt ließ sich nicht zuordnen.
- Ein kleines **⚠️-Zeichen** am Symbol steht für ein bestätigtes Leck: IPv6- oder
  DNS-Verkehr läuft am Tunnel vorbei. Die obersten Zeilen im Menü sagen, welches.

**Der VPN-Name**

Der Tunnel mit der Standardroute wird über den Netzwerkdienst benannt, den der Client bei
macOS registriert. Das funktioniert für jedes VPN, auch für eines, das diese App nie gesehen
hat. Manche Clients registrieren gar nichts; die werden über Erkennungsmerkmale benannt,
soweit sich das ehrlich machen lässt. Geht beides nicht, steht dort **VPN (utun4)** — der
Tunnel ist echt und die Route stimmt, nur die Marke ist unbekannt. Der Bericht von ⌘D sagt,
woran es lag, und genau das braucht ein Issue, damit dein VPN benannt werden kann.

**Seit und Geprüft**

*Seit* ist der Beginn des Zustands, den du gerade siehst — der Wert bewegt sich nur, wenn
sich Austritt, Route oder Verbindung wirklich ändern. *Geprüft* ist der Zeitpunkt der
letzten Bestätigung. Ein „Aktualisieren", das nur bestätigt, dass alles gleich geblieben
ist, bewegt „Geprüft", nicht „Seit". Beide stehen sekundengenau da, und zwar mit Absicht:
sonst sieht ein stundenalter Zustand genauso aus wie ein frischer.

**Die DNS-Zeile**

Aufgeklappt zeigt sie zwei verschiedene Arten von Tatsachen — sie zu verwechseln ist genau
das, was Split-DNS unlesbar macht:

- **Konfigurierte Resolver** — wen macOS fragen soll, je Schnittstelle. Eine lokale
  Tatsache, immer bekannt, ganz ohne Netzwerk.
- **Anfragen beantwortet von** — wo deine Anfragen tatsächlich herauskamen, gemessen.
  Öffentliche Resolver sind lastverteilt, mehrere Adressen sind hier also normal. Steht
  diese Liste außerhalb deines Tunnels, während ein VPN die Route hat, ist das ein DNS-Leck.

Die Messung ist freiwillig: Einstellungen ▸ Auf DNS-Lecks prüfen schaltet sie ab, danach
wird keine einzige solche Anfrage mehr gesendet. Router-lokale Resolver, die an einen
bekannten Anbieter weiterleiten, werden so benannt — ob dieser Abschnitt verschlüsselt ist,
wird am Router eingestellt und lässt sich von hier aus nicht beobachten.

**Tastaturkürzel**

- **⌘C** — kopiert die IPv4-Austrittsadresse.
- **⌥⌘C** — kopiert beide Austrittsadressen, IPv4 und IPv6. Halte **⌥** bei geöffnetem
  Menü gedrückt, dann wird aus der IP-Zeile diese größere Kopie; wurde kein IPv6-Austritt
  gemessen, sagt die Zeile genau das, und es wird nichts kopiert.
- **⌘D** — Diagnose kopieren: das ganze Menü als Text, mit denselben Warnungen, die es dir
  auch anzeigt, und keinen weiteren — fertig zum Einfügen in einen Fehlerbericht. Der Text
  geht in die Zwischenablage und sonst nirgendwohin.
- **⌘R** — Aktualisieren. **⌘?** — dieses Fenster. **⌘Q** — Beenden.

**Die Kommandozeile**

Alles, was die Menüleiste kann, kann `whereamip` auch:

- `whereamip status` — ein Blick, als Text; `--json` für den vollständigen Datensatz.
- `whereamip watch` — eine neue Zeile, sobald sich Austritt, Route oder Verbindung ändern.
  `whereamip watch --json >> datei` ist der Weg zu einem Verlauf, falls du einen willst.
- `whereamip diagnostics` — derselbe Bericht, den ⌘D kopiert.
- `whereamip debug` — überträgt das Diagnoseprotokoll live, während du einen Fehler
  nachstellst. Auf die Festplatte wird dabei nichts geschrieben, weder vorher noch danach.
- `whereamip config get` / `set` — dieselben Einstellungen, die auch im Menü stehen.

Die Ausgaben von `whereamip` sind bewusst englisch: sie sind eine auswertbare Schnittstelle,
und Fehlerberichte landen in englischsprachigen GitHub-Issues.

**Sonst noch**

Die README beantwortet die längeren Fragen, und Fehlerberichte sind willkommen — häng die
Ausgabe von `whereamip diagnostics` an, oder füge ein, was ⌘D kopiert hat:
[github.com/frinsen/whereamip](https://github.com/frinsen/whereamip)
