# Passation : compiler et tester Dictée (iOS et macOS) sur Mac

Document destiné à l'agent (ou à la personne) qui compile et teste ce projet sur un Mac.
Le code a été écrit **sans compilateur Swift disponible** : attends-toi à quelques erreurs de compilation
mineures à corriger. L'architecture, elle, est volontaire. Ne la change pas sans raison (voir « Choix à préserver »).

Communique avec l'utilisateur **en français**.

## Ce que fait le projet

Dictée, sur le principe de Wispr Flow, transcrit la voix avec la clé API de l'utilisateur, chez le fournisseur qu'il choisit
(**OpenAI** par défaut, **Mistral** ou **Microsoft** Azure MAI-Transcribe-2), et insère le texte au curseur.
Le comportement commun aux trois plateformes est défini dans `../SPEC.md` (référence à suivre).
Ce dossier contient la version iOS (clavier) et la version macOS (barre des menus) ; la version Windows est dans `../windows/`.

| Cible | Plateforme | Rôle |
|---|---|---|
| `Dictee` (app) | iOS | Session audio en arrière-plan, enregistrement, appel au fournisseur de transcription, réglages, clés API dans le Trousseau |
| `DicteeKeyboard` (extension) | iOS | Bouton micro, insertion du texte, touches de base (espace, effacer, retour, ponctuation, globe) |
| `DicteeTests` | iOS | Tests unitaires de la logique sans matériel (multipart, requêtes OpenAI, Mistral et Azure, parseurs, état partagé, insertion) |
| `DicteeMac` (app) | macOS 13+ | App de barre des menus : raccourci global, enregistrement, transcription, collage au curseur (voir section « macOS ») |
| `DicteeMacTests` | macOS | Tests unitaires Mac sans matériel (raccourcis, presse-papiers, réglages, règles du pipeline, requêtes des trois fournisseurs) |

Flux d'une dictée sur iOS :

1. Clavier, micro touché sans session → ouvre `dictee://start` → l'app démarre `AVAudioEngine` (mode audio en arrière-plan).
2. L'utilisateur revient à son app (« ‹ » en haut à gauche).
3. Micro touché → notification Darwin `startRecording` → l'app écrit les tampons dans un WAV 16 kHz mono.
4. Micro retouché → `stopRecording` → l'app envoie le fichier au fournisseur choisi (`TranscriptionService.transcribe`), puis, si l'option est active, nettoie le texte via `chat/completions` chez OpenAI.
5. L'app écrit la `Transcript` dans les UserDefaults de l'App Group et poste `transcriptReady` → le clavier insère le texte via `textDocumentProxy`.

L'app rafraîchit `sessionExpiresAt` toutes les 2 s. Le clavier considère la session morte si cette date est dépassée.

## Arborescence

```
dictee/apple/
├── project.yml              # définition XcodeGen (source de vérité du projet)
├── Config/Signing.xcconfig  # équipe Apple, préfixe de bundle, App Group  ← à remplir
├── App/                     # cible Dictee (iOS)
├── Core/                    # code portable iOS + macOS (fournisseurs de transcription, OpenAI, Trousseau, enregistreur WAV, règles du pipeline)
├── Keyboard/                # cible DicteeKeyboard
├── Mac/                     # cible DicteeMac (app de barre des menus macOS) ; Mac/Tests = DicteeMacTests
├── Shared/                  # état partagé, compilé dans toutes les cibles
└── Tests/                   # DicteeTests
```

`Dictee.xcodeproj` et les `Info.plist` sont **générés** par XcodeGen et ignorés par git.
Toute modification de structure (cibles, Info.plist, droits) se fait dans `project.yml`.

## Fournisseurs de transcription (SPEC §2 bis)

> **Avertissement** : les API Mistral et Azure, et les noms de modèles (`gpt-transcribe`, `voxtral-small-transcribe-3`,
> `voxtral-mini-transcribe-3`, `mai-transcribe-2`), ont été décrits d'après des documentations publiques de novembre 2026,
> **sans vérification en direct**. Les noms de modèles et le format Azure (URL, `api-version=2025-10-15`, partie
> `definition`, forme de la réponse) sont **à confirmer à la première recette** (l'outil `dictee/bench/` le fait).
> Si un fournisseur refuse la requête, son message s'affiche tel quel (« Erreur Mistral (422) : … ») : corriger
> le constructeur de requête concerné dans `Core/TranscriptionService.swift` et son test.

| Élément | Où | Rôle |
|---|---|---|
| `TranscriptionProvider` | `Core/TranscriptionProvider.swift` | `openai` / `mistral` / `microsoft`, nom affiché, compte du Trousseau, modèles proposés, phrase d'aide |
| `TranscriptionService.transcribe(provider:audioURL:settings:keys:)` | `Core/TranscriptionService.swift` | Point d'entrée unique, appelé par `DictationEngine` (iOS) et `DictationController` (Mac) |
| `makeMistralRequest`, `makeAzureRequest`, `azureDefinition` | idem | Constructeurs de requêtes purs, testés sans réseau (`OpenAIClient.makeTranscriptionRequest` reste celui d'OpenAI) |
| `vocabularyTerms`, `azureLocale(for:)`, `mistralLanguage(for:)` | idem | Découpage du vocabulaire (100 termes, sans doublons), locale Azure, langue à 2 lettres pour Mistral |
| `parseTextResponse`, `parseAzureTranscription`, `errorMessage(from:)` | idem | Réponses (`text` ; `combinedPhrases[0].text`, sinon `phrases[].text`) et erreurs (`error.message`, `message`, `detail`) |
| `TranscriptionService.cleanUp` | idem | Nettoyage toujours chez OpenAI ; sauté sans erreur s'il n'y a pas de clé OpenAI |
| `KeychainStore` | `Core/KeychainStore.swift` | Une clé par fournisseur : service `com.dictee.openai`, comptes `apiKey` (OpenAI, inchangé), `apiKey.mistral`, `apiKey.microsoft` |
| `SharedStore` | `Shared/SharedStore.swift` | `dictee.settings.provider`, `mistralModel`, `microsoftModel`, `azureRegion` (repli sur le défaut si vide). Le type `TranscriptionProvider` n'est pas dans `Shared/` : le clavier n'en a pas besoin |

Défauts : fournisseur `openai`, modèle OpenAI `gpt-transcribe`, Mistral `voxtral-small-transcribe-3`,
Microsoft `mai-transcribe-2`, région Azure `eastus`. Messages : « Clé API Mistral manquante. Ajoutez-la dans les
réglages de Dictée. », « Erreur Microsoft (401) : … ». Les clés n'apparaissent jamais dans un message d'erreur
(remplacées par leur aperçu `sk-…abcd`).

## Étapes

### 1. Prérequis
- Xcode 15 ou plus récent (iOS 16 et macOS 13 minimum en cible ; la CI utilise Xcode 16 sur macos-15).
- `brew install xcodegen`
- Un compte Apple Developer payant est recommandé : l'App Group doit être enregistré. Pour le Mac, aucun App Group n'est nécessaire (voir section « macOS »). Avec un compte gratuit, ça peut marcher, mais l'app expire au bout de 7 jours.

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

## Check-list de recette (iOS)

Note chaque point comme OK, KO ou partiel, et décris les problèmes rencontrés.

**App seule**
- [ ] L'app se lance et la demande d'accès au micro s'affiche au premier démarrage de session.
- [ ] La clé API s'enregistre ; l'aperçu `sk-…abcd` s'affiche ; « Supprimer » l'efface.
- [ ] « Enregistrer un essai » → parler → « Arrêter et transcrire » → le texte français apparaît.
- [ ] Sans clé : message d'erreur clair, pas de plantage.
- [ ] Clé invalide : le message d'OpenAI (« Incorrect API key… ») s'affiche.
- [ ] Une clé OpenAI enregistrée avant cette version est toujours reconnue (compte Trousseau `apiKey` inchangé).

**Fournisseurs** (voir l'avertissement de la section « Fournisseurs de transcription »)
- [ ] Le Picker « Fournisseur » propose OpenAI, Mistral et Microsoft ; la section modèle change avec lui ;
  la phrase d'aide s'affiche (« Mistral : hébergé dans l'UE », « Microsoft : preview, prix promotionnel jusqu'au 31/12/2026 »).
- [ ] Chaque fournisseur a son champ de clé (aperçu, « Supprimer ») ; avec le nettoyage activé, la clé OpenAI est aussi proposée.
- [ ] **OpenAI** : essai avec `gpt-transcribe` (défaut). Si « model not found », essayer `gpt-4o-transcribe` et le noter.
- [ ] **Mistral** : clé Mistral, essai avec `voxtral-small-transcribe-3` puis `voxtral-mini-transcribe-3` ; les sigles
  du vocabulaire (OHADA, AUSCGIE…) sont bien orthographiés (`context_bias`). Noter tout refus (« Erreur Mistral (422) : … »).
- [ ] **Microsoft** : clé Azure AI Speech et région de la ressource (ex. `westeurope`), essai avec `mai-transcribe-2`.
  Noter tout refus (« Erreur Microsoft (…) : … ») : URL, `api-version`, partie `definition` ou forme de la réponse à corriger.
- [ ] Région Azure invalide (ex. `west europe`) : « Région Azure invalide… », sans appel réseau.
- [ ] Fournisseur sans clé : « Clé API Mistral manquante. Ajoutez-la dans les réglages de Dictée. » (idem Microsoft).
- [ ] Mistral ou Microsoft avec le nettoyage activé mais sans clé OpenAI : le texte brut est inséré, sans erreur.
- [ ] Mistral ou Microsoft avec le nettoyage activé et une clé OpenAI : le texte est nettoyé.

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

## Points à risque connus (iOS)

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
6. **Noms de modèles** : par défaut `gpt-transcribe` (OpenAI), `voxtral-small-transcribe-3` (Mistral), `mai-transcribe-2` (Microsoft) et `gpt-4o-mini` (nettoyage), **non vérifiés en direct**. Ils sont modifiables dans l'app (saisie libre). Si un fournisseur renvoie « model not found », vérifie les modèles disponibles sur le compte de l'utilisateur, puis corrige `SharedStore.Default` et `TranscriptionProvider.suggestedModels`.
7. **Formats Mistral et Azure** : décrits d'après la documentation, non vérifiés. Mistral : champ `context_bias` répété, ni `prompt` ni `response_format`. Azure : `transcriptions:transcribe?api-version=2025-10-15`, parties `audio` et `definition` (JSON), réponse lue dans `combinedPhrases[0].text`. En cas d'écart, corriger `Core/TranscriptionService.swift` et les tests correspondants.

## macOS (cible `DicteeMac`)

### Principe

App de barre des menus (pas d'icône dans le Dock, `LSUIElement`), comme Wispr Flow :

1. L'utilisateur **maintient Fn** (défaut) ou appuie sur **⌥Espace** (au choix, en mode « maintenir » ou « basculer »).
2. `AudioCapture` démarre un `AVAudioEngine` neuf ; le tap alimente `BufferRecorder` (WAV 16 kHz mono, fichier temporaire).
   La pastille flottante affiche « Écoute… » et le niveau ; un son « Tink » marque le début. Son et pastille
   arrivent 0,2 s après l'appui (le micro, lui, tourne dès l'appui) : un Fn+flèche annulé aussitôt ne fait ni son
   ni clignotement. En mode « basculer » avec Fn, la dictée démarre et s'arrête au **relâchement** de Fn, sauf si Fn
   a servi à un raccourci (Fn+flèche…).
3. Au relâchement : son « Pop », « Transcription… », envoi au fournisseur choisi (`Core/TranscriptionService`), puis
   nettoyage optionnel chez OpenAI avec repli sur le texte brut. Moins de 0,3 s : abandon silencieux. 12 min : arrêt automatique. Ces règles
   (durées, repli, « Aucune parole détectée. ») sont des fonctions pures de `Core/TranscriptionRules`, testées.
4. `TextInserter` sauvegarde tout le presse-papiers, y place le texte, simule ⌘V, puis restaure le presse-papiers
   après 1 s si son `changeCount` n'a pas bougé. Sans autorisation Accessibilité : « Texte copié : collez-le avec ⌘V ».
5. Le fichier audio est supprimé dans tous les cas, y compris si l'on quitte pendant l'écoute ou la transcription
   (`applicationWillTerminate`), et les restes d'une session interrompue sont purgés au lancement.
   **Échap** (ou ⌥Échap, ⌥ étant encore tenue avec ⌥Espace) pendant l'enregistrement annule.
6. Changement de micro pendant l'écoute (AirPods qui passent en profil HFP, casque branché, micro débranché) :
   `AudioCapture` relance un moteur neuf dans le même fichier (3 fois au plus), puis, en dernier recours, transcrit
   ce qui a été dit.

| Fichier (`Mac/`) | Rôle |
|---|---|
| `DicteeMacApp.swift` | `@main`, `MenuBarExtra` (icône selon l'état), `AppDelegate` qui lance le contrôleur |
| `DictationController.swift` | Contrôleur central `@MainActor` : états SPEC §7, raccourci → micro → transcription → insertion |
| `HotkeyLogic.swift` | Logique pure testable : `FnKeyTracker`, `HotkeyLogic.action`, symbole de menu par état |
| `HotkeyManager.swift` | Moniteurs NSEvent (Fn, `flagsChanged` keyCode 63), Échap pendant l'enregistrement |
| `CarbonHotKey.swift` | `RegisterEventHotKey` + `InstallEventHandler` (callback C sans capture, instance via `userData`) |
| `AudioCapture.swift` | `AVAudioEngine` + tap (bloc créé dans une fonction `nonisolated static`) |
| `PasteboardSnapshot.swift` / `TextInserter.swift` | Instantané complet du presse-papiers, ⌘V simulé (`CGEvent`, `.cghidEventTap`), restauration |
| `OverlayPanel.swift` | Pastille `NSPanel` non activante, en bas au centre de l'écran du pointeur, contenu SwiftUI |
| `SettingsWindowController.swift` / `SettingsView.swift` | Fenêtre de réglages (`NSWindow` + `NSHostingController`, pas de scène `Settings`) |
| `MenuContent.swift` | Menu : état, « Dernière transcription » (copier), « Réglages… », « Quitter » |
| `MacSettings.swift` | Réglages propres au Mac (`dictee.settings.hotkey`, `hotkeyMode`, `soundsEnabled`, `restoreClipboard`, `launchAtLogin`). Comme sur iOS, les clés de SPEC §3 sont stockées avec le préfixe `dictee.settings.` |
| `Permissions.swift` / `LoginItem.swift` | Micro, Accessibilité, ouverture des Réglages Système ; `SMAppService.mainApp` |

Code partagé avec iOS : `Core/` (TranscriptionProvider, TranscriptionService, OpenAIClient, KeychainStore, BufferRecorder, TranscriptionRules) et `Shared/`
(SharedStore, TextJoiner…). `Shared/DarwinNotifier.swift` (signaux app ↔ clavier iOS) est exclu de `DicteeMac` dans `project.yml`.
Sur Mac, l'Info.plist n'a pas de clé `AppGroupIdentifier` : `AppGroup.defaults` vaut `nil` et `SharedStore`
retombe sur `UserDefaults.standard`. **C'est voulu** (pas d'App Group sur Mac).

### Compilation

```bash
cd dictee/apple
xcodegen generate
# Vérification rapide, sans signature (c'est ce que fait la CI GitHub Actions) :
xcodebuild -project Dictee.xcodeproj -scheme DicteeMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
# Tests unitaires Mac :
xcodebuild -project Dictee.xcodeproj -scheme DicteeMac -destination 'platform=macOS' test
# Sans équipe renseignée, ou si le paquet de tests ne se charge pas (point à risque n° 9) :
xcodebuild -project Dictee.xcodeproj -scheme DicteeMac -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO test
```

L'app produite s'appelle `DicteeMac.app` (nom de cible ; le nom affiché est « Dictée »).
Elle est dans `~/Library/Developer/Xcode/DerivedData/Dictee-*/Build/Products/Debug/`.
Pour l'essayer durablement, copie-la dans `/Applications` (plus stable pour les autorisations et `SMAppService`).

### Signature et notarisation

- **Pour tester sur le Mac de développement** : renseigne `DEVELOPMENT_TEAM` dans `Config/Signing.xcconfig`
  (certificat « Apple Development »). Une signature stable compte : macOS rattache les autorisations Micro et
  Accessibilité, ainsi que l'accès au Trousseau, à la signature de l'app.
- **Sans compte développeur** : signature ad hoc, par exemple
  `xcodebuild … CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build`.
  Chaque recompilation change alors la signature : il faut retirer puis rajouter Dictée dans
  Réglages Système > Confidentialité et sécurité > Accessibilité, et le Trousseau peut redemander l'accès à la clé.
- **Runtime renforcé** (`ENABLE_HARDENED_RUNTIME`) activé, avec le droit `com.apple.security.device.audio-input`
  (`Mac/DicteeMac.entitlements`). **Pas de sandbox** : elle interdirait l'envoi de ⌘V aux autres apps.
  L'app ne peut donc pas aller sur le Mac App Store ; distribution directe uniquement.
- **Distribution à d'autres Mac** : signer avec « Developer ID Application », puis notariser :
  ```bash
  xcodebuild -project Dictee.xcodeproj -scheme DicteeMac -configuration Release archive -archivePath build/DicteeMac.xcarchive
  # Exporter l'app dans build/ (Xcode > Organizer > Distribute App > Direct Distribution), puis :
  ditto -c -k --keepParent build/DicteeMac.app build/DicteeMac.zip
  xcrun notarytool submit build/DicteeMac.zip --keychain-profile <profil> --wait
  xcrun stapler staple build/DicteeMac.app
  ```
  Tout reste dans `build/`, ignoré par git (`*.app`, `*.zip` et `*.xcarchive` le sont aussi, au cas où).

### Autorisations

| Autorisation | Pourquoi | Comment l'obtenir |
|---|---|---|
| Micro | Enregistrer la voix | Demandée à la première dictée ou par « Autoriser… » dans les réglages (`AVCaptureDevice.requestAccess`) |
| Accessibilité | Écouter Fn (moniteurs NSEvent globaux) et simuler ⌘V | « Demander… » (`AXIsProcessTrustedWithOptions`) puis cocher Dictée dans Réglages Système > Confidentialité et sécurité > Accessibilité |

- Sans Accessibilité : Fn ne fait rien et le texte est seulement copié. ⌥Espace fonctionne quand même (Carbon).
- L'app relit `AXIsProcessTrusted()` toutes les 2 s et réinstalle les moniteurs dès que l'autorisation arrive.
- **Touche 🌐** : l'utilisateur doit régler Réglages Système > Clavier > « Appuyer sur la touche 🌐 pour » sur
  **« Ne rien faire »**. Sinon, Fn ouvre aussi le sélecteur d'emojis, change de source de saisie ou lance la dictée d'Apple.
  Le bouton « Réglages Clavier… » de la fenêtre de réglages ouvre ce panneau.

### Check-list de recette Mac

Note chaque point comme OK, KO ou partiel, dans `RECETTE.md` (section macOS).

**Installation et premier lancement**
- [ ] `xcodebuild … -scheme DicteeMac build` et `test` réussissent ; tous les tests `DicteeMacTests` passent.
- [ ] Au lancement : icône micro dans la barre des menus, aucune icône dans le Dock.
- [ ] Sans clé du fournisseur choisi (ou sans Accessibilité avec Fn) : la fenêtre de réglages s'ouvre seule, au premier plan.
- [ ] Menu : l'état (« Prêt : maintenez Fn pour dicter »), « Dernière transcription », « Réglages… » (⌘,), « Quitter » (⌘Q).

**Réglages**
- [ ] Clé API : enregistrement, aperçu `sk-…abcd`, « Supprimer ». La clé est visible dans Trousseaux d'accès (service `com.dictee.openai`, compte `apiKey`, `apiKey.mistral` ou `apiKey.microsoft`).
- [ ] Fournisseur, modèle (liste et saisie libre), région Azure, langue, vocabulaire, nettoyage : conservés après relance de l'app.
- [ ] Fournisseur : la section modèle s'adapte (Microsoft : champs « Modèle » et « Région Azure ») ; la phrase d'aide s'affiche ;
  la clé du fournisseur choisi est proposée, plus la clé OpenAI quand le nettoyage est activé.
- [ ] Modèle saisi librement dans « Autre modèle » (ex. `gpt-4o-mini-transcribe`) : il apparaît dans la liste et sert à la dictée suivante.
- [ ] Changer le Mode (« maintenir » ↔ « basculer ») met aussitôt à jour la consigne du menu (« maintenez Fn… » / « appuyez sur Fn… »).
- [ ] Autorisations : l'état Micro et Accessibilité se met à jour en moins de 2 s après un changement dans Réglages Système.
- [ ] Les boutons « Ouvrir les Réglages Système » ouvrent le bon panneau (Micro, Accessibilité, Clavier).
- [ ] « Lancer Dictée à l'ouverture de session » : Dictée apparaît dans Réglages Système > Général > Ouverture ; elle démarre après fermeture puis réouverture de session.

**Dictée avec Fn (mode maintenir)**
- [ ] Touche 🌐 réglée sur « Ne rien faire ». Maintenir Fn : son, pastille « Écoute… » avec niveau qui bouge, icône `mic.fill`.
- [ ] Relâcher : « Transcription… », puis le texte français s'insère au curseur dans TextEdit, Notes, Mail, Safari (champ de recherche et zone de texte), Slack ou une app Electron, Terminal, Word si disponible.
- [ ] La pastille ne prend jamais le focus : le curseur reste dans l'app d'origine, même en plein écran et sur un autre Bureau (Space).
- [ ] Appui bref sur Fn (< 0,3 s) : rien ne se passe, aucun appel réseau, aucune erreur.
- [ ] Fn + F1 (luminosité) ou Fn + flèche : la dictée est annulée sans message.
- [ ] Échap pendant l'écoute : « Dictée annulée. », rien n'est inséré, et l'app au premier plan ne reçoit pas Échap.
- [ ] Fn + flèche ou Fn + Suppr, sans parler : ni son, ni pastille (au plus un bref voyant orange du micro).
- [ ] Une nouvelle pression de Fn pendant « Transcription… » est ignorée.

**Autres modes**
- [ ] Mode « basculer » avec Fn : un appui démarre, un appui arrête (au relâchement de Fn). Fn + flèche pendant
  l'écoute déplace le curseur sans arrêter la dictée.
- [ ] ⌥Espace en mode maintenir puis en mode basculer ; ⌥Espace ne tape pas d'espace insécable dans l'app au premier plan.
- [ ] ⌥Espace maintenu + Échap, **sans** Accessibilité : « Dictée annulée. ».
- [ ] ⌥Espace en mode maintenir, ⌥ relâchée un peu après Espace : le texte est collé normalement (pas de ⌥⌘V).
- [ ] Changer de raccourci dans les réglages prend effet immédiatement, sans relancer l'app.
- [ ] Changer de raccourci ou de Mode pendant une écoute (mode « basculer ») annule la dictée sans message, avec le son de fin.

**Fournisseurs** (voir l'avertissement de la section « Fournisseurs de transcription »)
- [ ] **OpenAI** (`gpt-transcribe`) : dictée transcrite et insérée. Si « model not found », essayer `gpt-4o-transcribe` et le noter.
- [ ] **Mistral** (`voxtral-small-transcribe-3`, puis `voxtral-mini-transcribe-3`) : dictée transcrite ; sigles du vocabulaire bien orthographiés.
- [ ] **Microsoft** (`mai-transcribe-2`, région de la ressource) : dictée transcrite ; noter l'URL, l'`api-version` et la réponse si ça échoue.
- [ ] Clé invalide : « Erreur Mistral (401) : … » ou « Erreur Microsoft (401) : … », sans la clé dans le message.
- [ ] Clé du fournisseur absente : « Clé API Mistral manquante. Ajoutez-la dans les réglages de Dictée. » (idem Microsoft).
- [ ] Mistral ou Microsoft + nettoyage activé sans clé OpenAI : texte brut inséré, aucune erreur ; avec clé OpenAI : texte nettoyé.

**Transcription et nettoyage**
- [ ] « Nettoyer le texte » activé : dicter « euh bonjour euh je voulais dire merci » → texte ponctué, sans les « euh ».
- [ ] Modèle de nettoyage sans `temperature` (ex. `o4-mini`) : le nettoyage fonctionne, aucune erreur.
- [ ] Modèle de nettoyage invalide (ex. `modele-inexistant`) : le texte brut est inséré, sans message d'erreur (SPEC §2.3).
- [ ] Langue vide : une dictée en anglais est transcrite en anglais (détection automatique).
- [ ] Menu « Dernière transcription » > « Copier » : le texte de la dernière dictée est dans le presse-papiers (⌘V ailleurs).
- [ ] Arrêt automatique : abaisser temporairement `DictationController.maxRecordingDuration` (à 10 s, par exemple),
  recompiler, maintenir Fn plus de 10 s → l'écoute s'arrête seule et le texte est transcrit puis inséré.
  **Remettre ensuite la valeur d'origine** (`TranscriptionRules.maxRecordingDuration`, 12 min).

**Presse-papiers**
- [ ] Copier une image (ou du texte riche) puis dicter : après ~1 s, l'image (ou le texte riche) est de nouveau dans le presse-papiers.
- [ ] Copier autre chose dans la seconde qui suit le collage : cette nouvelle copie n'est pas écrasée.
- [ ] Deux dictées courtes à moins d'1 s d'écart : c'est bien la copie d'origine qui revient ensuite.
- [ ] Ouvrir puis fermer les réglages, puis dicter aussitôt : le texte est collé dans l'app d'avant.
- [ ] « Restaurer le presse-papiers » désactivé : le texte dicté reste dans le presse-papiers.
- [ ] Accessibilité retirée : « Texte copié : collez-le avec ⌘V » et le texte est bien dans le presse-papiers.

**Erreurs et robustesse**
- [ ] Sans clé : « Clé API OpenAI manquante. Ajoutez-la dans les réglages de Dictée. » (pastille 4 s, icône d'erreur, état dans le menu).
- [ ] Clé invalide : « Erreur OpenAI (401) : Incorrect API key… ».
- [ ] Wi-Fi coupé : message d'erreur réseau, pas de plantage ; la dictée suivante fonctionne.
- [ ] Micro refusé : message clair renvoyant à Réglages Système > Micro.
- [ ] Dictée de 2 à 3 min : transcription complète. Après la dictée, le voyant orange du micro s'éteint.
- [ ] Dicter avec des AirPods comme micro : l'écoute ne s'arrête pas toute seule après le démarrage.
- [ ] Débrancher un micro USB ou des AirPods pendant l'écoute : pas de plantage, l'écoute continue sur l'autre micro
  et tout est transcrit au relâchement.
- [ ] Sons désactivés : plus de « Tink » ni de « Pop ». Sons activés : chaque « Tink » est suivi d'un « Pop », même pour un appui court,
  après Échap ou après Fn + autre touche.
- [ ] Aucun fichier `dictee-*.wav` ne reste dans le dossier temporaire (`echo $TMPDIR`) après succès, erreur, annulation, ou « Quitter » pendant l'écoute ou la transcription.
- [ ] Mode sombre et clair : réglages lisibles ; pastille lisible sur fond clair et sombre.

### Points à risque (Mac)

1. **Isolation des acteurs Swift** : le bloc du tap (`AudioCapture.makeTapBlock`) et `Permissions.requestMicrophone`
   sont volontairement hors `@MainActor`. Un plantage `dispatch_assert_queue` / `_swift_task_checkIsolated` signale
   une closure créée sur le MainActor et rappelée par le système sur un autre thread. Les moniteurs NSEvent,
   le gestionnaire Carbon et les minuteries sont rappelés sur le thread principal.
2. **Interop Carbon** (`CarbonHotKey.swift`) : conversions `ItemCount`, `ByteCount`, `OSType`, `OSStatus(noErr)`.
   Si la compilation bloque sur un type C, ajuster la conversion sans changer la logique.
   Si ⌥Espace est déjà pris (Spotlight, Raycast, Alfred…), `RegisterEventHotKey` échoue et les réglages le signalent.
3. **Fn** : les moniteurs globaux ne reçoivent rien sans Accessibilité, ni pendant la saisie d'un mot de passe
   (saisie sécurisée). Certains claviers externes n'ont pas de touche Fn visible par macOS : utiliser ⌥Espace.
   Le moniteur `keyDown` global sert uniquement à détecter Fn + autre touche ; il ne lit ni ne stocke les frappes.
4. **⌘V simulé** : keyCode 9 (`kVK_ANSI_V`) correspond à V en QWERTY et AZERTY, mais pas en Dvorak.
   Certaines apps (terminaux distants, jeux, VM) ignorent les événements synthétiques ; le texte reste alors
   au presse-papiers pendant 1 s seulement si la restauration est active.
5. **Restauration du presse-papiers** : une app lente peut lire le presse-papiers plus d'1 s après ⌘V et coller
   l'ancien contenu. Si ça arrive, augmenter `TextInserter.restoreDelay` (1,5 à 2 s).
6. **Pastille** : la hauteur est calculée par `NSHostingView.fittingSize`. Si un long message d'erreur est tronqué
   ou mal centré, revoir `OverlayView.messageText` (largeur fixe de 320 pt).
7. **`MenuBarExtra`** : l'icône suit `controller.state`. Si elle ne se met pas à jour, vérifier que
   `DictationController` est bien observé par `@StateObject` dans `DicteeMacApp`.
8. **Trousseau** : sur Mac, l'élément est créé dans le trousseau de session classique (`kSecAttrAccessible`
   n'est appliqué que sur iOS). Avec une signature ad hoc, macOS peut demander « Dictée veut utiliser… » : cliquer
   « Toujours autoriser ».
9. **Tests et runtime renforcé** : en signature ad hoc, la validation des bibliothèques peut empêcher le chargement
   du paquet de tests dans l'app hôte. Dans ce cas, lancer les tests avec `ENABLE_HARDENED_RUNTIME=NO`
   ou avec une équipe de développement renseignée.
10. **Démarrage du micro** : `AVAudioEngine` met 100 à 300 ms à démarrer ; le tout début de la phrase peut être coupé
    si l'on parle dès l'appui. Si c'est gênant, garder le moteur démarré pendant quelques secondes après chaque dictée
    (sans enregistrer), en acceptant le voyant orange.

## Choix à préserver

- **Le clavier n'a jamais le micro ni la clé API** : iOS l'interdit pour le micro, et c'est un choix de sécurité pour la clé. Tout passe par l'app.
- **Clé API uniquement dans le Trousseau de l'app**, jamais dans l'App Group ni dans le code.
- **Mac : pas de sandbox, presse-papiers + ⌘V** : c'est le seul moyen fiable d'insérer du texte dans n'importe quelle app (même choix que Wispr Flow).
- **Mac : `Core/` et `Shared/` sont partagés avec iOS.** Toute modification doit continuer à compiler pour les deux plateformes (utiliser `#if os(iOS)` si besoin).
- **Audio en WAV 16 kHz mono** : environ 13 min maximum sous la limite de 25 Mo d'OpenAI. Plafond fixé à 12 min dans `DictationEngine.maxRecordingDuration` (iOS) et `DictationController.maxRecordingDuration` (macOS).
- **`project.yml` est la source de vérité** : ne committe pas `Dictee.xcodeproj`.

## Ce qu'il faut rendre

1. Les corrections de compilation, en commits courts et explicites, sur la branche `claude/clavier-dictee-ios`.
2. La check-list ci-dessus remplie, dans un fichier `dictee/apple/RECETTE.md` daté.
3. Pour chaque point KO : symptôme, cause probable, correctif appliqué ou proposé.
4. Des captures d’écran du clavier en mode clair et en mode sombre si possible.
5. Pour le Mac : la check-list « Check-list de recette Mac » remplie dans `RECETTE.md`, et des captures de la pastille, du menu et des réglages.
