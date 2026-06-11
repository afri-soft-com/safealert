# Gravité des zones et statuts d'incidents — SafeAlert

Référence **exacte** des règles en vigueur (juin 2026), alignée sur :

- `backend/src/controllers/mapController.js`
- `backend/src/controllers/sosController.js`
- `backend/src/controllers/leaderController.js`
- `frontend/lib/screens/map_screen.dart`
- `frontend/lib/screens/heatmap_screen.dart`
- `frontend/lib/screens/dashboard_screen.dart`

---

## 1. Deux concepts distincts

| Concept | Champ BDD | Rôle | Valeurs possibles |
|---------|-----------|------|-------------------|
| **Gravité** (`severity`) | `incidents.severity` | Niveau d'urgence affiché sur la carte (couleur du marqueur) | `alert`, `vigilance`, `danger`, `safe` |
| **Statut** (`status`) | `incidents.status` | Cycle de vie opérationnel de l'incident | `active`, `verified`, `acknowledged`, `in_progress`, `resolved`, `false_alarm` |

La gravité et le statut évoluent **indépendamment** sauf lors d'actions qui modifient les deux en même temps (confirmation communautaire, résolution responsable).

---

## 2. Gravité (`severity`) — critères et couleurs

| Gravité (code) | Libellé UI | Couleur carte | Critère d'attribution | Qui déclenche |
|----------------|------------|---------------|----------------------|---------------|
| `alert` | Alerte | Rouge (`AppColors.rouge`) | Création d'un **SOS** (`POST /api/sos/trigger`) | Citoyen (bouton SOS) — **automatique** à l'insertion |
| `vigilance` | Vigilance | Orange (`AppColors.orange`) | Création d'un **signalement carte** (`POST /api/map/incidents`) | Citoyen (signalement) — **automatique** à l'insertion |
| `danger` | Danger | Rouge (même couleur que `alert`) | Lorsque `verified_by` atteint **≥ 3** confirmations | **Vérification communautaire** (`POST /api/map/incidents/:id/verify`) — **automatique** au 3ᵉ vote |
| `safe` | Sûr | Vert (`AppColors.vert`) | Résolution par un responsable **et** aucun autre incident actif dans la même zone sur les **24 dernières heures** | **Action responsable** (`PUT /api/leader/sector/incidents/:id/resolve`) — **automatique** si zone calme |

### Règles complémentaires sur la gravité

| Situation | Gravité résultante |
|-----------|-------------------|
| SOS créé | `alert` (inchangé tant qu'aucune action ne modifie `severity`) |
| Signalement créé | `vigilance` |
| 1ᵉ ou 2ᵉ confirmation citoyen | Inchangée (`alert` ou `vigilance` selon l'origine) |
| 3ᵉ confirmation citoyen (ou plus) | `danger` |
| Annulation SOS (2 min) | Inchangée (l'incident passe en `false_alarm` mais `severity` reste `alert`) |
| Prise en charge responsable (`acknowledge`) | Inchangée |
| Résolution responsable, **autres incidents actifs** dans la zone (24 h) | Inchangée |
| Résolution responsable, **zone calme** (0 autre incident actif 24 h) | `safe` sur l'incident résolu |

> **Note** : un SOS (`alert`) peut devenir `danger` si 3 citoyens le confirment — la logique de vérification ne distingue pas SOS et signalement.

---

## 3. Statut (`status`) — cycle de vie

| Statut | Signification | Qui déclenche | Effet sur la carte |
|--------|---------------|---------------|-------------------|
| `active` | Incident ouvert, non confirmé (ou &lt; 3 confirmations) | Défaut à la création SOS / signalement | **Visible** |
| `verified` | Confirmé par la communauté (≥ 3 votes) | Automatique à la 3ᵉ confirmation | **Visible** |
| `acknowledged` | Pris en charge par un responsable | Leader / agent (`PUT …/acknowledge` depuis `active` ou `verified`) | **Visible** |
| `in_progress` | Traitement en cours | Leader / agent (2ᵉ appel `acknowledge` depuis `acknowledged`) | **Visible** |
| `resolved` | Clôturé par un responsable | Leader / agent (`PUT …/resolve`) | **Masqué** (hors filtre carte) |
| `false_alarm` | SOS annulé par l'auteur (≤ 2 min) | Citoyen (`POST /api/sos/cancel` ou `cancel-latest`) | **Masqué** |

La carte (`GET /api/map/incidents`) ne retourne que les incidents dont le statut est dans : `active`, `verified`, `acknowledged`, `in_progress`.

---

## 4. Matrice des actions → gravité + statut

| Action | Acteur | Route | `severity` | `status` |
|--------|--------|-------|------------|----------|
| Déclencher SOS | Citoyen | `POST /api/sos/trigger` | `alert` | `active` |
| Signaler sur la carte | Citoyen | `POST /api/map/incidents` | `vigilance` | `active` |
| Confirmer (1ᵉ–2ᵉ fois) | Citoyen | `POST /api/map/incidents/:id/verify` | inchangé | `active` |
| Confirmer (3ᵉ fois+) | Citoyen | idem | `danger` | `verified` |
| Annuler SOS | Citoyen (auteur, ≤ 2 min) | `POST /api/sos/cancel` | inchangé | `false_alarm` |
| Prendre en charge | Leader / agent | `PUT /api/leader/sector/incidents/:id/acknowledge` | inchangé | `acknowledged` ou `in_progress` |
| Résoudre (zone encore active) | Leader / agent | `PUT /api/leader/sector/incidents/:id/resolve` | inchangé | `resolved` |
| Résoudre (zone calme 24 h) | Leader / agent | idem | `safe` | `resolved` |

**Géocodage** : à chaque création SOS ou signalement, `zone_name` est résolu automatiquement via Nominatim/OSM (`resolveZoneName`) — sans impact direct sur gravité ou statut.

---

## 5. Affichage carte vs heatmap vs tableau de bord

### 5.1 Marqueurs carte (`map_screen.dart`)

| Élément | Source | Règle |
|---------|--------|-------|
| Couleur marqueur | `incidents.severity` | `alert` / `danger` → rouge ; `vigilance` → orange ; `safe` → vert |
| Chiffre au centre | `verified_by` | Nombre de confirmations communautaires |
| Légende | UI fixe | « Danger », « Vigilance », « Sûr » (le rouge regroupe `alert` et `danger`) |
| Filtre temporel | `hours` (24 h ou 7 j) | Incidents récents selon `created_at` |
| Filtre type | `incident_type` | Optionnel (agression, vol, etc.) |

### 5.2 Carte de chaleur (`heatmap_screen.dart` + `getHeatmap`)

| Élément | Source | Règle |
|---------|--------|-------|
| **Intensité** (barre, fond, couleur zone) | `total` par `zone_name` | `intensity = total_zone / max(total_toutes_zones)` sur la période (défaut **30 jours**) |
| Couleur intensité | Calcul frontend | `> 60 %` → rouge ; `> 30 %` → orange ; sinon vert |
| Compteur « alertes » | `severity = 'alert'` | Nombre de SOS sur la période |
| Compteur « vigil. » | `severity = 'vigilance'` | Signalements non confirmés (ou redevenus vigilance) |
| Compteur `danger` | Backend agrège | Présent en API mais non affiché séparément dans l'UI actuelle |

> **Important** : l'intensité heatmap mesure la **densité totale d'incidents** par quartier, pas la gravité maximale d'un marqueur. Une zone peut être « Élevé » (rouge) par volume tout en ayant des incidents individuels en `vigilance`.

### 5.3 Tableau de bord (`dashboard_screen.dart` + `getStats`)

| Métrique | Période | Calcul backend |
|----------|---------|----------------|
| Incidents cette semaine | 7 jours | `COUNT(*)` tous incidents |
| Alertes SOS envoyées | 7 jours | `COUNT(*) WHERE severity = 'alert'` |
| Utilisateurs actifs | 24 h | Utilisateurs avec `last_seen_at` récent |
| Zones sécurisées | 30 jours | Quartiers (`zone_name`) avec incidents `status = 'verified'` et **moins de 3** incidents groupés |
| Incidents par jour | 7 jours | Agrégation par jour de la semaine |
| Heures à risque | 7 jours | % des incidents par tranche horaire |

---

## 6. Schéma de flux simplifié

```
                    ┌─────────────┐
                    │   Création   │
                    └──────┬──────┘
           ┌─────────────────┼─────────────────┐
           ▼                 ▼                 │
      SOS (citoyen)    Signalement (citoyen)   │
   severity=alert    severity=vigilance        │
   status=active     status=active             │
           │                 │                 │
           └────────┬────────┘                 │
                    ▼                          │
         Confirmations citoyens (verify)       │
         verified_by++                         │
                    │                          │
         ┌──────────┴──────────┐               │
         │ < 3 confirmations   │ ≥ 3           │
         │ severity inchangé   │ severity=danger│
         │ status=active       │ status=verified│
         └──────────┬──────────┘               │
                    ▼                          │
         Prise en charge (leader/agent)        │
         status → acknowledged → in_progress │
         severity inchangé                     │
                    ▼                          │
         Résolution (leader/agent)            │
         status=resolved                      │
         severity=safe si zone calme 24h       │
                    │                          │
         Annulation SOS ≤2min (citoyen) ───────┘
         status=false_alarm
```

---

## 7. Documents connexes

| Document | Contenu |
|----------|---------|
| [PROVENANCE_DONNEES_ET_ROLES.md](PROVENANCE_DONNEES_ET_ROLES.md) | Provenance des champs et rôles utilisateurs |
| [MANUEL_UTILISATEUR.md](MANUEL_UTILISATEUR.md) | Guide citoyen |
| [EXTERNAL_APIS.md](EXTERNAL_APIS.md) | Géocodage Nominatim |

---

*Dernière mise à jour : juin 2026 — reflète le code des contrôleurs et écrans Flutter listés en tête de document.*
