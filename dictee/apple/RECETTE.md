# Recette de Dictée (iOS, clavier AZERTY, macOS)

Note chaque point **OK**, **KO** ou **partiel**. Les check-lists complètes sont dans `HANDOFF.md`
(« Check-list de recette (iOS) » et « Check-list de recette Mac ») : ne recopie ici que le résultat par rubrique
et le détail des points KO ou partiels (symptôme, cause probable, correctif, commit).

| Étape | Date | Où | État |
|---|---|---|---|
| Pré-vérification documentaire | 2026-11-05 | Session cloud (Linux, sans Xcode) | Faite, voir ci-dessous |
| Compilation et tests | 2026-11-06 | Mac | Faite, tout passe |
| App Mac | 2026-11-06 | Mac | Faite sauf dictée réelle (pas de clé) |
| iPhone et clavier | 2026-11-06 | iPhone réel | Frappe et ouverture de l'app OK ; dictée non testée (pas de clé) |
| Banc d'essai des moteurs | à faire | Mac, avec les clés de l'utilisateur | Bloqué : aucune clé API disponible. Les noms de modèles (§0) restent à trancher |

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

Complément du 2026-11-07 : la page de présentation audio de Mistral (docs.mistral.ai, « overview ») écrit
`voxtral-small-transcribe-3-0` et `voxtral-mini-transcribe-realtime-3-0`, alors que le guide « transcribe in realtime »
écrit `voxtral-mini-transcribe-realtime-3`. Les deux formes coexistent dans la documentation officielle.

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

- Mac (modèle, macOS) : MacBook Air (Mac16,13), macOS 27.3
- Xcode : 27.2 (27B52)
- XcodeGen : 2.46.0
- iPhone (modèle, iOS) : iPhone 18 Pro, iOS 27.3
- `DEVELOPMENT_TEAM` renseigné : oui, compte gratuit (Personal Team) ; la valeur n'est pas recopiée ici
- `BUNDLE_ID_PREFIX` : `com.jfkonan`

## 2. Compilation et tests

| Commande | Résultat | Remarques |
|---|---|---|
| `xcodegen generate` | OK | |
| `xcodebuild -scheme Dictee … test` (simulateur iOS) | OK, 89 tests | iPhone 17, iOS 27.2 |
| `xcodebuild -scheme DicteeMac … test` | OK, 39 tests | Signature ad hoc |
| CI GitHub (`.github/workflows/dictee.yml`) après les correctifs | OK | Verte après afc3768 |

## 3. macOS (`DicteeMac`)

| Rubrique de la check-list Mac | État | Détail |
|---|---|---|
| Installation et premier lancement | OK | Icône dans la barre des menus (peut être masquée par l'encoche), rien dans le Dock |
| Autorisations Micro et Accessibilité ; 🌐 réglé sur « Ne rien faire » | OK | |
| Raccourcis (Fn maintenu, ⌥Espace) | partiel | ⌥Espace OK ; Fn KO sur ce Mac, voir §7 |
| Insertion (presse-papiers + ⌘V, restauration) | OK (dictée dans Notes avec ⌥Espace) | Restauration du presse-papiers non vérifiée |
| Transcription en continu (OpenAI) | OK | 2026-11-07, dictée de 10 s : session prête +1,4 s après l'appui, 47 deltas, texte final 0,85 s après le relâchement ; nettoyage `gpt-4o-mini` +2,0 s (style Formel) → 2,85 s au total. Journal : `~/Library/Logs/Dictee/dictee.log` |
| Latence | OK après réglage | Jugée lente avec « Nettoyer le texte » activé (second appel OpenAI, `gpt-4o-mini`) ; nettement plus rapide une fois désactivé. Modèle `gpt-transcribe` conservé |
| Pastille, sons, Échap | non testé | À tester avec ⌥Espace |
| Réglages, fournisseurs, styles | partiel | Fenêtre « Réglages… » KO au départ (derrière les autres), corrigée ; voir §7 |
| Lancement au démarrage | non testé | |

## 4. iOS : app seule et session

| Rubrique | État | Détail |
|---|---|---|
| App seule (micro, clés, réglages) | OK | Clé OpenAI enregistrée, transcription réussie |
| Activation du clavier et accès complet | OK | |
| Ouverture de l'app depuis le clavier (**point à risque n° 1**) | OK | Ouverture et retour dans Notes corrects |
| Dictée dans Notes | OK après correctif | Texte jamais inséré au départ, voir §7 |
| Dictée dans Mail | non testé | Demande une clé API |
| Dictée dans Safari | non testé | Demande une clé API |
| Robustesse (arrière-plan, appel, écouteurs, app tuée, dictée longue, musique) | partiel | Session en arrière-plan et point orange OK ; reste non testé (demande une dictée réelle, donc une clé) |

## 5. Clavier AZERTY

| Rubrique | État | Détail |
|---|---|---|
| Frappe | OK | Points 1 à 5 de la série sans clé |
| Barre de suggestions | OK | Ajoutée le 2026-11-06 (496cf72, c894db4) ; validée sur iPhone 18 Pro |
| Correction automatique | OK | Ajoutée le 2026-11-06 (4531704, 1519bb7) ; validée sur iPhone 18 Pro |
| Espace intelligente avant la ponctuation | OK | Ajoutée le 2026-11-06 (c59de3b) ; validée sur iPhone 18 Pro |
| Accents par appui long | OK | |
| Majuscules | OK | |
| 123 et #+= | OK | |
| Dictée et pastille | OK | Dictée réelle dans Notes OK |
| Styles d'écriture | non testé | Demande une clé OpenAI |
| Panneau rapide ☰ | OK (ouverture et fermeture) | Historique, fournisseur, langue non testés |
| Mode sombre | OK après correctif | Clavier resté clair en mode sombre ; corrigé, voir §7 |
| Tailles d'écran et paysage | partiel | Paysage OK sur iPhone 18 Pro ; iPhone SE et Pro Max non testés (un seul appareil) |
| Mémoire (< ~40 Mo, aucun `EXC_RESOURCE`) | non testé | Demande le Debug Navigator de Xcode |
| VoiceOver | OK | |

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
| 1 | Mac : fenêtre « Réglages… » | S'ouvrait derrière les autres fenêtres | Le menu de la barre des menus se ferme après le clic et macOS rend la main à l'app précédente ; app LSUIElement | Remise au premier plan immédiate puis 0,15 s plus tard (`orderFrontRegardless`) | Non (comportement d'interface) | afc3768, b6237f3 (garde si fermée) |
| 2 | Clavier : mode sombre | Clavier entièrement clair alors que le système est en sombre | Le mode de l'extension ne se propageait pas à la vue SwiftUI | Mode appliqué explicitement (`environment(\.colorScheme)`) et réévalué à chaque changement de mode | Oui, `KeyboardAppearanceLogicTests` (revue : champ clair respecté, plus d'override, iOS 17) | 3e308c0, b6237f3 |
| 3 | Mac : touche Fn (point à risque) | Fn ne déclenche rien | Sur ce MacBook Air (Mac16,13, macOS 27.3), l'événement `flagsChanged` (keyCode 63) arrive mais sans le drapeau `.function`, et un seul événement par geste : appui et relâchement indiscernables | Aucun pour l'instant : contournement par ⌥Espace. Pistes : CGEventTap ou IOHID | Non | non corrigé |
| 4 | iPhone : texte non inséré | Transcription réussie (visible dans l'app) mais rien n'apparaît dans le champ | Lecture unique des UserDefaults partagés au signal `transcriptReady`, parfois en retard (point à risque n° 4) ; transcription marquée consommée avant insertion | Relectures à 0,15 / 0,5 / 1,5 s, vérification au retour `idle`, consommation après insertion réelle | Non (inter-processus) | 1bcc5f1 |
