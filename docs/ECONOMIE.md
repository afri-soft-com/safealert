# SafeAlert — Modèle économique (MVP)

Document de référence pour la monétisation B2C (Premium) et B2B (API partenaires). Devise d’affichage : **USD** (équivalent indicatif en **CDF** pour la RDC).

## Coûts & seuil de rentabilité

| Poste | Ordre de grandeur |
|-------|-------------------|
| Hébergement / ops (API, DB, admin) | ~77 USD / mois |
| Premium citoyen (cible) | **2 USD / mois** (~5 500 CDF) |
| Partenaire API « Pro » | **100 USD / mois** |

**Seuil simple** : ~40 abonnés Premium **ou** 1 partenaire Pro couvrent le burn mensuel.

## Offre citoyenne (B2C)

### Gratuit (Free)

Toujours disponible sans carte bancaire :

- SOS, carte, groupes, check-in, annuaire, mode discret
- **5** contacts de confiance
- **3** trajets sécurisés / semaine (ETA max **2 h**)
- Historique des **30** dernières alertes
- File ops SOS **standard**

### Premium — 2 USD / mois (~5 500 CDF)

Ou **20 USD / an** (~55 000 CDF, ~2 mois offerts).

Débloqué via `users.premium_until` (après paiement, grant admin, ou activation test) :

| Avantage | Détail |
|----------|--------|
| Trajets illimités | Plus de plafond hebdomadaire |
| ETA long | Jusqu’à **12 h** de suivi |
| Contacts élargis | Jusqu’à **25** contacts de confiance |
| Historique étendu | **100** dernières alertes |
| Priorité SOS | Flag `priority_boost` → remonte dans la file ops |

Pas de publicité dans l’app aujourd’hui (pas de bénéfice « sans pubs » à vendre).

### Activation technique (MVP)

| Mode | Condition | Comportement |
|------|-----------|--------------|
| Flag off | `FEATURE_PREMIUM` absent / false | Limites Free **non** appliquées (comportement historique) |
| Flag on | `FEATURE_PREMIUM=true` | Entitlements Free / Premium actifs |
| Test | `FEATURE_PREMIUM_TEST_PURCHASE=true` **ou** `ALLOW_DEV_OTP=true` **ou** `NODE_ENV≠production` | Bouton « Activer Premium (test) » → `POST /api/premium/grant` |
| Stripe | `STRIPE_SECRET_KEY` + `STRIPE_PRICE_ID_PREMIUM` | Stub Checkout (`POST /api/premium/checkout`) — **pas de secrets fictifs** |
| Admin | Rôle `platform_admin` | Accorder / révoquer Premium (console Utilisateurs) |

Stripe n’est **pas** requis pour le MVP. Sans clés Stripe, l’API renvoie `checkout_available: false` et l’app propose l’activation test (si autorisée) ou un message « paiement bientôt ».

## Offre partenaires (B2B)

Clés `partner_api_keys` + `rate_limit` (fenêtre **15 minutes**, pas par minute).

| Plan | `rate_limit` (req / 15 min) | Prix indicatif |
|------|-----------------------------|----------------|
| **Essai** | ≤ 500 | 0 USD (pilote) |
| **Standard** | ≤ 1 000 | **50 USD / mois** |
| **Pro** | ≤ 5 000 | **100 USD / mois** |
| **Entreprise** | > 5 000 | Sur devis |

Inclus selon plan : webhooks SOS / incidents, portail `/portail-partenaire` (limites + livraisons). Facturation hors app (contrat / facture) — pas de Stripe B2B dans ce MVP.

## Variables d’environnement

```bash
FEATURE_PREMIUM=true
# FEATURE_PREMIUM_TEST_PURCHASE=true   # testers (prod) sans Stripe
# STRIPE_SECRET_KEY=                   # réel uniquement — jamais de placeholder
# STRIPE_PRICE_ID_PREMIUM=
# STRIPE_WEBHOOK_SECRET=
# STRIPE_SUCCESS_URL=https://…
# STRIPE_CANCEL_URL=https://…
```

## Roadmap paiement

1. MVP actuel : entitlements + grant admin / test + stub Checkout
2. Stripe Checkout réel (Mobile Money / carte selon dispo)
3. Reçus + `stripe_customer_id` sur `users`
4. Facturation partenaires (facture mensuelle / portail)

## Références code

- Entitlements : `backend/src/services/premiumEntitlements.js`
- API : `GET/POST /api/premium/*`
- Flag : `FEATURE_PREMIUM` dans `docs/FEATURES.md`
- Manuel utilisateur : section Premium dans `docs/MANUEL_UTILISATEUR.md`
