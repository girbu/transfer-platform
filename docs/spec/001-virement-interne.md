# Spec 001 — Virement interne entre compte courant et livret

> Statut : **validée** — toute modification passe par l'humain (le hook `protect-files.sh` bloque l'agent).
> Version : 1.1 — 2026-11-10 — ajoute le livret d'épargne (`savings-service`), les virements dans les deux sens, la concurrence sur le solde et précise l'idempotence HTTP.

## 1. Objectif

Permettre à un client de virer un montant **entre son compte courant et son livret d'épargne, dans les deux sens**, **sans jamais créer ni perdre d'argent**, même si un service, la base ou Kafka tombe au milieu du traitement.

Les comptes courants et les livrets sont tenus par **deux services distincts**, chacun avec sa propre base : un virement modifie donc deux soldes qui ne peuvent pas être mis à jour dans une même transaction. La cohérence est **éventuelle** et garantie par une **saga** orchestrée par `payment-service`.

## 2. Périmètre V1 (au plus tard le 22/11)

| Dans le périmètre | Hors périmètre V1 (voir §9) |
|---|---|
| Virement EUR compte courant → livret et livret → compte courant | Virement courant → courant et livret → livret |
| Débit, crédit, compensation | Multi-devise, virements externes (SEPA) |
| Débits concurrents sur un même compte | Délai d'expiration de la saga, état `COMPENSATION_FAILED` |
| Idempotence HTTP et Kafka | Relevé de compte (CQRS), grand livre (event sourcing) |
| Publication fiable (outbox) | DLQ, observabilité, sécurité / authentification |
| | Contrôle de conformité par LLM |

## 3. Services

| Service | Responsabilité | Données propres |
|---|---|---|
| `payment-service` | Reçoit la demande, porte l'état du virement, **orchestre la saga** | `transfer`, `idempotency_key`, `outbox_message`, `inbox_message` |
| `account-service` | Tient les **comptes courants** : débit, crédit, compensation | `account`, `account_movement`, `outbox_message`, `inbox_message`, `processed_command`|
| `savings-service` | Tient les **livrets** : débit, crédit, compensation | `savings_account`, `savings_movement`, `outbox_message`, `inbox_message`, `processed_command`  |

Une instance PostgreSQL, **une base par service** (`payment_db`, `account_db`, `savings_db`). Aucun service ne lit la base d'un autre.

Types de compte : `CURRENT` (compte courant, `account-service`) et `SAVINGS` (livret, `savings-service`).

## 4. Règles métier

- **R1** Montant strictement positif, **2 décimales au plus** (au-delà : refus, jamais d'arrondi), devise `EUR` uniquement.
- **R2** Montant maximal par virement : **10 000,00 €**.
- **R3** Compte source ≠ compte destinataire, et de types différents (un `CURRENT` et un `SAVINGS`).
- **R4** Pas de découvert : un débit est refusé si `solde < montant`. La règle vaut aussi quand plusieurs virements débitent le même compte au même moment : **le solde n'est jamais négatif**.
- **R5** Un compte `BLOCKED` ou `CLOSED`, courant ou livret, ne peut être ni débité ni crédité.
- **R6** Chaque mouvement de solde est tracé (`account_movement`, `savings_movement` : type, montant, `transferId`, horodatage). Le solde est toujours égal à la somme des mouvements. Le solde initial est un mouvement de type `OPENING`.
- **R7** Un même `transferId` ne produit **jamais** plus d'un débit, d'un crédit ou d'une compensation (idempotence).
- **R8** Montants en `BigDecimal` (jamais `double`). L'arrondi `HALF_EVEN` est réservé aux calculs internes ; un montant reçu n'est jamais arrondi (R1).
- **R9** Plafond du livret : un crédit sur un livret est refusé si `solde + montant > plafond`. Le plafond est **paramétrable** ; valeur initiale **22 950,00 €**.
- **R10** Une **compensation est toujours acceptée** : R5 et R9 ne s'y appliquent pas, car elle restaure le solde d'avant le débit. Une compensation qui échoue pour une raison technique est réessayée jusqu'au succès.

## 5. Cycle de vie d'un virement

Le compte source est toujours débité **avant** que le compte destinataire soit crédité.

```
REQUESTED ──DebitSucceeded──▶ DEBITED ──CreditSucceeded──▶ COMPLETED
    │                            │
    └─DebitRejected──▶ REJECTED  └─CreditRejected──▶ COMPENSATING ──DebitCompensated──▶ COMPENSATED
```

- `REJECTED` : rien n'a bougé (solde insuffisant, compte source bloqué, clos ou inconnu).
- `COMPENSATING` : le compte source a été débité, le crédit a été refusé, le recrédit du compte source est en cours. Cet état se termine toujours (R10).
- `COMPENSATED` : le compte source a été débité puis recrédité ; son solde final est égal à son solde initial ; les deux mouvements restent tracés.
- États terminaux : `COMPLETED`, `REJECTED`, `COMPENSATED`. Un événement reçu sur un état terminal est ignoré (et journalisé).

## 6. Contrats

### 6.1 API HTTP (`payment-service`)

`POST /transfers` — en-tête **`Idempotency-Key` obligatoire** (UUID choisi par le client)

```json
{
  "source": { "type": "CURRENT", "id": "uuid" },
  "target": { "type": "SAVINGS", "id": "uuid" },
  "amount": "150.00",
  "currency": "EUR"
}
```

- Toute demande valide reçoit `202 Accepted` + `{ "transferId": "uuid", "status": "REQUESTED" }`. Son issue (`COMPLETED`, `REJECTED`, `COMPENSATED`) se consulte ensuite par `GET`.
- R1 à R3 violées, ou type de compte invalide → `400` au format `application/problem+json` ; rien n'est enregistré, la clé n'est pas mémorisée.
- Même `Idempotency-Key` + même demande, la première requête ayant déjà reçu sa réponse → **même réponse**, aucun nouveau virement.
- Même `Idempotency-Key` + même demande, la première requête étant **encore en cours de traitement** → `409 Conflict` (« requête en cours »).
- Même `Idempotency-Key` + demande différente → `409 Conflict`.
- « Même demande » = mêmes valeurs après normalisation (montant à 2 décimales, devise en majuscules, identifiants en minuscules), quels que soient la mise en forme du JSON et l'ordre des champs.
- Compte inconnu du service désigné par son type : compte source → virement `REJECTED` (motif `ACCOUNT_NOT_FOUND`) ; compte destinataire → virement `COMPENSATED`.

`GET /transfers/{id}` → `200` avec l'état courant, l'historique des transitions et le motif de refus éventuel ; ou `404`.

`account-service` expose `POST /accounts` (création d'un compte courant avec solde initial, pour les tests et la démo) et `GET /accounts/{id}`.
`savings-service` expose `POST /savings-accounts` (création d'un livret avec solde initial) et `GET /savings-accounts/{id}`.

### 6.2 Messages Kafka

Les messages sont produits par les services, jamais par le client.

| Topic | Producteur | Messages |
|---|---|---|
| `account.commands` | payment | `DebitAccount`, `CreditAccount`, `CompensateDebit` |
| `account.events` | account | `DebitSucceeded`, `DebitRejected`, `CreditSucceeded`, `CreditRejected`, `DebitCompensated` |
| `savings.commands` | payment | `DebitAccount`, `CreditAccount`, `CompensateDebit` |
| `savings.events` | savings | `DebitSucceeded`, `DebitRejected`, `CreditSucceeded`, `CreditRejected`, `DebitCompensated` |

- Clé de partition : `transferId` (ordre garanti pour un même virement à l'intérieur d'un topic).
- Enveloppe JSON commune : `messageId` (UUID, unique), `type`, `transferId`, `occurredAt` (ISO-8601 UTC), `payload`.
- Livraison **au moins une fois** : tout consommateur est idempotent sur `messageId` (table `inbox_message`).

## 7. Scénarios d'acceptation

Chaque scénario est un test d'intégration (Testcontainers : PostgreSQL + Kafka) qui passe au vert.

**Périmètre V1 (22/11) : S1, S3, S4, S6, S7, S8, S9, S10.** S2, S5, S11 et S12 sont reportés en V1.1. Notation : `C` = compte courant, `L` = livret ; plafond du livret = 22 950,00 €. « Mouvements » = mouvements liés au virement (hors `OPENING`).

| # | Étant donné | Quand | Alors |
|---|---|---|---|
| S1 | C = 500 €, L = 100 € | virement de 150 € de C vers L | `COMPLETED` ; C = 350 €, L = 250 € |
| S2 | L = 500 €, C = 100 € | virement de 150 € de L vers C | `COMPLETED` ; L = 350 €, C = 250 € |
| S3 | C = 100 € | virement de 150 € de C vers L | `REJECTED` ; C = 100 €, aucun mouvement |
| S4 | C = 500 €, L = 22 900 € | virement de 150 € de C vers L | `COMPENSATED` (R9) ; C = 500 € avec 2 mouvements (débit, compensation) ; L = 22 900 € |
| S5 | L = 500 €, C `CLOSED` | virement de 150 € de L vers C | `COMPENSATED` (R5) ; L = 500 € avec 2 mouvements |
| S6 | un `DebitAccount` déjà traité | le même message est relivré | un seul débit (R7) |
| S7 | une requête déjà acceptée | rejouée avec la même `Idempotency-Key` | même `transferId`, un seul virement |
| S8 | Kafka arrêté | `POST /transfers` | `202` ; le virement est en base et la commande dans l'outbox ; elle est publiée au redémarrage de Kafka et le virement se termine |
| S9 | — | montant = 0, ou 150,001 €, ou 10 000,01 €, ou source = destinataire, ou deux comptes de même type | `400`, rien en base |
| S10 | C = 500 € | deux virements **différents** de 400 € de C vers L, envoyés en même temps avec des clés différentes | les deux reçoivent `202` ; l'un est `COMPLETED`, l'autre `REJECTED` ; C = 100 € ; le solde de C est égal à la somme de ses mouvements (R4) |
| S11 | C = 500 €, livret destinataire inexistant | virement de 150 € de C vers ce livret | `COMPENSATED` ; C = 500 € avec 2 mouvements |
| S12 | C débité de 150 € par le virement T, puis passé `BLOCKED` | `account-service` reçoit `CompensateDebit` pour T (test d'intégration du seul `account-service`) | compensation acceptée (R10) ; C recrédité de 150 € ; `DebitCompensated` publié |

## 8. Exigences non fonctionnelles

- Java 25, Spring Boot 4.1.x, Maven multi-module avec wrapper.
- Architecture hexagonale vérifiée par **ArchUnit** : le package `domain` ne dépend ni de Spring, ni de Kafka, ni de JPA.
- `docker compose up -d` démarre PostgreSQL (trois bases) et Kafka (KRaft, un seul broker) ; `./mvnw verify` passe sans autre prérequis que Docker.
- Migrations de schéma par Flyway.
- Plafond du livret fourni par la configuration (R9).
- CI GitHub Actions : `./mvnw verify` à chaque push.

## 9. Évolutions prévues (hors V1)

1. CQRS : relevé consolidé compte courant + livret (service `statement`), alimenté par les événements des deux services.
2. Event sourcing du grand livre (`ledger`).
3. Délai d'expiration de la saga, état `COMPENSATION_FAILED` et alerte.
4. Retry et DLQ ; schémas Avro et Schema Registry.
5. Observabilité : OpenTelemetry (traces de bout en bout d'un virement).
6. Service `compliance` : classification du motif libre du virement par un LLM, avec revue humaine et repli déterministe.
7. Serveur MCP exposant la plateforme à un agent (consultation des virements).
