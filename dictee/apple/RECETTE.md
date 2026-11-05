# Recette de Dictée (iOS, clavier AZERTY, macOS)

Note chaque point **OK**, **KO** ou **partiel**. Les check-lists complètes sont dans `HANDOFF.md`
(« Check-list de recette (iOS) » et « Check-list de recette Mac ») : ne recopie ici que le résultat par rubrique
et le détail des points KO ou partiels (symptôme, cause probable, correctif, commit).

| Étape | Date | Où | État |
|---|---|---|---|
| Pré-vérification documentaire | 2026-11-05 | Session cloud (Linux, sans Xcode) | Faite, voir ci-dessous |
| Compilation et tests | à faire | Mac | Non commencée |
| App Mac | à faire | Mac | Non commencée |
| iPhone et clavier | à faire | iPhone réel | Non commencée |
| Banc d'essai des moteurs | à faire | Mac, avec les clés de l'utilisateur | Non commencé |

---

## 0. Pré-vérification documentaire (2026-11-05)

Faite depuis une session cloud **sans Mac, sans iPhone et sans clé** : rien n'a été compilé ni appelé.
Les pages officielles (developers.openai.com, docs.mistral.ai, learn.microsoft.com) étaient bloquées par le réseau
de la session. Seuls les extraits du moteur de recherche ont été lus. **Le banc d'essai reste la seule preuve.**

- Tests du banc (`python3 -I -m unittest discover -s dictee/bench`) : **54 tests OK**.
- `.gitignore` : `bench/echantillons/`, `bench/rapport-*`, `Dictee.xcodeproj/` et les trois `Info.plist` générés sont bien ignorés.

| Point | Valeur actuelle (SPEC §2 bis / §3) | Ce que dit la documentation publique | Verdict provisoire |
|---|---|---|---|
| Modèle OpenAI | `gpt-transcribe` | Page modèle `gpt-transcribe` sur developers.openai.com, point d'accès `v1/audio/transcriptions` (sortie annoncée en juillet 2026). | Probablement juste |
| Modèle Mistral | `voxtral-small-transcribe-3` | La page « Audio » et l'annonce Voxtral 3 citent **`voxtral-small-transcribe-3-0`**. Une version de la page « Bias context » utiliserait le nom court. | **Douteux** : comparer les deux noms au banc |
| `context_bias` Mistral | répété une fois par terme | Confirmé : un champ par entrée en lot. Biais optimisé pour l'anglais, **expérimental** pour les autres langues. | Format juste |
| Modèle Microsoft | `mai-transcribe-2` | La documentation Microsoft écrit **`MAI-Transcribe-2`** (majuscules). Une version plus ancienne de la page montre `mai-transcribe-1.5`. MAI-Transcribe-1 est retiré depuis le 20 août 2026. Le service est en préversion. | **Casse à vérifier** au banc |
| Format Azure | `transcriptions:transcribe?api-version=2025-10-15`, parties `audio` + `definition`, `enhancedMode` `{enabled, model}`, `phraseList` au même niveau qu'`enhancedMode` | Confirmé par la documentation, y compris la place de `phraseList` (sous `definition`, pas sous `enhancedMode`) et sa prise en charge par MAI-Transcribe-2. | Format juste |

**Aucun changement de code à ce stade**, car les sources se contredisent. À trancher au banc, avec ces commandes :

```bash
python3 bench.py echantillons --dry-run
python3 bench.py echantillons --compare-mistral-models voxtral-small-transcribe-3,voxtral-small-transcribe-3-0
python3 bench.py echantillons --compare-microsoft-models mai-transcribe-2,MAI-Transcribe-2
python3 bench.py echantillons --repeat 3
```

Si l'un des noms est refusé (400 ou 404 qui cite le modèle), corriger dans cet ordre :
`dictee/SPEC.md` (§2 bis, §3), `Shared/SharedStore.swift` (`Default`) et `TranscriptionProvider.suggestedModels`,
`dictee/windows` (valeurs par défaut et tests), `dictee/bench/bench.py` (`DEFAULT_MODELS`, `PRICES`), `HANDOFF.md` (point à risque n° 6).

---

## 1. Environnement

- Mac (modèle, macOS) :
- Xcode :
- XcodeGen :
- iPhone (modèle, iOS) :
- `DEVELOPMENT_TEAM` renseigné : oui / non (la valeur n'est pas recopiée ici)
- `BUNDLE_ID_PREFIX` :

## 2. Compilation et tests

| Commande | Résultat | Remarques |
|---|---|---|
| `xcodegen generate` | | |
| `xcodebuild -scheme Dictee … test` (simulateur iOS) | | |
| `xcodebuild -scheme DicteeMac … test` | | |
| CI GitHub (`.github/workflows/dictee.yml`) après les correctifs | | |

## 3. macOS (`DicteeMac`)

| Rubrique de la check-list Mac | État | Détail |
|---|---|---|
| Installation et premier lancement | | |
| Autorisations Micro et Accessibilité ; 🌐 réglé sur « Ne rien faire » | | |
| Raccourcis (Fn maintenu, ⌥Espace) | | |
| Insertion (presse-papiers + ⌘V, restauration) | | |
| Pastille, sons, Échap | | |
| Réglages, fournisseurs, styles | | |
| Lancement au démarrage | | |

## 4. iOS : app seule et session

| Rubrique | État | Détail |
|---|---|---|
| App seule (micro, clés, réglages) | | |
| Activation du clavier et accès complet | | |
| Ouverture de l'app depuis le clavier (**point à risque n° 1**) | | |
| Dictée dans Notes | | |
| Dictée dans Mail | | |
| Dictée dans Safari | | |
| Robustesse (arrière-plan, appel, écouteurs, app tuée, dictée longue, musique) | | |

## 5. Clavier AZERTY

| Rubrique | État | Détail |
|---|---|---|
| Frappe | | |
| Accents par appui long | | |
| Majuscules | | |
| 123 et #+= | | |
| Dictée et pastille | | |
| Styles d'écriture | | |
| Panneau rapide ☰ | | |
| Mode sombre | | |
| Tailles d'écran et paysage | | |
| Mémoire (< ~40 Mo, aucun `EXC_RESOURCE`) | | |
| VoiceOver | | |

## 6. Banc d'essai des moteurs

Nombre de dictées : — · Répétitions : — · Région Azure : —

| Configuration | WER moyen | Latence méd. | Latence p90 | Rappel vocab. | Erreurs | Coût/heure |
|---|---|---|---|---|---|---|
| | | | | | | |

Noms de modèles confirmés : OpenAI — · Mistral — · Microsoft —
Format Azure confirmé : oui / non
Choix retenu et raison :

## 7. Points KO et correctifs

| # | Point | Symptôme | Cause | Correctif | Test ajouté | Commit |
|---|---|---|---|---|---|---|
| | | | | | | |
