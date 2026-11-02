# Passation : compiler et tester Dictée sur Mac

Document destiné à l'agent (ou à la personne) qui compile et teste ce projet sur un Mac.
Le code a été écrit **sans compilateur Swift disponible** : attends-toi à quelques erreurs de compilation
mineures à corriger. L'architecture, elle, est volontaire. Ne la change pas sans raison (voir « Choix à préserver »).

Communique avec l'utilisateur **en français**.

## Ce que fait le projet

Un clavier iOS de dictée, sur le principe de Wispr Flow, qui utilise la clé API OpenAI de l'utilisateur.

| Cible | Rôle |
|---|---|
| `Dictee` (app) | Session audio en arrière-plan, enregistrement, appel OpenAI, réglages, clé API dans le Trousseau |
| `DicteeKeyboard` (extension) | Bouton micro, insertion du texte, touches de base (espace, effacer, retour, ponctuation, globe) |
| `DicteeTests` | Tests unitaires de la logique sans matériel (multipart, requêtes OpenAI, état partagé, insertion) |

Flux d'une dictée :

1. Clavier, micro touché sans session → ouvre `dictee://start` → l'app démarre `AVAudioEngine` (mode audio en arrière-plan).
2. L'utilisateur revient à son app (« ‹ » en haut à gauche).
3. Micro touché → notification Darwin `startRecording` → l'app écrit les tampons dans un WAV 16 kHz mono.
4. Micro retouché → `stopRecording` → l'app envoie le fichier à `POST /v1/audio/transcriptions`, puis, si l'option est active, nettoie le texte via `chat/completions`.
5. L'app écrit la `Transcript` dans les UserDefaults de l'App Group et poste `transcriptReady` → le clavier insère le texte via `textDocumentProxy`.

L'app rafraîchit `sessionExpiresAt` toutes les 2 s. Le clavier considère la session morte si cette date est dépassée.

## Arborescence

```
dictee/apple/
├── project.yml              # définition XcodeGen (source de vérité du projet)
├── Config/Signing.xcconfig  # équipe Apple, préfixe de bundle, App Group  ← à remplir
├── App/                     # cible Dictee (iOS)
├── Core/                    # code portable iOS + macOS (OpenAI, Trousseau, enregistreur WAV)
├── Keyboard/                # cible DicteeKeyboard
├── Mac/                     # cible DicteeMac (app de barre des menus macOS)
├── Shared/                  # état partagé, compilé dans toutes les cibles
└── Tests/                   # DicteeTests
```

`Dictee.xcodeproj` et les `Info.plist` sont **générés** par XcodeGen et ignorés par git.
Toute modification de structure (cibles, Info.plist, droits) se fait dans `project.yml`.

## Étapes

### 1. Prérequis
- Xcode 15 ou plus récent (iOS 16 minimum en cible).
- `brew install xcodegen`
- Un compte Apple Developer payant est recommandé : l'App Group doit être enregistré. Avec un compte gratuit, ça peut marcher, mais l'app expire au bout de 7 jours.

### 2. Signature
Remplis `Config/Signing.xcconfig` :
- `DEVELOPMENT_TEAM` : identifiant d'équipe (`security find-certificate` ou Xcode > Settings > Accounts).
- `BUNDLE_ID_PREFIX` : à changer si `com.jfkonan.dictee` est déjà pris.
- `APP_GROUP_ID` : dérivé automatiquement, laisse-le tel quel sauf conflit.

Demande l'identifiant d'équipe à l'utilisateur si tu ne peux pas le trouver.

### 3. Génération et compilation
```bash
cd dictee/apple
xcodegen generate
xcodebuild -project Dictee.xcodeproj -scheme Dictee \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```
(Adapte le nom du simulateur : `xcrun simctl list devices available`.)

### 4. Tests unitaires
```bash
xcodebuild -project Dictee.xcodeproj -scheme Dictee \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
```
Tous les tests de `Tests/DicteeTests.swift` doivent passer.

### 5. Test sur iPhone réel (indispensable)
Le simulateur ne permet de valider ni le micro en arrière-plan ni l'ouverture de l'app depuis le clavier.
Installe l'app sur l'iPhone (Xcode, avec l'appareil branché, ou TestFlight), puis déroule la check-list ci-dessous.

## Check-list de recette

Note chaque point comme OK, KO ou partiel, et décris les problèmes rencontrés.

**App seule**
- [ ] L'app se lance et la demande d'accès au micro s'affiche au premier démarrage de session.
- [ ] La clé API s'enregistre ; l'aperçu `sk-…abcd` s'affiche ; « Supprimer » l'efface.
- [ ] « Enregistrer un essai » → parler → « Arrêter et transcrire » → le texte français apparaît.
- [ ] Sans clé : message d'erreur clair, pas de plantage.
- [ ] Clé invalide : le message d'OpenAI (« Incorrect API key… ») s'affiche.

**Clavier**
- [ ] Le clavier apparaît dans Réglages > Général > Clavier > Claviers > Ajouter.
- [ ] Sans accès complet : cadenas sur le micro et explication.
- [ ] Avec accès complet, sans session : le micro ouvre l'app Dictée (**point à risque n° 1**).
- [ ] Retour à l'app d'origine par « ‹ » : le micro devient bleu (« Touchez pour dicter »).
- [ ] Dictée dans Notes, Messages, Mail et un champ Safari : le texte s'insère au curseur, avec une espace devant si besoin.
- [ ] La croix annule un enregistrement en cours, sans insertion.
- [ ] Globe, espace, effacer (appui long = répétition), retour et ponctuation fonctionnent.
- [ ] Mode sombre lisible.

**Robustesse**
- [ ] Session en arrière-plan : point orange visible ; elle s'arrête seule après la durée réglée sans dictée.
- [ ] Recevoir un appel pendant une session : pas de plantage ; le clavier redemande une session ensuite.
- [ ] Brancher ou débrancher des écouteurs pendant une session : la dictée suivante fonctionne.
- [ ] Tuer l'app depuis le sélecteur : en moins de 6 s, le clavier repasse en « démarrer une session ».
- [ ] Dictée longue (2 à 3 min) : transcription complète.
- [ ] Musique en cours pendant la session : elle continue (option `.mixWithOthers`).

## Points à risque connus

1. **Ouverture de l'app depuis le clavier** (`KeyboardViewController.openContainingApp`). Il n'existe pas d'API officielle. La méthode utilisée remonte la chaîne des répondeurs jusqu'à `UIApplication` et appelle `openURL:options:completionHandler:` via le runtime Objective-C.
   - **Si ça ne marche pas** : vérifie que la boucle trouve bien un `UIApplication` (ajoute des logs).
   - **Alternative 1** : appeler le sélecteur `openURL:` avec `perform(_:with:)`.
   - **Alternative 2** : un `Link`/bouton SwiftUI avec `openURL` dans l'environnement.
   - **Dernier recours** : le message « Ouvrez l'app Dictée » s'affiche déjà, et la session peut être lancée à la main depuis l'app.
2. **Démarrage de l'enregistrement en arrière-plan.** Le moteur audio tourne en continu depuis le premier plan, ce qui doit suffire. Si iOS coupe l'entrée micro en arrière-plan, vérifie :
   - que `UIBackgroundModes` contient bien `audio` dans l'Info.plist généré ;
   - que la catégorie de session est `.playAndRecord`.
3. **Vérifications d'isolation des acteurs Swift** : le bloc du tap audio et la demande d'accès au micro sont volontairement `nonisolated`.
   - Si l'app plante avec `dispatch_assert_queue` ou `_swift_task_checkIsolated`, cherche une closure créée dans un contexte `@MainActor` puis appelée par iOS sur un autre thread.
   - Le projet est en Swift 5 : ne passe pas en Swift 6 strict sans traiter ces cas.
4. **UserDefaults partagés entre processus** : ils peuvent avoir un léger retard. Si le clavier lit un état périmé juste après une notification, une relecture courte (asyncAfter 0,1 s) dans `KeyboardModel` peut suffire.
5. **Mémoire du clavier** : iOS limite fortement les extensions clavier (environ 48 à 70 Mo). Le clavier ne fait que de l'interface, ça devrait passer. Surveille quand même les éventuels arrêts `EXC_RESOURCE`.
6. **Noms de modèles OpenAI** : par défaut `gpt-4o-transcribe` et `gpt-4o-mini` (nettoyage). Ils sont modifiables dans l'app. Si OpenAI renvoie « model not found », vérifie les modèles disponibles sur le compte de l'utilisateur.

## Choix à préserver

- **Le clavier n'a jamais le micro ni la clé API** : iOS l'interdit pour le micro, et c'est un choix de sécurité pour la clé. Tout passe par l'app.
- **Clé API uniquement dans le Trousseau de l'app**, jamais dans l'App Group ni dans le code.
- **Audio en WAV 16 kHz mono** : environ 13 min maximum sous la limite de 25 Mo d'OpenAI. Plafond fixé à 12 min dans `DictationEngine.maxRecordingDuration`.
- **`project.yml` est la source de vérité** : ne committe pas `Dictee.xcodeproj`.

## Ce qu'il faut rendre

1. Les corrections de compilation, en commits courts et explicites, sur la branche `claude/clavier-dictee-ios`.
2. La check-list ci-dessus remplie, dans un fichier `dictee/apple/RECETTE.md` daté.
3. Pour chaque point KO : symptôme, cause probable, correctif appliqué ou proposé.
4. Des captures d’écran du clavier en mode clair et en mode sombre si possible.
