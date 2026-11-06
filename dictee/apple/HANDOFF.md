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
| `DicteeKeyboard` (extension) | iOS | Clavier AZERTY complet (lettres, 123, #+=, accents) avec barre de dictée : ☰ (panneau rapide), pastille de style, micro ; insertion du texte |
| `DicteeTests` | iOS | Tests unitaires de la logique sans matériel (multipart, requêtes OpenAI, Mistral et Azure, parseurs, état partagé, insertion, logique du clavier AZERTY, style d'écriture, historique) |
| `DicteeMac` (app) | macOS 13+ | App de barre des menus : raccourci global, enregistrement, transcription, collage au curseur (voir section « macOS ») |
| `DicteeMacTests` | macOS | Tests unitaires Mac sans matériel (raccourcis, presse-papiers, réglages, règles du pipeline, requêtes des trois fournisseurs) |

Flux d'une dictée sur iOS :

1. Clavier, micro touché sans session → ouvre `dictee://start` → l'app démarre `AVAudioEngine` (mode audio en arrière-plan).
2. L'utilisateur revient à son app (« ‹ » en haut à gauche).
3. Micro touché → notification Darwin `startRecording` → l'app écrit les tampons dans un WAV 16 kHz mono.
4. Micro retouché → `stopRecording` → l'app envoie le fichier au fournisseur choisi (`TranscriptionService.transcribe`), puis, si « Nettoyer le texte » est actif **ou** si le style d'écriture n'est pas « Brut », nettoie le texte via `chat/completions` chez OpenAI (consignes + ligne du style, SPEC §2).
5. L'app écrit la `Transcript` dans les UserDefaults de l'App Group (et l'ajoute à l'historique des 10 dernières) et poste `transcriptReady` → le clavier insère le texte via `textDocumentProxy`.

L'app rafraîchit `sessionExpiresAt` toutes les 2 s. Le clavier considère la session morte si cette date est dépassée.

## Arborescence

```
dictee/apple/
├── project.yml              # définition XcodeGen (source de vérité du projet)
├── Config/Signing.xcconfig  # équipe Apple, préfixe de bundle, App Group  ← à remplir
├── App/                     # cible Dictee (iOS)
├── Core/                    # code portable iOS + macOS (transcription, OpenAI et consignes de style, Trousseau, enregistreur WAV, règles du pipeline)
├── Keyboard/                # cible DicteeKeyboard (interface SwiftUI du clavier AZERTY, session, panneau rapide)
├── Mac/                     # cible DicteeMac (app de barre des menus macOS) ; Mac/Tests = DicteeMacTests
├── Shared/                  # état partagé (SharedStore, historique, WritingStyle, TranscriptionProvider), compilé dans toutes les cibles
│   └── KeyboardLogic/       # logique pure du clavier (couches, accents, majuscule, double espace, ⏎, géométrie) ; exclue du Mac
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
| `TranscriptionProvider` | `Shared/TranscriptionProvider.swift` | `openai` / `mistral` / `microsoft`, nom affiché, compte du Trousseau, modèles proposés, phrase d'aide. Dans `Shared/` car le panneau rapide du clavier choisit aussi le fournisseur |
| `TranscriptionService.transcribe(provider:audioURL:settings:keys:)` | `Core/TranscriptionService.swift` | Point d'entrée unique, appelé par `DictationEngine` (iOS) et `DictationController` (Mac) |
| `makeMistralRequest`, `makeAzureRequest`, `azureDefinition` | idem | Constructeurs de requêtes purs, testés sans réseau (`OpenAIClient.makeTranscriptionRequest` reste celui d'OpenAI) |
| `vocabularyTerms`, `azureLocale(for:)`, `mistralLanguage(for:)` | idem | Découpage du vocabulaire (100 termes, sans doublons), locale Azure, langue à 2 lettres pour Mistral |
| `parseTextResponse`, `parseAzureTranscription`, `errorMessage(from:)` | idem | Réponses (`text` ; `combinedPhrases[0].text`, sinon `phrases[].text`) et erreurs (`error.message`, `message`, `detail`) |
| `TranscriptionService.cleanUp` | idem | Nettoyage toujours chez OpenAI, si `cleanupEnabled` **ou** style ≠ `brut` (`TranscriptionRules.isCleanupRequested`) ; sauté sans erreur s'il n'y a pas de clé OpenAI |
| `OpenAIClient.cleanupInstructions(vocabulary:style:)` | `Core/OpenAIClient.swift` | Consignes exactes de SPEC §2, ligne de vocabulaire, puis ligne du style (`WritingStyle.cleanupInstruction`) |
| `KeychainStore` | `Core/KeychainStore.swift` | Une clé par fournisseur : service `com.dictee.openai`, comptes `apiKey` (OpenAI, inchangé), `apiKey.mistral`, `apiKey.microsoft` |
| `SharedStore` | `Shared/SharedStore.swift` | `dictee.settings.provider`, `mistralModel`, `microsoftModel`, `azureRegion` (repli sur le défaut si vide), `writingStyle` (valeur inconnue → `brut`), historique `dictee.history` (JSON, 10 au maximum, le plus récent en premier). `provider`, `language` et `writingStyle` sont aussi écrits par le clavier |
| `WritingStyle` | `Shared/WritingStyle.swift` | `brut` (défaut), `formel`, `courriel`, `decontracte` ; libellé (« Formel ») et libellé de pastille (« Formel. ») |

Défauts : fournisseur `openai`, modèle OpenAI `gpt-transcribe`, Mistral `voxtral-small-transcribe-3`,
Microsoft `mai-transcribe-2`, région Azure `eastus`. Messages : « Clé API Mistral manquante. Ajoutez-la dans les
réglages de Dictée. », « Erreur Microsoft (401) : … ». Les clés n'apparaissent jamais dans un message d'erreur
(remplacées par leur aperçu `sk-…abcd`).

## Clavier AZERTY (SPEC §9)

| Fichier | Rôle |
|---|---|
| `Keyboard/KeyboardViewController.swift` | Point d'entrée ; `KeyboardInputView` (clic système), hauteur 290 pt (220 pt en paysage), mode sombre selon `keyboardAppearance`, traits du champ (`returnKeyType`, `autocapitalizationType`), ouverture de l'app |
| `Keyboard/KeyboardModel.swift` | Session et micro (logique inchangée : signaux Darwin, délai de démarrage de 2 s, accès complet), pastille, menu des styles, panneau rapide, réglages écrits dans l'App Group |
| `Keyboard/TypingModel.swift` | Frappe : couches, ⇧, double espace, ⌫ répété, accents par appui long, aperçu, frappe à deux doigts |
| `Keyboard/KeyboardView.swift` | Racine SwiftUI, barre supérieure (☰, pastille, micro), menu des styles, panneau rapide |
| `Keyboard/KeysView.swift` | Dessin des touches, aperçu, bulle d'accents, `KeyTouchView` (UIKit multi-touch, bouton 🌐, éléments VoiceOver) |
| `Keyboard/KeyboardTheme.swift` | Couleurs claires et sombres |
| `Shared/KeyboardLogic/` | Logique pure testée dans `DicteeTests` : `KeyboardLayout`, `AccentTable`, `ShiftLogic`, `AutoCapitalization`, `DoubleSpaceRule`, `ReturnKeyKind`, `KeyboardGeometry` |

Le clavier n'a toujours ni micro ni clé API. Il écrit seulement `writingStyle`, `provider`, `language` et efface
l'historique dans l'App Group (avec l'accès complet) ; l'app les relit à la dictée suivante. L'historique contient le
texte des 10 dernières dictées, en clair dans l'App Group (comme `latestTranscript`).

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

**Clavier AZERTY** (SPEC §9 ; captures en mode clair et sombre à joindre)
- [ ] Le clavier apparaît dans Réglages > Général > Clavier > Claviers > Ajouter.
- [ ] Sans accès complet : cadenas sur le micro ; toucher le micro ou changer un réglage du panneau affiche l'explication.
- [ ] Avec accès complet, sans session : le micro ouvre l'app Dictée (**point à risque n° 1**). Retour par « ‹ » : micro noir, pastille « Brut. ».
- [ ] Barre supérieure : ☰ à gauche, pastille blanche arrondie et micro dans un cercle noir à droite, comme sur la maquette ; aucune marque tierce, la barre d'espace affiche « Dictée ».

*Frappe*
- [ ] Lettres `A Z E R T Y U I O P` / `Q S D F G H J K L M` / `⇧ W X C V B N ' ⌫` / `123 espace ⏎` : chaque touche tape le bon caractère, y compris en touchant le bord d'une touche ou l'espace entre deux touches.
- [ ] Aperçu agrandi de la lettre au toucher (y compris sur la rangée du haut, A et P aux bords) ; clic clavier si « Clics du clavier » est activé dans Réglages > Sons et vibrations.
- [ ] Frappe rapide à deux pouces : aucune lettre perdue ni doublée (ex. « bonjour » tapé vite, dix fois).
- [ ] Glisser d'une lettre à une autre avant de relâcher tape la seconde.
- [ ] ⌫ efface un caractère ; maintenu, il répète (après ~0,5 s) et s'arrête dès qu'on relâche.
- [ ] Double espace après un mot → « . » suivi d'une majuscule ; pas de point après une ponctuation ou une espace déjà présente.
- [ ] ⏎ : libellé selon le champ (« retour » dans Notes, « envoyer » dans Messages, « rechercher » dans Safari, « OK »…), bleu pour les actions ; il insère un retour à la ligne ou déclenche l'action de l'app.
- [ ] 🌐 présent seulement s'il n'y a pas de globe système (iPhone avec bouton d'accueil) ; toucher = clavier suivant, appui long = liste des claviers.

*Barre de suggestions*
- [ ] Après 2 lettres (« tri ») : jusqu'à trois propositions ; toucher l'une d'elles remplace le mot en cours, casse conservée (« Tri » → « Tribunal »), suivie d'une espace.
- [ ] Un terme du vocabulaire (« ohad » → « OHADA ») passe devant le dictionnaire.
- [ ] Barre vide : clavier `123` / `#+=`, panneau ☰ ouvert, champ mot de passe, e-mail, URL ou recherche ; mode sombre lisible ; paysage : tout tient.
- [ ] Aucune lenteur sensible à la frappe (le calcul est coalescé à 50 ms).

*Correction automatique*
- [ ] « tribunla » puis espace → « tribunal » ; la barre montre « tribunla » entre guillemets ; un toucher ou ⌫ immédiat rétablit « tribunla ».
- [ ] Un sigle (« AUSCGIE »), un mot du vocabulaire ou un mot de 2 lettres n'est jamais corrigé ; une ponctuation (« , ») déclenche aussi la correction.
- [ ] Réglage « Correction automatique » désactivé dans l'app : plus aucune correction.

*Accents*
- [ ] Appui long sur e, a, c, u, i, o, y : bulle avec é è ê ë · à â æ · ç · ù û ü · î ï · ô œ · ÿ ; glisser puis relâcher insère l'accent choisi.
- [ ] Relâcher sans glisser insère le premier accent ; glisser nettement vers le bas annule.
- [ ] Sur O et P (bord droit), la bulle s'ouvre vers la gauche sans sortir de l'écran.
- [ ] Avec ⇧ : accents en majuscules (É, À, Ç, Œ, Ÿ…).

*Majuscules*
- [ ] Un toucher sur ⇧ = une majuscule ; double toucher = verrouillage (symbole cadenas) ; toucher suivant = arrêt.
- [ ] Majuscule automatique en début de champ, après « . », « ? », « ! » suivis d'une espace, et après un retour à la ligne (Notes, Messages).
- [ ] Pas de majuscule automatique dans un champ e-mail ou URL (Safari), ni dans un champ qui la désactive.

*123 et #+=*
- [ ] `123` : `1 2 3 4 5 6 7 8 9 0` / `- / : ; ( ) € & @ "` / `#+= . , ? ! ' ⌫` / `ABC espace ⏎`.
- [ ] `#+=` : `[ ] { } # % ^ * + =` / `_ \ | ~ < > $ £ ¥ •` / `123 . , ? ! ' ⌫` / `ABC espace ⏎`.
- [ ] `ABC` revient aux lettres (avec la majuscule automatique réévaluée).

*Dictée et pastille*
- [ ] Micro → cercle rouge avec un carré, pastille « Écoute… » ; retoucher → « Transcription… » puis le texte s'insère au curseur, avec une espace devant si besoin.
- [ ] Appui long sur le micro pendant l'écoute : annulation, rien n'est inséré.
- [ ] Erreur (ex. clé absente) : message rouge dans la barre ; un toucher le masque.
- [ ] Pastille : un toucher ouvre le menu des 4 styles (coche sur le style courant) ; toucher à côté le ferme sans taper de lettre.

*Styles d'écriture*
- [ ] « Formel » choisi au clavier, « Nettoyer le texte » désactivé dans l'app, avec clé OpenAI : une dictée familière ressort au registre soutenu, sans ajout ni résumé.
- [ ] « Courriel » : paragraphes courts, pas de formule de politesse ajoutée si elle n'est pas dictée. « Décontracté » : ton direct.
- [ ] Style ≠ « Brut » sans clé OpenAI (fournisseur Mistral) : texte brut inséré, sans erreur ; l'app propose la clé OpenAI.
- [ ] Le style choisi au clavier apparaît dans l'app (« Style d'écriture ») et inversement.

*Panneau rapide (☰)*
- [ ] Les dernières transcriptions (10 au maximum, la plus récente en haut) ; un toucher insère le texte et referme le panneau.
- [ ] « Effacer l'historique » vide la liste (et l'app indique « Historique vide ») ; le bouton de l'app fait de même.
- [ ] Style, fournisseur (OpenAI / Mistral / Microsoft) et langue (Français, Anglais, Détection auto) : le choix est pris en compte à la dictée suivante et visible dans l'app.
- [ ] « Ouvrir Dictée » ouvre l'app (`dictee://settings`) sans démarrer de session ; « Fermer » revient aux touches.

*Affichage et mémoire*
- [ ] Mode sombre (système) et champ à clavier sombre : touches, pastille, micro, bulles et panneau lisibles.
- [ ] iPhone SE (375 pt) : aucune touche tronquée, « rechercher » lisible sur ⏎, panneau défilable. iPhone Pro Max : touches proportionnées.
- [ ] Paysage : clavier moins haut, tout reste utilisable.
- [ ] Mémoire : Xcode > Debug Navigator sur le processus du clavier, moins de ~40 Mo après 2 min de frappe, ouverture du panneau et des bulles ; aucun arrêt `EXC_RESOURCE` ni disparition du clavier.
- [ ] VoiceOver : chaque touche est annoncée (« a », « Majuscule », « Effacer », « retour »…) et activable.

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
4. **UserDefaults partagés entre processus** : ils peuvent avoir un léger retard. **Constaté en recette (2026-11-06)** : la transcription réussissait mais n'était jamais insérée. `KeyboardModel` relit désormais à 0,15 s, 0,5 s et 1,5 s après `transcriptReady`, vérifie aussi à chaque retour de l'app à `idle`, et ne marque la transcription consommée qu'après insertion réelle.
5. **Mémoire du clavier** : iOS limite fortement les extensions clavier (environ 48 à 70 Mo). Le clavier ne fait que de l'interface : aucune image, couleurs et symboles SF uniquement, liseré des touches dessiné par une forme (pas d'ombre), une seule minuterie (1 s, rafraîchissement de la session, arrêtée à la disparition), appui long et répétition par des `Task` annulées. Surveille quand même les éventuels arrêts `EXC_RESOURCE`.
6. **Noms de modèles** : par défaut `gpt-transcribe` (OpenAI), `voxtral-small-transcribe-3` (Mistral), `mai-transcribe-2` (Microsoft) et `gpt-4o-mini` (nettoyage), **non vérifiés en direct**. Ils sont modifiables dans l'app (saisie libre). Si un fournisseur renvoie « model not found », vérifie les modèles disponibles sur le compte de l'utilisateur, puis corrige `SharedStore.Default` et `TranscriptionProvider.suggestedModels`.
7. **Formats Mistral et Azure** : décrits d'après la documentation, non vérifiés. Mistral : champ `context_bias` répété, ni `prompt` ni `response_format`. Azure : `transcriptions:transcribe?api-version=2025-10-15`, parties `audio` et `definition` (JSON), réponse lue dans `combinedPhrases[0].text`. En cas d'écart, corriger `Core/TranscriptionService.swift` et les tests correspondants.
8 ter. **Correction automatique** (`AutoCorrection`, `PredictionModel.autocorrectBeforeBoundary`) : `UITextChecker`
   juge « inconnu » tout mot absent de son dictionnaire, noms propres compris ; la protection repose sur le vocabulaire,
   l'historique, la casse et la distance d'édition. Si des corrections intempestives remontent, ajouter les termes au
   vocabulaire ou durcir `AutoCorrection.maximumDistance`.
8 bis. **Barre de suggestions** (`PredictionModel`, `WordPrediction`) : `UITextChecker.completions` renvoie des
   complétions de dictionnaire, à peu près alphabétiques, pas classées par fréquence ; le vocabulaire et l'historique
   passent devant. `UITextChecker.availableLanguages` varie selon les dictionnaires installés : sans `fr_*`/`en_*`
   disponible, seuls le vocabulaire et l'historique sont proposés. Calcul coalescé (50 ms) sur le thread principal ;
   surveiller la latence et la mémoire si l'historique grossit.
8. **Clavier AZERTY : points à vérifier en premier**
   - **Clic clavier** : `KeyboardViewController.loadView` remplace la vue par `KeyboardInputView` (`UIInputView` + `UIInputViewAudioFeedback`). Si le clavier s'affiche mal (fond, hauteur), retirer `loadView` : seul le clic disparaît.
   - **Touchers** : `KeyTouchView` (UIKit, multi-touch) est posée sur les touches SwiftUI et retrouve la touche par `KeyboardGeometry` (même calcul que l'affichage). Si une touche ne répond pas, vérifier que la vue reçoit bien `touchesBegan` et que sa taille est celle de la zone.
   - **🌐** : un `UIButton` transparent posé sur la touche, branché sur `handleInputModeList(from:with:)` (`.allTouchEvents`). Si l'appui long n'affiche pas la liste, garder au moins le toucher (repli : `advanceToNextInputMode`).
   - **Menu des styles** : pendant qu'il est ouvert, `KeyTouchView.isUserInteractionEnabled` est faux pour que le toucher « à côté » arrive à SwiftUI. Si un toucher à côté tape quand même une lettre, c'est ce point.
   - **Majuscule automatique** : lit `documentContextBeforeInput` après chaque frappe et dans `textDidChange`. Certaines apps renvoient un contexte vide ou en retard : la majuscule peut alors apparaître à tort en milieu de phrase.
   - **Double espace** : délai de 0,8 s (`DoubleSpaceRule.interval`), à ajuster si besoin.

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

Code partagé avec iOS : `Core/` (TranscriptionService, OpenAIClient, KeychainStore, BufferRecorder, TranscriptionRules) et `Shared/`
(SharedStore, TranscriptionProvider, WritingStyle, TextJoiner…). `Shared/DarwinNotifier.swift` (signaux app ↔ clavier iOS) et
`Shared/KeyboardLogic/` (logique du clavier AZERTY) sont exclus de `DicteeMac` dans `project.yml`. Le Mac lit le réglage
`writingStyle` (Picker « Style d'écriture » dans les réglages ; défaut `brut`, donc sans effet tant qu'il n'est pas changé).
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
- [ ] « Style d'écriture » réglé sur « Formel » avec « Nettoyer le texte » désactivé : la dictée est nettoyée au registre soutenu (clé OpenAI requise ; sans elle, texte brut).
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
   **Constaté le 2026-11-06 sur MacBook Air (Mac16,13, macOS 27.3)** : `flagsChanged` (keyCode 63) arrive bien, mais sans le
   drapeau `.function` et en un seul événement par geste (appui bref ou long) : « maintenir » est impossible avec les
   moniteurs NSEvent. Réglage « Appuyer sur 🌐 » sur « Ne rien faire » et aucun remappage de touche. Contournement :
   ⌥Espace. Pistes non explorées : `CGEventTap` ou IOHID.
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
