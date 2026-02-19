import textwrap
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

out_path = Path("output/pdf/svs_app_kurzuebersicht_einfach.pdf")
out_path.parent.mkdir(parents=True, exist_ok=True)

# Content is intentionally simple German and based on repository evidence only.
title = "SVS App - Kurzuebersicht (einfach)"
subtitle = "Stand: aus Repo-Dateien in /SVS App und /functions"

sections = [
    (
        "Was ist das?",
        [
            "Die SVS App ist eine iPhone-App fuer interne Arbeitsablaeufe bei SV Souleiman.",
            "Sie verbindet Mitarbeitende und Admins mit einem Firebase-Backend fuer Daten und Benachrichtigungen.",
        ],
    ),
    (
        "Fuer wen ist es?",
        [
            "Primaere Nutzer: Mitarbeitende/Sachverstaendige und Admins im Sachverstaendigenbuero Souleiman.",
            "Rollen im Code: admin, expert, employee.",
        ],
    ),
    (
        "Was macht die App? (Kernfunktionen)",
        [
            "Kalender mit Urlaub, Krankheit, Samstags-Bereitschaft und Geburtstagen.",
            "Abwesenheitsantraege erstellen, bearbeiten, loeschen und verfolgen.",
            "Aufgaben (To-dos) zuweisen, filtern und auf erledigt setzen.",
            "Meeting-Punkte sammeln, naechsten Termin verwalten und archivieren.",
            "Dokumente mit der Kamera scannen, als PDF erzeugen, teilen oder in Drive ablegen.",
            "Provisionen ueber Einmal-Link fuer Online-Formular anstossen und verwalten.",
            "Admin-Bereich fuer Antraege, Nutzer, Bereitschaft, Provisionen und Automation-Status.",
        ],
    ),
    (
        "Wie funktioniert es? (kurze Architektur)",
        [
            "Frontend: SwiftUI-iOS-App mit zentralem AppState als Zustandsschicht.",
            "Login: Firebase Auth. Profil-Quelle: Firestore (users/invites).",
            "Daten in Firestore: users, invites, leaveRequests, tasks, commissions, meetingTopics, meetingMeta, meetingArchives.",
            "Serverlogik: Firebase Cloud Functions (onCall + HTTP), z. B. adminCreateUserInvite, clearMyUnreadBadge, setMyPushEnabled, uploadScanToDrive, createProvisionLink.",
            "Push: APNs + Firebase Messaging; Token in users/<uid>/devices/<deviceId>; Push-Tap wird ins Routing geleitet.",
            "Datenfluss: Nutzeraktion -> AppState -> Firestore/Functions -> Listener -> UI-Update in Echtzeit.",
        ],
    ),
    (
        "Wie starten? (minimal)",
        [
            "Xcode oeffnen und Projektdatei ../SVS App.xcodeproj laden.",
            "Scheme 'SVS App' waehlen und auf Simulator oder iPhone starten.",
            "Beim ersten Start mit vorhandener E-Mail/Passwort anmelden.",
            "Hinweis fuer Scanner: auf Simulator teils nicht unterstuetzt (laut Code).",
            "Test-Login-Daten: Not found in repo.",
            "Vollstaendige lokale Setup-Doku fuer Backend/Emulatoren: Not found in repo.",
        ],
    ),
    (
        "Geplante Aenderungen (laut Repo-Hinweisen)",
        [
            "Push-Tap soll spaeter echte Navigation oeffnen (aktuell vor allem Logging).",
            "Admin-Automation 'UltraExpert-Akten oeffnen' ist als Platzhalter markiert.",
            "Manueller Start der Make-Automatisierung ist als Platzhalter markiert.",
            "Weitere Listener-Stops sind als spaeterer Schritt kommentiert.",
        ],
    ),
]


def render(scale: float) -> tuple[bool, float]:
    fig = plt.figure(figsize=(8.27, 11.69))  # A4 portrait
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_axis_off()

    x = 0.08
    y = 0.965

    title_size = 19 * scale
    subtitle_size = 9.8 * scale
    heading_size = 12.4 * scale
    body_size = 10.2 * scale

    title_h = 0.036 * scale
    subtitle_h = 0.020 * scale
    heading_gap = 0.008 * scale
    section_gap = 0.010 * scale
    line_h = 0.0205 * scale

    ax.text(x, y, title, fontsize=title_size, weight="bold", va="top", ha="left")
    y -= title_h
    ax.text(x, y, subtitle, fontsize=subtitle_size, color="#444", va="top", ha="left")
    y -= (subtitle_h + 0.012 * scale)

    wrapper = textwrap.TextWrapper(width=92, break_long_words=False, replace_whitespace=False)

    for heading, items in sections:
        ax.text(x, y, heading, fontsize=heading_size, weight="bold", va="top", ha="left")
        y -= (line_h + heading_gap)

        for item in items:
            wrapped_lines = wrapper.wrap(item)
            if len(wrapped_lines) == 0:
                wrapped_lines = [""]
            for idx, line in enumerate(wrapped_lines):
                prefix = "- " if idx == 0 else "  "
                ax.text(x + 0.006, y, f"{prefix}{line}", fontsize=body_size, va="top", ha="left")
                y -= line_h

        y -= section_gap

    if y < 0.05:
        plt.close(fig)
        return False, y

    with PdfPages(out_path) as pdf:
        pdf.savefig(fig)
    plt.close(fig)
    return True, y


fitted = False
last_y = -1.0
for s in [1.0, 0.97, 0.94, 0.91, 0.88, 0.85]:
    ok, yy = render(s)
    last_y = yy
    if ok:
        fitted = True
        break

if not fitted:
    raise RuntimeError(f"Could not fit content on one page. Last y={last_y:.4f}")

print(out_path.resolve())
