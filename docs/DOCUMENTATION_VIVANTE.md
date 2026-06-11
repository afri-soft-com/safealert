# Documentation vivante — SafeAlert

Document technique maintenu au fil de l'évolution du code. À mettre à jour à chaque changement significatif.

---

## 1. Vue d'ensemble de l'architecture

```
┌─────────────────┐     HTTPS/REST      ┌──────────────────────────────┐
│  Flutter App    │ ◄──────────────────► │  API Node.js (Express)       │
│  Android / iOS  │     WebSocket (SOS)  │  Docker → GHCR → VPS         │
└────────┬────────┘                      └───────┬──────────┬───────────┘
         │ SQLite cache                         │          │
         │ offline-first                        ▼          ▼
         │                               ┌──────────┐ ┌────────┐
         │                               │ Neon     │ │ Redis  │
         │                               │ Postgres │ │ (VPS)  │
         │                               │ + PostGIS│ │ cache  │
         └─ FCM push ◄───────────────────┴──────────┘ └────────┘
                    Firebase
                    Twilio SMS (OTP, alertes)
```

| Composant | Rôle | Hébergement |
|-----------|------|-------------|
| **Frontend** | UI Flutter, cache SQLite, SOS discret | APK / Play Store |
| **Backend** | API REST, JWT, OTP, FCM, PDF | VPS Docker (image GHCR) |
| **Neon** | PostgreSQL managé + PostGIS | Cloud Neon |
| **Redis** | Cache sessions / rate-limit optionnel | VPS (docker-compose) |
| **Twilio** | SMS OTP et notifications | SaaS |
| **Firebase** | Push FCM | Google Cloud |

Référence détaillée des clés API : [EXTERNAL_APIS.md](EXTERNAL_APIS.md).

---

## 2. Exécution en local

### Prérequis

- Flutter 3.32+
- Node.js 20+
- Docker (Postgres local) ou compte Neon
- Téléphone Android physique (recommandé pour OTP / GPS / volume SOS)

### Backend (PC)

```bash
cd backend
cp .env.example .env
# DATABASE_URL, JWT_SECRET (32+ caractères)
npm install
npm run migrate
npm run seed   # optionnel
npm run dev    # http://localhost:3000
```

### Frontend (PC + appareil Android)

```bash
cd frontend
flutter pub get
# IP locale du PC (ipconfig / ifconfig), pas localhost :
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000/api
```

**Points importants :**

- PC et téléphone sur le **même Wi-Fi**.
- Autoriser le port **3000** dans le pare-feu Windows.
- Pour OTP sans Twilio : `NODE_ENV=development` + variables Twilio vides → code dans le terminal (`[DEV OTP]`) et champ `devCode` côté app (debug).

### Tests

```bash
cd backend && npm test
cd frontend && flutter analyze && flutter test
```

---

## 3. Variables d'environnement

Voir le tableau complet dans [EXTERNAL_APIS.md](EXTERNAL_APIS.md).

| Variable | Obligatoire prod | Description |
|----------|------------------|-------------|
| `DATABASE_URL` | Oui | Neon pooler ou Postgres local |
| `JWT_SECRET` | Oui (32+ chars) | Signature JWT |
| `TWILIO_*` | Recommandé | SMS OTP / alertes |
| `FCM_*` | Optionnel | Push notifications |
| `REDIS_URL` | Optionnel | Cache (`redis://redis:6379`) |
| `CORS_ORIGIN` | Prod | Origines autorisées |

Fichiers modèles : `backend/.env.example`, `.env.production.example`.

---

## 4. CI/CD

Fichiers : `.github/workflows/ci.yml`, `.github/workflows/deploy.yml`.

### Pipeline CI (chaque push / PR)

1. **Backend** : install → lint → migration test → `npm test` (Vitest + supertest, DB mockée).
2. **Frontend** : `flutter pub get` → `flutter analyze` → `flutter test`.

### Pipeline Deploy

- Déclenchement : tag `v*` ou `workflow_dispatch`.
- Build image Docker backend → push **GHCR** (`ghcr.io/...`).
- Déploiement SSH optionnel sur VPS (`deploy/deploy.sh`).

### Stack production (VPS)

```bash
docker compose --env-file .env.production up -d
# Neon : docker-compose.neon.yml
# TLS : docker compose --profile proxy up -d
```

---

## 5. Maintenir cette documentation

| Événement code | Action doc |
|----------------|------------|
| Nouvel écran / fonction utilisateur | Mettre à jour [MANUEL_UTILISATEUR.md](MANUEL_UTILISATEUR.md) |
| Nouvelle variable d'env ou API externe | Mettre à jour [EXTERNAL_APIS.md](EXTERNAL_APIS.md) |
| Changement architecture / déploiement | Mettre à jour ce fichier |
| Correctif ou feature livrée | Ajouter une entrée **Changelog** ci-dessous |
| Nouvelle route API | Mettre à jour `README.md` (table endpoints) |

**Règle :** toute PR qui modifie le comportement visible ou le déploiement doit inclure la mise à jour doc associée.

---

## 6. État du projet (juin 2026)

| Domaine | Avancement | Notes |
|---------|------------|-------|
| Auth OTP téléphone | ~95 % | Normalisation E.164 (+243), Twilio + mode dev |
| SOS + annulation | ~90 % | GPS, FCM, contacts |
| Carte incidents | ~85 % | OSM, filtres, signalement |
| Contacts confiance | ~90 % | CRUD + cache offline |
| Annuaire urgence | ~95 % | Cache 24h |
| Groupes voisins | ~80 % | Création, join par code |
| Mode discret | ~75 % | Calculatrice + volume Android |
| Leader / PDF | ~70 % | Rôle leader requis |
| Push FCM | ~60 % | Nécessite config Firebase |
| iOS volume SOS | ~20 % | Limitation plateforme |

### Lacunes connues (non bloquantes)

- Appels téléphoniques depuis l'annuaire (bouton numéro non câblé à `url_launcher`).
- Heatmap simplifiée (grille, pas de tuiles cartographiques).
- Pas de publication Play Store automatisée dans CI.
- iOS : pas de SOS discret par volume.

---

## 7. Changelog

### 2026-06-11

- **OTP E.164** : normalisation `+243` côté backend (`utils/phone.js`) et frontend (`lib/utils/phone.dart`).
- **Overflow UI** : corrections responsive sur login, top bar, nav bar, carte, annuaire, SOS, paramètres, groupes, leader, accueil ; tests widget 320dp et clavier.
- **Twilio / dev** : logs OTP dev via `logger.log` (pas de `console.log` direct en prod) ; `devCode` en développement uniquement.
- **Tests backend** : le serveur HTTP ne démarre plus sous Vitest (`NODE_ENV=test` / `VITEST`) — évite `EADDRINUSE` port 3000.
- **Docs** : ajout manuel utilisateur FR et documentation vivante.

### Historique antérieur

- Stack Neon + Redis VPS + déploiement GHCR.
- Cache SQLite offline-first (providers Flutter).
- CI GitHub Actions backend + frontend.

---

## 8. Liens utiles

| Document | Public |
|----------|--------|
| [MANUEL_UTILISATEUR.md](MANUEL_UTILISATEUR.md) | Utilisateurs finaux |
| [EXTERNAL_APIS.md](EXTERNAL_APIS.md) | DevOps / intégrations |
| [NEON_SETUP.md](NEON_SETUP.md) | Configuration base Neon |
| [README.md](../README.md) | Démarrage rapide développeur |

---

*Maintenu par l'équipe SafeAlert — dernière révision : 11 juin 2026*
