# Guide publication Google Play — SafeAlert

Compte Play Console disponible. App Store iOS : plus tard.

## 1. Préparer la signature (une seule fois)

```bash
cd frontend/android
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copier le modèle :

```bash
cp key.properties.example key.properties
# Éditer storePassword, keyPassword, keyAlias, storeFile
```

**Sauvegarder le `.jks` hors Git** (perte = impossible de mettre à jour l’app).  
Fichiers déjà ignorés : `key.properties`, `*.jks`.

### Secrets CI (optionnel, pour AAB signé en Actions)

| Secret GitHub | Contenu |
|---------------|---------|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEY_PROPERTIES` | contenu brut de `key.properties` |

Variable repo : `API_BASE_URL` = `https://safealert-api.onrender.com/api` (ou votre URL Render).

## 2. Build local signé

```bash
cd frontend
flutter pub get
flutter build appbundle --release --dart-define=API_BASE_URL=https://safealert-api.onrender.com/api
```

Fichier : `build/app/outputs/bundle/release/app-release.aab`

## 3. Play Console — checklist

1. **Créer l’application** → type App → gratuit → déclarations.
2. **Fiche Play** : titre, description courte/longue, icône 512×512, feature graphic 1024×500, captures téléphone.
3. **Classement du contenu** : questionnaire (sécurité personnelle / urgence).
4. **Cible / public** : pas enfants si SOS adulte ; politique de confidentialité **URL HTTPS obligatoire**.
5. **Data safety** : localisation, téléphone, notifications — déclarer usage SOS.
6. **Accès apps sensibles** : si SOS / contacts d’urgence, préparer justification.
7. **Pays** : RDC (+ autres) ; devise / distribution.
8. **Production ou tests** :
   - **Internal testing** : uploader l’AAB, ajouter testeurs e-mail → lien rapide.
   - **Closed / Open testing** avant production.
9. **Signer avec Play App Signing** : uploader la clé d’upload ; Google gère la clé app.

## 4. Alignement Render

L’APK/AAB doit pointer vers l’API Render :

```text
--dart-define=API_BASE_URL=https://<votre-service>.onrender.com/api
```

Vérifier avant soumission :

```bash
curl https://<votre-service>.onrender.com/health/ready
```

OTP réel = SerdiPay (clés à brancher) ou Twilio en secours. Sans SMS, les testeurs ne pourront pas se connecter en prod.

## 5. Après publication

- Suivre les crashs dans Play Console → Android Vitals.
- Chaque version : incrémenter `version` / `versionCode` dans `frontend/pubspec.yaml` (`1.0.0+1` → `1.0.1+2`).
- Tag Git `v1.0.1` pour déclencher le workflow Deploy (AAB artifact + image GHCR).
