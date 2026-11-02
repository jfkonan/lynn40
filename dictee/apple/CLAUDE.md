# Dictée (dictée via OpenAI : clavier iOS et app de barre des menus macOS)

Lis d'abord `HANDOFF.md` : il décrit l'architecture, les étapes de compilation, la check-list de recette
et les points à risque connus. Réponds à l'utilisateur en français.

Règles rapides :
- `project.yml` (XcodeGen) est la source de vérité ; `Dictee.xcodeproj` est généré et ignoré par git.
- La signature se règle uniquement dans `Config/Signing.xcconfig`.
- Le clavier n'accède ni au micro ni à la clé API : tout passe par l'app via l'App Group et les notifications Darwin.
- Après une modification : `xcodegen generate` puis `xcodebuild … test` (voir HANDOFF.md), schéma `Dictee` (iOS) et schéma `DicteeMac` (macOS).
- Le comportement commun iOS / macOS / Windows est défini dans `../SPEC.md` : le modifier là d'abord.
- Cible macOS `DicteeMac` (dossier `Mac/`, tests dans `Mac/Tests`) : app `LSUIElement` sans sandbox, raccourci global
  (Fn via NSEvent, ⌥Espace via Carbon), insertion par presse-papiers + ⌘V simulé. Voir la section « macOS » de HANDOFF.md.
- `Core/` et `Shared/` sont compilés pour iOS **et** macOS : toute modification doit compiler sur les deux (`#if os(iOS)` si besoin).
- Closures rappelées par le système sur un autre thread (tap audio, autorisation micro) : à créer hors `@MainActor`
  (fonction `nonisolated static`), sinon plantage à l'exécution.
