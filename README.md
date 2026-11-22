# Pixel Monitor

Widget de bureau Windows 11 au style pixel. Il affiche la charge CPU, la mémoire, les débits et l’espace libre du disque sélectionné, la batterie et, si le capteur est accessible, la température CPU. Le menu permet de modifier la couleur, la taille, l’intervalle et les mesures visibles.

## Installation

Clone le dépôt sur le PC Windows, puis ouvre PowerShell dans le dossier du projet.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Le script compile le lanceur avec le compilateur .NET Framework de Windows, puis crée les raccourcis sur le Bureau et dans le menu Démarrer. Ouvre **Pixel Monitor** depuis l’un de ces raccourcis. Les réglages sont conservés sous `%LOCALAPPDATA%\PixelMonitor`.

## Température CPU

Sur un nouveau PC, lance l’installeur avec le paramètre `-WithTemperature` pour télécharger la bibliothèque de la version officielle de Libre Hardware Monitor et vérifier son empreinte.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -WithTemperature
```

Installe ensuite [PawnIO](https://github.com/namazso/PawnIO.Setup/releases/latest) si nécessaire. Dans le widget, sélectionne **Menu → Accès température (administrateur)** et valide la demande administrateur. La disponibilité de la mesure dépend du matériel et des droits Windows.
