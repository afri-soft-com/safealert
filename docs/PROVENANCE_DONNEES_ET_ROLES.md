# Provenance des données et rôles utilisateurs — SafeAlert

Référence technique décrivant **d'où provient chaque donnée** stockée en base PostgreSQL (Neon + PostGIS) et **ce que chaque rôle** peut faire dans l'application mobile, la console web d'administration et l'API REST.

Sources documentées : `backend/src/config/migrate.js`, `seed.js`, contrôleurs, [MANUEL_UTILISATEUR.md](MANUEL_UTILISATEUR.md), [DOCUMENTATION_VIVANTE.md](DOCUMENTATION_VIVANTE.md).

---

## 1. Légende des sources

| Source | Description |
|--------|-------------|
| **Saisie utilisateur (app)** | Données fournies par l'utilisateur via l'application Flutter |
| **Script seed** | Données initiales insérées par `npm run seed` |
| **Géocodage Nominatim** | Nom de zone dérivé des coordonnées GPS via OpenStreetMap (service `geocode.js`) |
| **Twilio** | Envoi SMS (OTP, alertes SOS aux contacts) — ne stocke pas de données en base |
| **Firebase (FCM)** | Token push enregistré côté utilisateur — notifications, pas de persistance Firebase |
| **Action administrateur** | Modification par un compte `platform_admin` (app ou console web) |
| **Vérification communautaire** | Confirmations d'incidents par d'autres citoyens |
| **Automatique** | Valeurs générées par le serveur ou la base (UUID, horodatages, compteurs, hash) |
| **Action responsable** | Leader ou agent via le mode responsable |
| **Admin de groupe** | Membre avec rôle `admin` dans `group_members` |

---

## 2. Provenance par table

### 2.1 `users` — Comptes utilisateurs

| Colonne | Provenance | Détail |
|---------|------------|--------|
| `id` | Automatique | `gen_random_uuid()` à la création |
| `phone` | Saisie utilisateur (app) | Normalisé E.164 (`+243…`) à l'inscription OTP |
| `pseudo` | Saisie utilisateur (app) | Requis à la première connexion |
| `role` | Automatique / Action administrateur | Défaut `citizen` ; promotion `leader`, `agent`, `platform_admin` par admin ou `PLATFORM_ADMIN_PHONE` à la migration |
| `sector_name` | Action administrateur | Assignation secteur géographique (ex. Gombe, Limete) pour leaders/agents |
| `fcm_token` | Firebase (app) | Enregistré via `PUT /api/auth/fcm-token` après init Firebase côté mobile |
| `avatar_url` | Saisie utilisateur (app) | Mise à jour profil (optionnel) |
| `last_lat`, `last_lng` | Saisie utilisateur (app) | GPS envoyé via `PUT /api/auth/position` |
| `last_seen_at` | Automatique | Mis à jour avec la position |
| `is_discreet_mode` | Saisie utilisateur (app) | Mode camouflage calculatrice |
| `share_presence` | Saisie utilisateur (app) | Partage ou non de la position |
| `created_at`, `updated_at` | Automatique | Horodatages serveur |

**Création** : première vérification OTP réussie (`POST /api/auth/verify-code`).  
**Suppression** : utilisateur via `DELETE /api/auth/account` (cascade sur incidents et contacts).

---

### 2.2 `otp_codes` — Codes de connexion temporaires

| Colonne | Provenance | Détail |
|---------|------------|--------|
| `id` | Automatique | UUID |
| `phone` | Saisie utilisateur (app) | Numéro demandant le code |
| `code_hash` | Automatique | Hash bcrypt du code à 6 chiffres généré serveur |
| `expires_at` | Automatique | TTL 5 minutes (`OTP_TTL_SECONDS = 300`) |
| `used_at` | Automatique | Renseigné à la validation OTP |
| `created_at` | Automatique | Horodatage insertion |

**Flux** : `POST /api/auth/request-code` génère le code, l'enregistre, envoie le SMS via **Twilio** (ou mode dev sans SMS). Le code en clair n'est **jamais** stocké en base.  
**Nettoyage** : codes expirés ou anciens supprimés à chaque nouvelle demande.

---

### 2.3 `trust_contacts` — Cercle de confiance

| Colonne | Provenance | Détail |
|---------|------------|--------|
| `id` | Automatique | UUID |
| `user_id` | Automatique | Utilisateur connecté (propriétaire du contact) |
| `contact_user_id` | Automatique (lien) | Renseigné si le numéro correspond à un compte SafeAlert existant (jointure `contact_phone = users.phone`) |
| `contact_name` | Saisie utilisateur (app) | Nom du proche |
| `contact_phone` | Saisie utilisateur (app) | Numéro à alerter en cas de SOS |
| `created_at` | Automatique | Horodatage |

**Création** : `POST /api/contacts` (max. 10 contacts).  
**Utilisation** : lors d'un SOS, le service `alert.js` envoie SMS (**Twilio**) et push **Firebase** aux contacts ayant un compte et un `fcm_token`.

---

### 2.4 `incidents` — Alertes SOS et signalements carte

| Colonne | Provenance | Détail |
|---------|------------|--------|
| `id` | Automatique | UUID |
| `user_id` | Automatique | Auteur du signalement (utilisateur connecté) |
| `incident_type` | Saisie utilisateur (app) | Ex. `sos`, `vol`, `agression`… |
| `description` | Saisie utilisateur (app) | Texte libre (optionnel) |
| `lat`, `lng` | Saisie utilisateur (app) | GPS au moment du SOS ou du signalement |
| `location` | Automatique | Point PostGIS `ST_MakePoint(lng, lat)` |
| `zone_name` | Géocodage Nominatim | Résolu à la création via `resolveZoneName()` (quartier / ville OSM) |
| `severity` | Automatique / Vérification communautaire / Action responsable | `alert` (SOS), `vigilance` (signalement), `danger` (≥ 3 confirmations), `safe` (zone calme après résolution) |
| `status` | Automatique / Saisie utilisateur / Vérification communautaire / Action responsable | Voir tableau ci-dessous |
| `acknowledged_by`, `acknowledged_at` | Action responsable | Leader/agent prenant en charge l'incident |
| `verified_by` | Vérification communautaire | Compteur incrémenté à chaque confirmation (`incident_verifications`) |
| `is_anonymous` | Saisie utilisateur (app) | Masque le pseudo sur la carte |
| `created_at` | Automatique | Horodatage création |
| `resolved_at` | Automatique / Saisie utilisateur / Action responsable | Annulation SOS, résolution leader |

**Origines des enregistrements**

| Action | Route | `severity` initial | `status` initial |
|--------|-------|------------------|------------------|
| Bouton SOS | `POST /api/sos/trigger` | `alert` | `active` |
| Signalement carte | `POST /api/map/incidents` | `vigilance` | `active` |
| Annulation SOS (2 min) | `POST /api/sos/cancel` ou `/:id/cancel` | inchangé | `false_alarm` |
| Confirmation citoyen | `POST /api/map/incidents/:id/verify` | → `danger` si ≥ 3 | → `verified` si ≥ 3 |
| Prise en charge | `PUT /api/leader/sector/incidents/:id/acknowledge` | inchangé | `acknowledged` → `in_progress` |
| Résolution | `PUT /api/leader/sector/incidents/:id/resolve` | → `safe` si zone calme 24 h | `resolved` |

**Notifications externes** : SMS Twilio et push Firebase déclenchés à la création/annulation SOS (pas stockés en base).

**Référence détaillée gravité / statut / heatmap** : voir [ZONES_GRAVITE.md](ZONES_GRAVITE.md) (critères exacts Danger, Vigilance, Sûr, Alerte ; acteurs ; distinction marqueurs vs densité heatmap).

---

### 2.5 `incident_verifications` — Confirmations communautaires

| Colonne | Provenance | Détail |
|---------|------------|--------|
| `id` | Automatique | UUID |
| `incident_id` | Automatique | Incident confirmé |
| `user_id` | Automatique | Citoyen confirmant (un seul vote par incident) |
| `created_at` | Automatique | Horodatage |

**Création** : `POST /api/map/incidents/:id/verify` — chaque confirmation incrémente `incidents.verified_by` et peut faire passer le statut à `verified` / gravité `danger`.

---

### 2.6 `emergency_numbers` — Annuaire d'urgence

| Colonne | Provenance | Détail |
|---------|------------|--------|
| `id` | Automatique | UUID |
| `country_code` | Script seed / Action administrateur | Défaut `CD` (RDC) |
| `service_name` | Script seed / Action administrateur | Ex. Police nationale, Pompiers |
| `service_type` | Script seed / Action administrateur | `police`, `medical`, `fire`… |
| `phone_number` | Script seed / Action administrateur | Numéro à appeler |
| `icon` | Script seed / Action administrateur | Emoji affiché |
| `is_offline_available` | Script seed / Action administrateur | Disponible en cache offline (défaut `true`) |
| `created_at` | Automatique | Horodatage |

**Seed** : `npm run seed` insère 5 numéros RDC (112, 15, 118, etc.) après purge de la table.  
**Lecture publique** : `GET /api/annuaire` (sans auth).  
**Cache mobile offline** : l'app Flutter stocke la réponse dans SQLite (`safealert_cache.db`, clé `annuaire`, TTL 24 h) via `AnnuaireProvider` ; affichage immédiat du cache puis rafraîchissement réseau.  
**Gestion admin** : CRUD via `GET/POST/PUT/DELETE /api/admin/emergency-numbers` (console web ou API).

---

### 2.7 `neighborhood_groups` — Groupes de voisins

| Colonne | Provenance | Détail |
|---------|------------|--------|
| `id` | Automatique | UUID |
| `name` | Saisie utilisateur (app) | Nom du groupe |
| `description` | Saisie utilisateur (app) | Description (optionnelle) |
| `zone_name` | Saisie utilisateur (app) | Quartier déclaré (texte libre, pas de géocodage auto) |
| `created_by` | Automatique | Créateur du groupe |
| `invite_code` | Automatique | Code hex 8 caractères (`crypto.randomBytes`) |
| `member_count` | Automatique | Incrémenté/décrémenté à l'adhésion / départ |
| `created_at` | Automatique | Horodatage |

**Création** : `POST /api/groups` — le créateur devient admin dans `group_members`.

---

### 2.8 `group_members` — Membres des groupes

| Colonne | Provenance | Détail |
|---------|------------|--------|
| `id` | Automatique | UUID |
| `group_id` | Automatique | Groupe concerné |
| `user_id` | Automatique / Admin de groupe | Créateur à la création ; autres à l'approbation d'une demande |
| `role` | Automatique / Admin de groupe | `admin` (créateur) ou `member` (membres approuvés) |
| `joined_at` | Automatique | Horodatage adhésion |

**Note** : le rôle `admin` dans cette table est **indépendant** du rôle plateforme `users.role`.

---

### 2.9 `group_join_requests` — Demandes d'adhésion

| Colonne | Provenance | Détail |
|---------|------------|--------|
| `id` | Automatique | UUID |
| `group_id` | Automatique | Groupe visé (via code d'invitation) |
| `user_id` | Automatique | Demandeur |
| `status` | Saisie utilisateur (app) / Admin de groupe | `pending` → `approved` ou `rejected` |
| `created_at` | Automatique | Horodatage demande |

**Flux** : `POST /api/groups/:id/join` avec `invite_code` crée une demande `pending`. L'admin du groupe approuve (`approve`) ou refuse (`reject`) via l'app.

---

### 2.10 `partner_api_keys` — Clés API partenaires

| Colonne | Provenance | Détail |
|---------|------------|--------|
| `id` | Automatique | UUID |
| `partner_name` | Action administrateur | Nom de l'organisme (ONG, autorité…) |
| `api_key` | Automatique | Clé 64 caractères générée serveur (`generateApiKey`) |
| `is_active` | Action administrateur | `true` à la création ; `false` à la révocation |
| `rate_limit` | Action administrateur | Défaut 1000 requêtes (configurable à la création) |
| `created_at` | Automatique | Horodatage |
| `expires_at` | Action administrateur | Optionnel (non défini par défaut) |

**Création** : `POST /api/admin/partners` ou `POST /api/partner/register` (réservé `platform_admin`).  
**Usage** : authentification en-tête `X-API-Key` sur `/api/partner/*` — **aucun compte utilisateur** associé.

---

## 3. Schéma synthétique des flux de données

```
┌─────────────┐     OTP SMS      ┌──────────┐     INSERT      ┌─────────────┐
│  App mobile │ ───────────────► │  Twilio  │                 │  otp_codes  │
│  (Flutter)  │ ◄── JWT ──────── │          │                 └─────────────┘
└──────┬──────┘                  └──────────┘                        │
       │ saisie profil / GPS / contacts                               │ verify
       ▼                                                              ▼
┌─────────────┐     zone_name    ┌──────────────┐              ┌─────────────┐
│   users     │ ◄─────────────── │  Nominatim   │              │   users     │
│trust_contacts│                │  (OSM)       │              └─────────────┘
└──────┬──────┘                  └──────┬───────┘
       │ SOS / signalement              │ reverse geocode
       ▼                                ▼
┌─────────────┐     confirm     ┌──────────────────────┐
│  incidents  │ ◄────────────── │ incident_verifications│
└──────┬──────┘                 └──────────────────────┘
       │ acknowledge / resolve
       ▼
┌─────────────┐                  ┌─────────────────────┐
│leader/agent │                  │ partner_api_keys    │──► API lecture seule
└─────────────┘                  └─────────────────────┘

┌──────────────────┐  seed / admin   ┌────────────────────┐
│ emergency_numbers  │ ◄────────────── │ seed.js / admin-web │
└──────────────────┘                 └────────────────────┘

┌────────────────────┐  app utilisateur  ┌───────────────────┐
│neighborhood_groups │ ◄─────────────── │ group_members     │
│group_join_requests │                  │ (admin / member)  │
└────────────────────┘                  └───────────────────┘
```

---

## 4. Rôles utilisateurs

SafeAlert distingue **quatre rôles plateforme** (`users.role`), un **rôle de groupe** (`group_members.role`) et les **partenaires API** (hors compte applicatif).

### 4.1 Vue d'ensemble

| Rôle | Code | Compte app | Compte admin web | Auth API |
|------|------|------------|------------------|----------|
| Citoyen | `citizen` | Oui (défaut) | Non | JWT |
| Responsable | `leader` | Oui | Non | JWT |
| Agent | `agent` | Oui | Non | JWT |
| Administrateur plateforme | `platform_admin` | Oui | Oui | JWT |
| Admin de groupe | `group_members.role = admin` | Oui (tout rôle plateforme) | Non | JWT |
| Partenaire | — (clé API) | **Non** | **Non** | `X-API-Key` |

---

### 4.2 Citoyen (`citizen`)

Rôle par défaut à l'inscription. Cible principale de SafeAlert.

| Canal | Capacités |
|-------|-----------|
| **Application mobile** | Connexion OTP ; bouton SOS et annulation (2 min) ; signalements carte ; confirmation d'incidents ; cercle de confiance (CRUD) ; annuaire urgence (lecture + cache offline) ; carte, stats, heatmap ; groupes voisins (créer, demander à rejoindre, quitter) ; mode discret ; profil et paramètres ; suppression de compte ; mode invité (carte + annuaire sans compte) |
| **Console web admin** | Aucun accès |
| **API REST (JWT)** | Routes auth, SOS, carte, contacts, groupes, historique — **sans** `/api/leader/*`, `/api/admin/*`, `/api/report` |

---

### 4.3 Responsable (`leader`)

Même base que le citoyen, plus le **mode responsable** pour superviser les incidents.

| Canal | Capacités |
|-------|-----------|
| **Application mobile** | Tout citoyen + écran **Mode responsable** : incidents du secteur assigné (`sector_name`), prise en charge, résolution, statistiques secteur, export PDF |
| **Console web admin** | Aucun accès |
| **API REST (JWT)** | `GET /api/leader/sector/incidents`, `PUT …/acknowledge`, `PUT …/resolve`, `GET /api/leader/sector/stats`, `GET /api/report` (PDF) |

**Filtrage secteur** : si `sector_name` est renseigné (ex. `Gombe`), seuls les incidents dont `zone_name` correspond (recherche `ILIKE`) sont visibles. Sans secteur, tous les incidents actifs sont listés.

---

### 4.4 Agent (`agent`)

Fonctionnellement **identique au responsable** (`leader`) dans le code actuel : mêmes routes protégées par `requireRole("leader", "agent")`.

| Canal | Capacités |
|-------|-----------|
| **Application mobile** | Identique au responsable |
| **Console web admin** | Aucun accès |
| **API REST (JWT)** | Identique au responsable |

La distinction `leader` / `agent` est **organisationnelle** (affectation métier) ; les permissions techniques sont les mêmes.

---

### 4.5 Administrateur plateforme (`platform_admin`)

Supervise l'instance SafeAlert. Promu manuellement (SQL, `PLATFORM_ADMIN_PHONE` à la migration, ou par un autre admin).

| Canal | Capacités |
|-------|-----------|
| **Application mobile** | Tout citoyen + écran **Administration** : liste utilisateurs, changement de rôles, attribution de secteurs, création/révocation de clés partenaires |
| **Console web admin** | Connexion OTP ; tableau de bord ; gestion utilisateurs (rôles, secteurs) ; partenaires API ; annuaire urgence (CRUD) ; liste incidents (filtres) ; liste groupes |
| **API REST (JWT)** | Toutes les routes `/api/admin/*` : utilisateurs, partenaires, stats, numéros urgence, incidents, groupes ; `POST /api/partner/register` |

**Restrictions** : un admin ne peut pas se retirer son propre rôle `platform_admin` via l'API. Reconnexion requise après changement de rôle pour rafraîchir le JWT.

---

### 4.6 Administrateur de groupe (`group_members.role = admin`)

Rôle **local au groupe**, distinct du rôle plateforme. Le créateur d'un groupe en est automatiquement admin.

| Canal | Capacités |
|-------|-----------|
| **Application mobile** | Voir les demandes d'adhésion en attente ; **approuver** ou **refuser** les demandes (`group_join_requests`) ; gérer les membres de son groupe ; partager le code d'invitation |
| **Console web admin** | Aucun accès (lecture seule des groupes pour `platform_admin`) |
| **API REST (JWT)** | `GET /api/groups/:id/join-requests`, `POST …/approve`, `POST …/reject` — contrôle `isGroupAdmin()` |

Un citoyen sans rôle plateforme élevé peut être admin de groupe.

---

### 4.7 Partenaires API (clés `partner_api_keys`)

Organismes externes (ONG, services publics, intégrateurs) — **pas de rôle applicatif**, pas d'OTP, pas d'écran mobile.

| Canal | Capacités |
|-------|-----------|
| **Application mobile** | Aucun accès |
| **Console web admin** | Aucun accès (la clé est créée par un `platform_admin`) |
| **API REST (`X-API-Key`)** | `GET /api/partner/stats` — statistiques agrégées ; `GET /api/partner/incidents` — incidents publics (lecture) ; `GET /api/partner/heatmap` — carte de chaleur par zone |

**Création de clé** : réservée aux `platform_admin` (`POST /api/admin/partners`). La clé n'est affichée qu'une fois à la création.

---

## 5. Matrice des permissions par endpoint (résumé)

| Domaine | Citoyen | Leader / Agent | Platform admin | Partenaire (API Key) |
|---------|---------|----------------|----------------|----------------------|
| Auth / profil | ✓ | ✓ | ✓ | — |
| SOS / signalements | ✓ | ✓ | ✓ | — |
| Confirmer incident | ✓ | ✓ | ✓ | — |
| Contacts confiance | ✓ | ✓ | ✓ | — |
| Groupes voisins | ✓ | ✓ | ✓ | — |
| Admin groupe (approve/reject) | Si admin groupe | Si admin groupe | Si admin groupe | — |
| Mode responsable / PDF | — | ✓ | ✓* | — |
| `/api/admin/*` | — | — | ✓ | — |
| `/api/partner/*` (lecture) | — | — | — | ✓ |
| Annuaire public | ✓ (sans auth) | ✓ | ✓ | — |

\* Un `platform_admin` peut techniquement appeler les routes leader s'il possède le JWT adéquat, mais l'interface dédiée est le mode responsable (rôle leader/agent recommandé pour l'usage opérationnel).

---

## 6. Promotion et gouvernance des rôles

| Action | Méthode |
|--------|---------|
| Premier admin | `PLATFORM_ADMIN_PHONE=+243… npm run migrate` (compte existant) ou `UPDATE users SET role = 'platform_admin' WHERE phone = '…'` |
| Changer rôle utilisateur | Admin : app Administration ou `PATCH /api/admin/users/:id/role` |
| Assigner secteur | Admin : `PATCH /api/admin/users/:id/sector` avec `{ "sector_name": "Gombe" }` |
| Créer clé partenaire | Admin : console web ou `POST /api/admin/partners` |
| Admin de groupe | Automatique à la création du groupe ; non transférable via API actuelle |

---

## 7. Documents connexes

| Document | Contenu |
|----------|---------|
| [MANUEL_UTILISATEUR.md](MANUEL_UTILISATEUR.md) | Guide pas à pas pour les citoyens |
| [DOCUMENTATION_VIVANTE.md](DOCUMENTATION_VIVANTE.md) | Architecture, CI/CD, changelog |
| [ADMIN_WEB.md](ADMIN_WEB.md) | Console d'administration web |
| [EXTERNAL_APIS.md](EXTERNAL_APIS.md) | Twilio, Firebase, Nominatim |
| [ZONES_GRAVITE.md](ZONES_GRAVITE.md) | Critères gravité (alert, danger, vigilance, safe), statuts incident, heatmap vs marqueurs |

---

*Dernière mise à jour : juin 2026 — aligné sur le schéma `migrate.js` et les contrôleurs backend.*
