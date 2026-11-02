# Dictée pour Windows

Lis d'abord `HANDOFF.md` : compilation, publication, check-list de recette Windows et points à risque connus.
Le comportement commun aux trois plateformes est fixé par `../SPEC.md` : toute modification de comportement s'y fait d'abord.
Réponds à l'utilisateur en français. Interface, messages et commentaires en français ; identifiants de code en anglais.

Règles rapides :
- `src/Dictee.Core` reste en `net8.0` pur, sans aucune dépendance Windows : c'est ce qui est testé (`tests/Dictee.Core.Tests`).
- Tout ce qui touche Win32, WinForms, NAudio ou DPAPI va dans `src/Dictee.Windows`.
- La clé API n'apparaît jamais dans le code, les journaux, `settings.json` ou un message d'erreur.
- Après une modification : `dotnet build Dictee.sln -c Release` puis `dotnet test Dictee.sln -c Release`.
