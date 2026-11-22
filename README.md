# Pixel Monitor

Widget de bureau Windows 11 au style pixel. Il affiche la charge CPU, la mémoire, les débits et l’espace libre du disque sélectionné, la batterie et, si le capteur est accessible, la température de la zone ACPI. Le menu permet de modifier la couleur, la taille, l’intervalle et les mesures visibles.

## Mode miniature

Choisis **Menu → Mode miniature** ou clique sur **[-]** dans le titre. La miniature affiche les mesures sélectionnées sur des lignes compactes. Clique sur **[+]** pour retrouver la vue complète. Un clic droit ouvre le menu dans les deux vues. Le mode choisi est mémorisé.

## Installation

Clone le dépôt sur le PC Windows, puis ouvre PowerShell dans le dossier du projet.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Le script compile le lanceur avec le compilateur .NET Framework de Windows, puis crée les raccourcis sur le Bureau et dans le menu Démarrer. Ouvre **Pixel Monitor** depuis l’un de ces raccourcis. Les réglages sont conservés sous `%LOCALAPPDATA%\PixelMonitor`.

## Température

Le widget utilise les zones thermiques ACPI exposées par les compteurs Windows. Si plusieurs zones sont disponibles, il affiche la plus chaude. Cette mesure peut différer de la température interne du CPU Package. Si le matériel ne publie aucune zone, le widget affiche « Zone thermique indisponible ». Aucun composant tiers ni droit administrateur ne sont requis.
