**Das Symbol im Panel**

- Eine **Länderflagge** steht für das Land deines tatsächlichen Internet-Austritts — dort
  sieht der Rest der Welt deinen Datenverkehr herkommen. Sie wechselt, sobald ein VPN die
  Standardroute übernimmt. Unter Einstellungen ▸ Menüleistenstil geht stattdessen auch der
  **ISO-Code** (`DE`) auf einem Badge oder die Emoji-Flagge; in Panelgröße ist der ISO-Code
  am besten zu lesen.
- Die App folgt der Sprache deines Desktops. Unter Einstellungen ▸ Sprache lässt sie sich
  von Hand umstellen — English oder Deutsch — und zwar ab dem nächsten Öffnen des Menüs,
  ohne Neustart.
- Ein **durchgestrichenes Netzwerk-Symbol** heißt, dass gerade nichts wirklich lädt — egal, was
  WLAN oder Ethernet behaupten. Ein **Fragezeichen** heißt, der Austritt ließ sich nicht zuordnen.
- Ein kleines **Warndreieck** in der Ecke des Symbols steht für ein bestätigtes Leck:
  IPv6- oder DNS-Verkehr läuft am Tunnel vorbei. Die obersten Zeilen im Menü sagen, welches.

**Der VPN-Name**

Der Tunnel mit der Standardroute wird nach der Verbindung benannt, als die NetworkManager
ihn betreibt — so, wie du sie in den Netzwerkeinstellungen genannt hast. Das funktioniert
für jedes dort eingerichtete VPN. Clients, die am NetworkManager vorbeigehen, werden am
Schnittstellennamen erkannt, den ihr eigener Client vergibt (Tailscale, Cloudflare WARP,
NordVPN, Mullvad), OpenVPN an seinem Prozess. Geht nichts davon, steht dort **VPN (tun0)** —
der Tunnel ist echt und die Route stimmt, nur die Marke ist unbekannt. „Diagnose kopieren"
sagt, woran es lag, und genau das braucht ein Issue, damit dein VPN benannt werden kann.

**Seit und Geprüft**

*Seit* ist der Beginn des Zustands, den du gerade siehst — der Wert bewegt sich nur, wenn
sich Austritt, Route oder Verbindung wirklich ändern. *Geprüft* ist der Zeitpunkt der
letzten Bestätigung. Ein „Aktualisieren", das nur bestätigt, dass alles gleich geblieben
ist, bewegt „Geprüft", nicht „Seit". Beide stehen sekundengenau da, und zwar mit Absicht:
sonst sieht ein stundenalter Zustand genauso aus wie ein frischer.

**Die DNS-Zeile**

Aufgeklappt zeigt sie zwei verschiedene Arten von Tatsachen — sie zu verwechseln ist genau
das, was Split-DNS unlesbar macht:

- **Konfigurierte Resolver** — wen dieser Rechner fragen soll, je Schnittstelle, so wie
  systemd-resolved es meldet. Eine lokale Tatsache, immer bekannt, ganz ohne Netzwerk.
- **Anfragen beantwortet von** — wo deine Anfragen tatsächlich herauskamen, gemessen.
  Öffentliche Resolver sind lastverteilt, mehrere Adressen sind hier also normal. Steht
  diese Liste außerhalb deines Tunnels, während ein VPN die Route hat, ist das ein DNS-Leck.

Die Messung ist freiwillig: Einstellungen ▸ Auf DNS-Lecks prüfen schaltet sie ab, danach
wird keine einzige solche Anfrage mehr gesendet. Router-lokale Resolver, die an einen
bekannten Anbieter weiterleiten, werden so benannt — ob dieser Abschnitt verschlüsselt ist,
wird am Router eingestellt und lässt sich von hier aus nicht beobachten.

**Kopieren**

- Ein Klick auf die **Austritts-IP** kopiert die Adresse. Mit IPv6-Austritt kopiert
  **Beide Austrittsadressen kopieren** IPv4 und IPv6, eine pro Zeile.
- **Diagnose kopieren** kopiert das ganze Menü als Text, mit denselben Warnungen, die es dir
  auch anzeigt, und keinen weiteren — fertig zum Einfügen in einen Fehlerbericht. Der Text
  geht in die Zwischenablage und sonst nirgendwohin.
- Das Untermenü der DNS-Zeile kopiert seine Resolver-Listen, nackte Adressen, eine pro Zeile.

**Kein Symbol im Panel?**

Panels zeigen App-Symbole über den StatusNotifierItem-Standard (AppIndicator). Die meisten
können das von Haus aus; das Panel von elementary OS braucht zuerst den
Community-Indikator **AppIconTray**. Kann kein Panel das Symbol zeigen, sagt WhereAmIP das
einmal per Benachrichtigung — und die Kommandozeile unten funktioniert so oder so.

**Das Willkommensfenster**

Einstellungen ▸ Willkommensfenster anzeigen öffnet wieder das Fenster vom ersten Start —
was die App ist, und dieselben drei Schalter mit deinen aktuellen Einstellungen.

**Die Kommandozeile**

Alles, was das Panel kann, kann `whereamip` auch:

- `whereamip status` — ein Blick, als Text; `--json` für den vollständigen Datensatz.
- `whereamip watch` — eine neue Zeile, sobald sich Austritt, Route oder Verbindung ändern.
  `whereamip watch --json >> datei` ist der Weg zu einem Verlauf, falls du einen willst.
- `whereamip diagnostics` — derselbe Bericht, den „Diagnose kopieren" kopiert.
- `whereamip debug` — zeigt live jede Prüfung, während du einen Fehler nachstellst. Auf die
  Festplatte wird dabei nichts geschrieben, weder vorher noch danach. Für die Panel-App
  selbst: mit `WHEREAMIP_DEBUG=1 whereamip-indicator` starten.
- `whereamip config get` / `set` — dieselben Einstellungen, die auch im Menü stehen,
  inklusive `config set language de|en|system`.

Die Ausgaben von `whereamip` sind bewusst englisch: sie sind eine auswertbare Schnittstelle,
und Fehlerberichte landen in englischsprachigen GitHub-Issues.

**Sonst noch**

Die README beantwortet die längeren Fragen, und Fehlerberichte sind willkommen — häng die
Ausgabe von `whereamip diagnostics` an, oder füge ein, was „Diagnose kopieren" kopiert hat:
[github.com/frinsen/whereamip](https://github.com/frinsen/whereamip)
