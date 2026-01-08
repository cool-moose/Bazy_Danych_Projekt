# Hotel Aurora - System Zarządzania Hotelem

Projekt na Bazy Danych autorstwa: 

Celem projektu było stworzenie lokalnego systemu zarządzania hotelem.

Głównym plikiem jest sama baza danych baza.sql oraz jej dokumentacja DOKUMENTACJA_BAZY.md

Przygotowaliśmy także aplikację webową do zarządzania bazą w celach demonstracyjnych

W celu zaimportowania bazy danych oraz uruchomienia aplikacji demonstracyjnej uruchom skrypt konfiguracyjny run.sh

UWAGA!! Skrypt ten został utworzony wyłączne dla systemów Linux, w zależności od środowiska potrzebna może być także zmiana wartości zmiennych znajdujacych się na poczatku skryptu


## Struktura projektu

```
BD_Projekt/
├── BD_App/                 # Aplikacja Flask
│   ├── app.py              # Główny plik aplikacji
│   ├── config.py           # Konfiguracja
│   ├── static/             # CSS, favicon
│   └── templates/          # Szablony HTML
├── baza.sql                # Struktura bazy danych
├── DOKUMENTACJA_BAZY.md    # Dokumentacja techniczna bazy danych
├── README.md               # Ten plik
└── run.sh                  # Skrypt konfiguracyjny dla systemów Linux
```

