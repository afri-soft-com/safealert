# SafeAlert — Fonctionnalités livrées (extension)

Document de suivi des capacités ajoutées. Branding : **SafeAlert**. Produit en français (i18n FR / LN / SW / EN).

## Feature flags (backend)

Variables `FEATURE_*=true|1|yes` — voir `backend/src/config/features.js`.

| Flag | Défaut | Capacité |
|------|--------|----------|
| `FEATURE_CHECK_IN` | on | Check-in « Je suis en sécurité » |
| `FEATURE_SAFE_TRIP` | on | Trajet sécurisé + ETA + auto-alerte |
| `FEATURE_LIVE_STATUS` | on | Position + batterie pendant SOS (TTL ~90s) |
| `FEATURE_TRUST_ZONES` | on | Zones domicile / travail / école |
| `FEATURE_NEIGHBORHOOD_WATCH` | on | Abonnement quartier + digest |
| `FEATURE_WITNESS_EVIDENCE` | on | Preuves photo/audio (consent, rétention 7j) |
| `FEATURE_RELIABILITY_SCORE` | on | Score fiabilité signalements |
| `FEATURE_ESCORT_MODE` | on | Escorte (contacts suivent le trajet) |
| `FEATURE_FIELD_DISPATCH` | on | Assignation agent, chat, clôture |
| `FEATURE_SECTOR_GEOFENCE` | on | Alerte leaders sur SOS secteur |
| `FEATURE_OPS_DASHBOARD` | on | File SOS / SLA / busy map |
| `FEATURE_AUTO_REPORTS` | on | Export PDF/CSV secteur |
| `FEATURE_PARTNER_WEBHOOKS` | on | Webhooks partenaires |
| `FEATURE_PREMIUM` | **off** | Stub abonnement (illimité trajets/contacts) |
| `FEATURE_CONTACT_BACKUP` | on | Backup contacts chiffré côté client |
| `FEATURE_OFFLINE_QUEUE` | on | File hors-ligne étendue |

Après déploiement : `npm run migrate` dans `backend/`.

---

## Priorité haute

1. **Appel 1 tap annuaire** — Flutter `url_launcher` `tel:` sur chaque numéro.
2. **Check-in** — `POST /api/checkin` + bouton SOS « Je suis en sécurité ».
3. **Trajet sécurisé** — `POST /api/trips`, ping, arrive, cancel ; job overdue → SOS.
4. **SOS discret renforcé** — volume ↓ (existant) + secousse (`sensors_plus`) + raccourci Android (`quick_actions`). Widget home natif : non livré (voir partial).
5. **Statut live SOS** — `POST /api/sos/live` + socket `sos_live` ; batterie via `battery_plus`.
6. **Fausse alerte** — cancel → statut `false_alarm`, push/SMS explicites « Fausse alerte ».

## Priorité moyenne

7. **Zones de confiance** — CRUD `/api/trust-zones` + UI.
8. **Veille quartier** — `/api/neighborhood` + digest horaire.
9. **Preuves** — `evidence` + `consent_evidence` sur `POST /api/map/incidents`.
10. **Score fiabilité** — colonnes + bump à la confirmation.
11. **Escorte** — `escort_contact_ids` sur trajet + accès `GET /api/trips/:id`.
12. **i18n** — FR / LN / SW / EN (`LocaleProvider` + `AppLocalizations`).

## Leader / Ops

13. **Dispatch** — `POST /api/leader/incidents/:id/assign|close`, chat.
14. **Géofence secteur** — `POST /api/leader/sectors` + notify leaders au SOS.
15. **Ops dashboard** — admin-web `/ops` → `GET /api/ops/queue`.
16. **Rapports auto** — `GET /api/ops/reports/sector?format=csv|pdf`.

## Partenaires

17. **Webhooks** — `sos` / `incident` / `cancel` + HMAC `X-SafeAlert-Signature`.
18. **Portail** — admin-web `/portail-partenaire` (clé API).
19. **Premium stub** — `GET/POST /api/premium/*` ; activer `FEATURE_PREMIUM=true` (pas de Stripe).

## Tech

20. **SMS OTP** — doc `EXTERNAL_APIS.md` (SerdiPay → Twilio → AT). Pas de secrets inventés.
21. **FCM** — refresh token + upload `/auth/fcm-token` ; doc `FIREBASE_SETUP.md`.
22. **Offline queue** — SOS + reports + messages groupe (`pending_queue` v3).
23. **Backup contacts** — chiffrement client + `PUT/GET /api/backup/contacts`.

---

## Comment tester (rapide)

```bash
# Backend
cd backend && npm run migrate && npm start

# Flutter
cd frontend && flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api

# Admin
cd admin-web && npm run dev
```

| Scénario | Attendu |
|----------|---------|
| Annuaire → tap numéro | Composeur `tel:` |
| SOS → « Je suis en sécurité » | Push cercle confiance |
| SOS → « Fausse alerte » | SMS/push « Fausse alerte » |
| Trajet + ETA court + pas d’arrivée | Auto-SOS après ETA+5 min |
| Secouer téléphone (auth) | SOS discret |
| Ops admin (leader) | File + SLA |
| Partenaire webhook URL | Livraisons listées |

## Partial / reste

- **Widget home Android** — livré (`SosHomeWidgetProvider`, bouton SOS discret).
- **Capture photo/audio UI** — livré (picker photo/galerie + micro + consent sur signalement carte).
- **Suivi escorte carte live** — livré (`EscortMapScreen` + sockets `trip_ping` / `escort_trip`).
- **Stripe** — volontairement non branché ; grant admin/dev uniquement.
- **Digest push** — job 15 min serveur ; nécessite FCM configuré.
