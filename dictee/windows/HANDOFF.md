# Passation : compiler, publier et recetter Dictée sur Windows

Document destiné à l'agent (ou à la personne) qui reprend ce projet **sur une machine Windows**.
Communique avec l'utilisateur **en français**.

Le code a été écrit et compilé sous Linux (SDK .NET 8 avec `EnableWindowsTargeting`) : la compilation, la publication
`win-x64` et les tests du cœur passent, mais **rien n'a encore été exécuté sous Windows**. Les parties Win32
(crochet clavier, SendInput, presse-papiers, micro, pastille) sont donc à valider en priorité avec la check-list ci-dessous.

## Ce que fait le projet

Équivalent Windows de Wispr Flow, conforme à `../SPEC.md` : app de zone de notification ; on maintient **Ctrl droit**,
on parle, on relâche ; l'audio part à OpenAI avec la clé de l'utilisateur, et le texte est collé au curseur
(presse-papiers + Ctrl+V simulé, puis restauration du presse-papiers).

## Arborescence

```
dictee/windows/
├── Dictee.sln
├── Directory.Build.props        # réglages communs (nullable, version, symboles intégrés)
├── src/
│   ├── Dictee.Core/             # net8.0 pur, sans dépendance Windows, testé
│   │   ├── OpenAiClient.cs        # transcription + nettoyage, multipart, délais, extraction de error.message
│   │   ├── MultipartFormData.cs   # corps multipart écrit à la main (comme sur iOS)
│   │   ├── TranscriptionPipeline.cs # transcription → nettoyage (repli sur le brut) → « Aucune parole détectée. » → suppression du WAV
│   │   ├── DicteeSettings.cs      # réglages SPEC §3 (JSON camelCase), HotkeyIds, HotkeyModes
│   │   ├── HotkeyStateMachine.cs  # décisions des raccourcis (maintenir/basculer, annulation, AltGr, Échap), sans Win32
│   │   ├── DicteeConstants.cs     # 16 kHz, 12 min, 0,3 s, 120 s / 60 s, 1 s, 4 s
│   │   ├── DicteeMessages.cs      # textes imposés + DicteeException / OpenAiHttpException
│   │   └── ApiKeyHint.cs          # aperçu « sk-…abcd »
│   └── Dictee.Windows/          # net8.0-windows, WinForms, exe « Dictee.exe »
│       ├── Program.cs             # instance unique (Mutex), configuration WinForms
│       ├── TrayApplicationContext.cs # icône, menu, cycle de vie
│       ├── TrayIconRenderer.cs    # icônes dessinées à l'exécution (aucune ressource binaire)
│       ├── DictationController.cs # machine à états SPEC §7, orchestre tout
│       ├── HotkeyManager.cs       # WH_KEYBOARD_LL + WH_MOUSE_LL → HotkeyStateMachine ; RegisterHotKey
│       ├── AudioRecorder.cs       # NAudio WaveInEvent → WAV 16 kHz mono dans %TEMP%
│       ├── TextInjector.cs        # presse-papiers + SendInput Ctrl+V + restauration
│       ├── OverlayForm.cs         # pastille flottante sans focus
│       ├── SettingsForm.cs        # réglages (construits en code)
│       ├── SettingsStore.cs / ApiKeyStore.cs / AppPaths.cs / StartupRegistration.cs / SoundEffects.cs
│       ├── Native/NativeMethods.cs # P/Invoke
│       └── app.manifest           # asInvoker, Windows 10/11
└── tests/Dictee.Core.Tests/     # xUnit, aucun appel réseau (faux HttpMessageHandler)
```

## Étapes

### 0. Récupérer le code
```powershell
git clone https://github.com/jfkonan/lynn40.git
cd lynn40
git checkout claude/clavier-dictee-ios
cd dictee\windows
# Ou seulement l'exe produit par la CI (GitHub CLI, depuis le dépôt cloné) :
gh run download --name Dictee-Windows-x64 --dir publish
```

### 1. Prérequis
- Windows 10 ou 11, x64.
- SDK .NET 8 : `winget install Microsoft.DotNet.SDK.8` (vérifier avec `dotnet --info`).
- Un micro, une clé API OpenAI valide (à demander à l'utilisateur ; ne jamais l'écrire dans un fichier du dépôt).

### 2. Compilation et tests (depuis `dictee/windows`)
```powershell
dotnet build Dictee.sln -c Release
dotnet test Dictee.sln -c Release
```
Attendu : 0 erreur, 0 avertissement, 99 tests réussis. Le test `MatchesSpecFileExactly` lit `../SPEC.md` :
il échoue si les consignes de nettoyage divergent du cahier des charges.

### 3. Lancement en développement
```powershell
dotnet run --project src/Dictee.Windows -c Debug
```

### 4. Publication (exe autonome, identique à la CI)
```powershell
dotnet publish src/Dictee.Windows/Dictee.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish
```
Produit `publish\Dictee.exe` (≈ 65 Mo, compressé ; aucun runtime .NET requis sur la machine cible).
La CI (`.github/workflows/dictee.yml`, job `windows`) fait la même chose et publie l'artefact `Dictee-Windows-x64`.

## Check-list de recette Windows

Note chaque point OK, KO ou partiel, et décris les problèmes. Teste avec l'exe **publié**, pas seulement `dotnet run`.

**Premier lancement**
- [ ] SmartScreen : « Informations complémentaires » > « Exécuter quand même » permet de lancer l'exe.
- [ ] L'icône micro grise apparaît dans la zone de notification ; la fenêtre Réglages s'ouvre car aucune clé n'est enregistrée.
- [ ] Relancer l'exe une seconde fois : message « Dictée est déjà lancée… », pas de seconde icône.
- [ ] Écran à 150 % ou 200 % : réglages, pastille et icône nets et bien proportionnés ; idem en déplaçant la fenêtre vers un écran à autre échelle.

**Clé API et réglages**
- [ ] Coller une clé, Enregistrer, rouvrir : « Clé enregistrée : sk-…abcd ». `%APPDATA%\Dictee\apikey.bin` n'est pas lisible en clair :
  `Format-Hex $env:APPDATA\Dictee\apikey.bin | Select-Object -First 3` ne montre aucun « sk- ».
- [ ] « Annuler » et Échap ferment la fenêtre des réglages sans rien enregistrer.
- [ ] « Supprimer la clé » l'efface ; une dictée sans clé affiche « Clé API OpenAI manquante. Ajoutez-la dans les réglages de Dictée. »
- [ ] `%APPDATA%\Dictee\settings.json` contient les clés camelCase de SPEC §3 et jamais la clé API.
- [ ] Modifier `settings.json` en le corrompant : au relancement, réglages par défaut, pas de plantage.
- [ ] « Lancer au démarrage » crée/supprime la valeur `Dictee` sous `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` ; Dictée démarre bien à l'ouverture de session.
  Vérifier avec `Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name Dictee` (erreur si la valeur est absente).
- [ ] Mettre une valeur mal typée dans `settings.json` (ex. `"soundsEnabled": "oui"`) : seul ce réglage revient à son défaut, les autres sont conservés.

**Dictée (mode maintenir, Ctrl droit)**
- [ ] Bloc-notes : maintenir Ctrl droit, parler, relâcher → son de début, pastille « Écoute… » avec niveau qui bouge, son de fin, « Transcription… », texte inséré au curseur.
- [ ] La pastille ne vole jamais le focus : le curseur reste dans le Bloc-notes, on peut continuer à taper ; les clics la traversent.
- [ ] La pastille s'affiche en bas au centre de l'écran de la fenêtre active (tester avec deux écrans).
- [ ] Le presse-papiers d'origine (texte, puis image copiée depuis Paint, puis fichiers copiés depuis l'Explorateur) est restauré environ 1 s après le collage.
- [ ] Copier autre chose dans la seconde qui suit l'insertion : ce nouveau contenu n'est pas écrasé par la restauration.
- [ ] Ctrl droit + C / V / Z / flèches : le raccourci fonctionne normalement, aucune dictée, aucune pastille ni son (ou un éclair < 150 ms).
- [ ] Ctrl droit + clic (sélection multiple dans l'Explorateur, lien dans un nouvel onglet) et Ctrl droit + molette : aucune dictée.
- [ ] Sans clé enregistrée : Ctrl droit + C ne montre aucune erreur ; seule une vraie dictée affiche « Clé API OpenAI manquante… ».
- [ ] Appui bref (< 0,3 s) : rien ne se passe, aucun appel réseau.
- [ ] Échap pendant l'enregistrement : annulation, rien n'est inséré ; Échap n'est pas transmis à l'application et le menu Démarrer ne s'ouvre pas (Ctrl droit maintenu).
- [ ] Silence total (micro coupé) : message d'erreur clair dans la pastille pendant ~4 s ; l'icône passe à l'orange, puis redevient normale à la dictée suivante.
- [ ] Clé invalide : « Erreur OpenAI (401) : Incorrect API key provided… ».
- [ ] Wi-Fi coupé : « Connexion à OpenAI impossible : … ».
- [ ] Une nouvelle pression pendant « Transcription… » est ignorée ; la pastille disparaît dès le collage, sans attendre la restauration du presse-papiers, et l'on peut enchaîner aussitôt une autre dictée.
- [ ] Dictée longue (2-3 min) : transcription complète. Optionnel : vérifier l'arrêt automatique à 12 min.
- [ ] Aucun fichier `dictee-*.wav` ne reste dans `%TEMP%` après succès, erreur, annulation, et après « Quitter » pendant un enregistrement
  ou une transcription : `Get-ChildItem $env:TEMP\dictee-*.wav` ne renvoie rien.

**Autres raccourcis et modes**
- [ ] Mode « appuyer pour démarrer, appuyer pour arrêter » avec Ctrl droit.
- [ ] Ctrl+Maj+Espace : bascule ; si une autre application l'a déjà pris, un message l'indique.
- [ ] F8 (maintenir) : F8 n'atteint plus l'application au premier plan.
- [ ] Alt droit sur clavier QWERTY : relâcher Alt n'active pas la barre de menus du Bloc-notes (touche masque).
- [ ] Alt droit sur clavier AZERTY : AltGr+0 donne bien « @ » et annule la dictée ; maintenir AltGr seul dicte.

**Applications cibles**
- [ ] Word, Outlook (nouveau et classique), Teams, Chrome/Edge (champ de recherche, Gmail, Google Docs), Slack, VS Code.
- [ ] Terminal Windows, PowerShell, invite de commandes (voir point à risque n° 4).
- [ ] Application lancée « en tant qu'administrateur » (ex. Bloc-notes admin) : « Texte copié : collez-le avec Ctrl+V », le texte est dans le presse-papiers.
- [ ] Menu de l'icône : « Dernière transcription (copier) » fonctionne.
- [ ] Historique du presse-papiers (Win+V) : le texte dicté n'y apparaît pas quand la restauration est active, et le contenu restauré n'y crée pas de doublon.

**Compte rendu** : un tableau « point / OK, KO ou partiel / observation », à renvoyer à l'utilisateur en français.
Ne jamais y coller la clé API.

## Points à risque connus

1. **SmartScreen et exe non signé.** L'exe n'est pas signé : SmartScreen avertit au premier lancement, et certains
   navigateurs le signalent au téléchargement. Solution durable : signature Authenticode (certificat OV/EV ou
   Azure Trusted Signing), à ajouter comme étape de la CI. Sans signature, documenter « Exécuter quand même » (fait dans README).
2. **Antivirus et crochet clavier.** Un crochet `WH_KEYBOARD_LL` dans un exe non signé et compressé (single-file) ressemble
   à un enregistreur de frappe pour certains antivirus (heuristique). Si Defender ou un autre produit le bloque ou le met en
   quarantaine : tester sans `EnableCompressionInSingleFile`, signer l'exe, ou soumettre un faux positif à l'éditeur.
   Si `SetWindowsHookEx` échoue, une bulle « Raccourci clavier indisponible » s'affiche.
   Windows retire aussi silencieusement un crochet dont le rappel dépasse `LowLevelHooksTimeout`. Les crochets clavier et
   souris tournent donc sur un fil dédié (`Dictee.KeyboardHook`) qui ne fait que pomper ses messages : un fil d'interface
   occupé (presse-papiers, DPAPI) ne peut pas les faire sauter. En mode maintenir, un chien de garde (`GetAsyncKeyState`
   toutes les 200 ms) arrête l'enregistrement si le relâchement a été manqué (crochet retiré, fenêtre administrateur au
   premier plan) ; il ne s'applique pas à F8, que le crochet avale. Symptôme d'un crochet retiré malgré tout : le raccourci
   ne répond plus jusqu'au redémarrage de Dictée.
3. **Applications élevées (UIPI).** Une application lancée en administrateur ignore les `SendInput` d'une application
   normale, sans erreur visible. `TextInjector.ForegroundIsElevated` détecte ce cas (jeton du processus au premier plan)
   et laisse le texte dans le presse-papiers. À vérifier : pas de faux positif sur les applications ordinaires
   (UWP, Office, navigateurs). Ne **pas** lancer Dictée en administrateur pour contourner : le crochet verrait alors
   les frappes des applications élevées, et le lancement au démarrage via `Run` ne s'élève pas.
4. **Terminaux où Ctrl+V diffère.** Invite de commandes et PowerShell récents collent avec Ctrl+V, mais d'anciens
   consoles, WSL dans certains terminaux, PuTTY (clic droit / Maj+Inser) ou Vim n'interprètent pas Ctrl+V comme un collage.
   Piste si besoin : liste de processus (`putty.exe`, `mintty.exe`…) pour lesquels envoyer Maj+Inser à la place.
5. **Presse-papiers.** La sauvegarde copie chaque format via WinForms (`GetData` par format, try/catch) : les formats à
   rendu différé, les métafichiers ou des formats privés peuvent ne pas être restaurés à l'identique. Les gestionnaires de
   presse-papiers (Ditto…) voient passer le texte dicté.
6. **Micro.** `WaveInEvent` utilise le périphérique par défaut (`WAVE_MAPPER`, numéro -1). Si les applications de bureau
   n'ont pas accès au micro (Confidentialité), WinMM enregistre du silence numérique : Dictée le détecte (aucun échantillon
   non nul) et affiche un message. Un micro avec porte de bruit peut, rarement, déclencher ce message à tort si l'on ne parle pas.
7. **Alt droit.** La « touche masque » (VK 0xE8 simulée pendant le maintien) empêche l'activation du menu. À vérifier
   dans Office, où Alt seul affiche les info-bulles du ruban.
8. **Pastille.** `TopMost` passe par `WS_EX_TOPMOST` et `SetWindowPos(…, SWP_NOACTIVATE)` (et non la propriété `TopMost`,
   qui peut activer la fenêtre). Elle peut passer sous une application plein écran exclusive (jeux) : sans gravité.

## Choix à préserver

- `Dictee.Core` sans dépendance Windows : c'est ce qui permet de tester sous Linux et en CI.
- Consignes de nettoyage construites ligne par ligne avec `\n` (pas de chaîne multiligne) : une extraction Git en CRLF
  ne doit pas changer le texte envoyé à OpenAI.
- `HttpClient` sans délai global (`OpenAiClient.CreateHttpClient`) : chaque appel applique son délai (120 s / 60 s).
- Aucune journalisation : rien ne doit pouvoir écrire la clé ou le texte dicté sur disque.
