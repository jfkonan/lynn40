# Dictée (clavier iOS de dictée via OpenAI)

Lis d'abord `HANDOFF.md` : il décrit l'architecture, les étapes de compilation, la check-list de recette
et les points à risque connus. Réponds à l'utilisateur en français.

Règles rapides :
- `project.yml` (XcodeGen) est la source de vérité ; `Dictee.xcodeproj` est généré et ignoré par git.
- La signature se règle uniquement dans `Config/Signing.xcconfig`.
- Le clavier n'accède ni au micro ni à la clé API : tout passe par l'app via l'App Group et les notifications Darwin.
- Après une modification : `xcodegen generate` puis `xcodebuild … test` (voir HANDOFF.md).
