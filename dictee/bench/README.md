# Banc d'essai : quel moteur transcrit le mieux vos dictées ?

Cet outil envoie **vos propres dictées** aux trois moteurs de transcription que Dictée sait utiliser,
puis compare ce qu'ils ont écrit avec le texte exact que vous avez dicté :

| Fournisseur | Modèle testé par défaut | Particularité |
|---|---|---|
| OpenAI | `gpt-transcribe` | Moteur par défaut de Dictée |
| Mistral (Voxtral) | `voxtral-small-transcribe-3` | Hébergé dans l'Union européenne |
| Microsoft (Azure) | `mai-transcribe-2` | Le moins cher (tarif promotionnel) |

Vous obtenez pour chacun :

- la **précision** (taux d'erreur sur les mots) ;
- la **justesse des termes juridiques** (OHADA, AUSCGIE, RCCM…) ;
- la **rapidité** ;
- un **coût estimé**.

Il vérifie aussi que les noms de modèles et le format des requêtes sont acceptés par chaque fournisseur.

Il n'y a rien à installer à part Python. Il faut compter une heure de préparation, puis quelques minutes d'exécution.

---

## 1. Enregistrer 20 à 30 dictées réelles

- Utilisez le **Dictaphone de l'iPhone** (fichiers `.m4a`) ou n'importe quel enregistreur.
  Formats acceptés : `.m4a`, `.wav`, `.mp3`, `.ogg`, `.flac`, `.webm`.
- Chaque dictée dure **de 5 à 60 secondes**. Dictez comme d'habitude, au rythme habituel, dans votre bureau habituel.
- Variez les contenus :
  - des phrases courantes ;
  - des sigles (AUSCGIE, CCJA, RCCM…) ;
  - des références d'articles ;
  - des montants et des dates ;
  - des noms propres ;
  - une ou deux dictées dans un endroit bruyant.
- Pour des raisons de confidentialité, préférez des textes **fictifs ou anonymisés** (voir la section 6).
- Transférez les fichiers sur l'ordinateur (AirDrop, « Partager › Enregistrer dans Fichiers », câble…).
- Rangez-les dans un dossier **`echantillons`** placé dans le dossier `bench` (à côté de `bench.py`).
  Donnez-leur des noms simples, sans accents si possible : `dictee-01.m4a`, `dictee-02.m4a`…

> Le dossier `echantillons/` et les rapports sont exclus de Git : vos enregistrements ne seront jamais
> publiés avec le projet.

## 2. Écrire le texte exact de chaque dictée

Pour chaque enregistrement, créez un fichier texte **du même nom** avec l'extension `.txt` :

```
echantillons/
  dictee-01.m4a
  dictee-01.txt   ← « L'assemblée générale de la SARL a révoqué le gérant le 3 mars 2026. »
  dictee-02.m4a
  dictee-02.txt
```

- Écrivez **exactement ce que vous avez dit**, comme vous voudriez le voir écrit.
  - Sur Mac, utilisez TextEdit, avec le menu « Format › Convertir au format texte ».
  - Sur Windows, utilisez le Bloc-notes.
- La ponctuation et les majuscules ne comptent pas dans la note : l'outil les ignore.
  Les **accents**, en revanche, comptent : « gerant » au lieu de « gérant » est une erreur.
- Écrivez les nombres comme vous voulez les obtenir (« article 1134 », « 3 mars 2026 ») :
  l'outil ne sait pas que « mille cent trente-quatre » et « 1134 » sont équivalents.
- Écrivez les sigles **en majuscules** (SA, SARL, CCJA). C'est ce qui permet de distinguer « SA » (société anonyme)
  du possessif « sa ».
- Si un `.txt` manque, la dictée est quand même transcrite (vous pourrez lire le résultat), mais elle n'est pas notée.

## 3. Obtenir les clés API

Vous n'avez besoin que des clés des fournisseurs que vous voulez tester. Chaque test est facturé
sur votre compte, mais c'est très peu : environ 0,10 à 0,30 $ par heure d'audio, soit quelques centimes pour 30 dictées.

- **OpenAI** : <https://platform.openai.com/api-keys>
  1. Cliquez sur « Create new secret key ».
  2. Copiez la clé (elle commence par `sk-`).
  3. Vérifiez qu'un moyen de paiement est enregistré, dans « Billing ».
- **Mistral** : <https://console.mistral.ai/api-keys>
  1. Choisissez une formule dans « Billing » (l'offre d'essai suffit pour un test).
  2. Cliquez sur « Create new key » et copiez la clé.
- **Microsoft Azure** : <https://portal.azure.com>
  1. Cliquez sur « Créer une ressource », puis cherchez **« Speech »** (Azure AI Speech, parfois
     présenté sous « Azure AI Services »).
  2. Choisissez un abonnement, un groupe de ressources (n'importe quel nom) et une **région**.
     Par exemple : `eastus` (valeur par défaut), ou `westeurope` / `swedencentral` pour rester en Europe.
     Vérifiez sur la page de MAI-Transcribe-2 que le modèle est proposé dans cette région.
  3. Prenez le niveau tarifaire « Standard S0 », puis créez la ressource.
  4. Une fois la ressource créée, ouvrez « Clés et point de terminaison ». Copiez **CLÉ 1** et notez
     l'**Emplacement/Région** (par exemple `westeurope`).

Les clés ne sont lues que dans la fenêtre du Terminal ou de PowerShell où vous les définissez. Elles ne sont
jamais affichées ni écrites dans un fichier par l'outil. Ne les collez jamais dans un e-mail ou un document.

## 4. Lancer le banc d'essai

### Sur Mac (application Terminal)

1. Vérifiez que Python est présent : tapez `python3 --version`, puis Entrée.
   Il faut la version 3.9 ou une version plus récente. Sinon, installez Python depuis <https://www.python.org/downloads/>.
   Après l'installation, double-cliquez sur « Install Certificates.command » dans le dossier
   Applications › Python 3.x. Sans cela, les connexions sécurisées échouent.
2. Placez-vous dans le dossier `bench`. Tapez `cd `, avec une espace, faites glisser le dossier `bench`
   depuis le Finder dans la fenêtre, puis appuyez sur Entrée.
3. Définissez les clés. Chaque commande demande la clé sans l'afficher : collez-la, puis appuyez sur Entrée.
   ```bash
   read -s OPENAI_API_KEY && export OPENAI_API_KEY
   read -s MISTRAL_API_KEY && export MISTRAL_API_KEY
   read -s AZURE_SPEECH_KEY && export AZURE_SPEECH_KEY
   export AZURE_SPEECH_REGION=westeurope   # la région de votre ressource Azure
   ```
4. Vérifiez d'abord le format, sans rien envoyer ni payer :
   ```bash
   python3 bench.py echantillons --dry-run
   ```
5. Lancez le vrai test :
   ```bash
   python3 bench.py echantillons --repeat 3
   ```

### Sur Windows (PowerShell)

1. Vérifiez que Python est présent : tapez `py --version`. Sinon, installez Python depuis
   <https://www.python.org/downloads/> ou depuis le Microsoft Store.
2. Ouvrez le dossier `bench` dans l'Explorateur, puis faites un clic droit dans le dossier et choisissez
   « Ouvrir dans le Terminal » (ou tapez `cd "C:\chemin\vers\bench"`).
3. Définissez les clés. Elles ne valent que pour cette fenêtre :
   ```powershell
   $env:OPENAI_API_KEY = "sk-..."
   $env:MISTRAL_API_KEY = "..."
   $env:AZURE_SPEECH_KEY = "..."
   $env:AZURE_SPEECH_REGION = "westeurope"
   ```
4. Vérifiez le format, puis lancez le test :
   ```powershell
   py bench.py echantillons --dry-run
   py bench.py echantillons --repeat 3
   ```

### Options utiles

| Option | Effet |
|---|---|
| `--dry-run` | Affiche les requêtes (adresse, en-têtes sans la clé, champs) sans rien envoyer. |
| `--repeat 3` | Passe chaque dictée 3 fois, pour une mesure de vitesse plus fiable. |
| `--providers openai,mistral` | Ne teste que certains fournisseurs. Par défaut, tous ceux dont la clé est définie sont testés. |
| `--compare-openai-models gpt-transcribe,gpt-4o-transcribe` | Compare plusieurs modèles OpenAI. Il existe aussi `--compare-mistral-models` et `--compare-microsoft-models`. |
| `--openai-model`, `--mistral-model`, `--microsoft-model` | Change le modèle testé, par exemple `--mistral-model voxtral-mini-transcribe-3`. |
| `--azure-region westeurope` | Région Azure. Remplace la variable AZURE_SPEECH_REGION. |
| `--language fr` | Langue (`fr` par défaut). |
| `--vocabulary "OHADA, CCJA, …"` | Vocabulaire envoyé aux moteurs. Par défaut, c'est celui de l'app. |
| `--vocabulary-file vocab.txt` | Lit le vocabulaire dans un fichier : un terme par ligne, ou des termes séparés par des virgules. |
| `--output-dir dossier` | Dossier des rapports. Par défaut, c'est le dossier `bench`. |

## 5. Lire les résultats et choisir

Le terminal affiche un récapitulatif comme celui-ci :

```
Configuration                       WER moyen  Latence méd.  Latence p90  Rappel vocab.  Erreurs  Coût/heure*  Coût du banc*
openai:gpt-transcribe               4,1 %      1 850 ms      2 900 ms     96,0 %         0/90     0,27 $       0,0405 $
mistral:voxtral-small-transcribe-3  5,3 %      1 400 ms      2 100 ms     92,0 %         0/90     0,24 $       0,0360 $
microsoft:mai-transcribe-2          6,0 %      1 100 ms      1 600 ms     88,0 %         0/90     0,10 $       0,0153 $
```

(Ces chiffres sont fictifs.)

Deux fichiers sont aussi créés dans le dossier `bench` :

- `rapport-AAAA-MM-JJ-HHMM.md` présente, pour chaque dictée, les transcriptions côte à côte et les différences
  marquées : ~~mot barré~~ pour un mot manquant ou mal transcrit, **mot en gras** pour un mot fautif ou en trop.
  Pour une mise en forme lisible, ouvrez-le dans un éditeur Markdown, Visual Studio Code ou Typora.
  Sinon, ouvrez-le dans un simple éditeur de texte.
- `rapport-AAAA-MM-JJ-HHMM.csv` contient toutes les mesures, appel par appel. Il s'ouvre directement dans Excel.

**Comment lire les colonnes :**

- **WER moyen** : la part des mots erronés (mots manquants, en trop ou remplacés). Plus il est bas, mieux c'est.
  - Moins de 5 % : excellent.
  - De 5 à 10 % : bon.
  - Au-delà de 15 %, les corrections deviennent pénibles.
  La ponctuation et les majuscules ne sont pas comptées.
- **Rappel vocab.** : sur les termes de votre vocabulaire (OHADA, RCCM, capital social…) présents dans vos dictées,
  la part qui est correctement écrite. C'est l'indicateur le plus parlant pour un texte juridique.
- **Latence méd.** : le temps typique entre l'envoi de l'enregistrement et la réception du texte.
  **Latence p90** : le temps dans les cas lents (9 appels sur 10 sont plus rapides).
  C'est le p90 qui donne l'impression de lenteur au quotidien.
- **Erreurs** : le nombre d'appels refusés, sur le total. Le détail des messages s'affiche sous le tableau
  et dans la section « Vérification du format » du rapport :
  - `401` ou `403` : la clé est invalide, ou elle n'a pas accès au service (pour Azure, vérifiez aussi la région) ;
  - `400` ou `404` mentionnant le modèle : le **nom du modèle** n'est pas reconnu. Essayez un autre nom
    avec `--openai-model`, `--mistral-model` ou `--microsoft-model`, et signalez-le : il faudra corriger
    le nom dans les réglages des apps (cahier des charges `dictee/SPEC.md`) ;
  - `400` mentionnant `definition`, `enhancedMode` ou `phraseList` (Microsoft) : le format Azure a changé.
    Il faudra l'adapter dans les apps ;
  - `429` : trop de requêtes, ou crédit épuisé. Relancez plus tard, ou vérifiez la facturation.
- **Coût/heure** et **Coût du banc** : des estimations tirées d'une table de prix placée en tête de `bench.py`.
  Ces prix sont **à vérifier** sur les pages tarifaires, car ils évoluent souvent.
  « n.d. » signifie que le prix de ce modèle n'est pas connu de l'outil.

**Pour choisir :**

1. Regardez d'abord la **précision** : le WER, puis le rappel du vocabulaire. Sur 20 à 30 dictées, un écart de
   moins de 1 à 2 points de WER n'est pas significatif ; considérez alors les moteurs comme équivalents.
2. Parcourez le rapport détaillé : une erreur sur un nom propre ou sur un sigle gêne plus qu'un « de » oublié.
3. Départagez ensuite sur la **latence p90**, puis sur le **coût** et l'**hébergement** :
   Mistral est hébergé dans l'UE, et Azure l'est aussi si vous choisissez une région européenne.
4. Réglez ensuite le fournisseur retenu dans Dictée (Réglages › Fournisseur), avec sa clé.

## 6. Confidentialité

- **Chaque enregistrement est envoyé à chacun des fournisseurs testés** (OpenAI aux États-Unis, Mistral
  dans l'UE, Microsoft dans la région Azure choisie), avec votre clé et selon leurs conditions d'utilisation de l'API.
  Avec `--repeat 3`, chaque fichier est envoyé trois fois à chacun.
- Compte tenu du secret professionnel, utilisez de préférence des **dictées fictives ou anonymisées**
  (noms de parties, montants et références modifiés). Elles mesurent la qualité aussi bien que de vraies dictées.
- Le nom de vos fichiers n'est jamais transmis : l'audio est toujours envoyé sous le nom `audio.m4a`, `audio.wav`…
- Les rapports contiennent le texte de vos dictées. Ils restent sur votre ordinateur et sont exclus de Git,
  comme le dossier `echantillons/`. Supprimez-les quand vous n'en avez plus besoin.
- Les clés ne sont lues que dans les variables d'environnement. Elles ne sont jamais affichées, ni écrites dans
  les rapports, ni conservées après la fermeture de la fenêtre.

## Pour les développeurs

- `bench.py` est un fichier unique, en bibliothèque standard, compatible Python 3.9 et plus.
  Les requêtes reproduisent `dictee/SPEC.md` §2 bis :
  - OpenAI : `prompt` contient le vocabulaire brut ;
  - Mistral : `context_bias` est répété pour chaque terme, sans `prompt` ni `response_format` ;
  - Azure : le corps contient deux parties, `audio` et `definition` (JSON) ;
  - le vocabulaire est découpé en 100 termes au maximum.
- Tests, sans réseau, depuis la racine du dépôt : `python3 -I -m unittest discover -s dictee/bench -v`.
- Normalisation pour le WER :
  - passage en minuscules (NFC) ;
  - apostrophes et tirets unifiés ;
  - ponctuation supprimée ;
  - élisions séparées (« l'assemblée » → « l' assemblée ») ;
  - accents conservés.
  La distance de Levenshtein est calculée sur les mots.
