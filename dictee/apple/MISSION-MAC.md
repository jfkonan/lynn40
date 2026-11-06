# Mission : recette de Dictée sur Mac et iPhone

À exécuter par une session Claude Code **qui tourne sur le Mac** (Xcode installé, iPhone branché).
Réponds toujours en français. À supprimer une fois la recette terminée.

## Avant tout
`git fetch origin && git checkout claude/clavier-dictee-ios && git pull`, puis lis `dictee/SPEC.md`,
`dictee/apple/HANDOFF.md`, `dictee/apple/CLAUDE.md` et `dictee/apple/RECETTE.md`. La section 0 de ce dernier
liste les noms de modèles à trancher (Mistral `-3-0`, casse `MAI-Transcribe-2`).

## Étapes
1. **Prérequis.** Vérifie Xcode, installe XcodeGen (`brew install xcodegen`). Demande l'identifiant d'équipe Apple
   et remplis `Config/Signing.xcconfig` (change `BUNDLE_ID_PREFIX` si besoin).
2. **Compilation et tests.** `xcodegen generate`, puis les tests sur le simulateur iOS **et** sur macOS (commandes dans HANDOFF.md).
3. **App Mac.** Lance `DicteeMac`, autorisations Micro et Accessibilité, touche 🌐 sur « Ne rien faire »,
   puis la check-list macOS de HANDOFF.md, avec l'utilisateur.
4. **iPhone.** Installe l'app et le clavier, active le clavier et l'« accès complet », puis les check-lists iOS et clavier
   AZERTY : frappe, accents par appui long, majuscules, 123 et #+=, panneau ☰, styles, ouverture de l'app depuis le clavier
   (point à risque n° 1), dictée dans Notes, Mail et Safari, mode sombre, mémoire.
5. **Banc d'essai.** 20 à 30 dictées juridiques fictives ou anonymisées, avec leur texte de référence, dans
   `dictee/bench/echantillons/` (ignoré par git). L'utilisateur saisit ses clés avec `read -s` : ne les affiche jamais,
   ne les écris jamais dans un fichier. Lance `--dry-run`, puis
   `--compare-mistral-models voxtral-small-transcribe-3,voxtral-small-transcribe-3-0`,
   `--compare-microsoft-models mai-transcribe-2,MAI-Transcribe-2`, puis `--repeat 3`.
   Si un nom ou un format est faux : corrige `dictee/SPEC.md`, puis `Shared/SharedStore.swift`,
   `Shared/TranscriptionProvider.swift`, `dictee/windows/src/Dictee.Core/DicteeSettings.cs` et leurs tests,
   `dictee/bench/bench.py`, et le point à risque n° 6 de HANDOFF.md.
6. **Corrections.** Pour chaque point KO : cause, correctif minimal, test si possible, commit court sur
   `claude/clavier-dictee-ios`, push. La CI (`.github/workflows/dictee.yml`) doit rester verte.
7. **Bilan.** Remplis et date `dictee/apple/RECETTE.md`.

## Règles
- `project.yml` est la source de vérité : ne committe ni `Dictee.xcodeproj` ni les `Info.plist` générés.
- Le clavier n'a jamais accès au micro ni aux clés : tout passe par l'app via l'App Group.
- Clés API dans le Trousseau uniquement : jamais dans le code, les journaux, un commit ou le chat.
  L'identifiant d'équipe ne va pas dans RECETTE.md.
- Dépôt public : aucun enregistrement, aucune clé, aucune donnée client dans un commit.
