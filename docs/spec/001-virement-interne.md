# Spec 001 — Virement interne entre deux comptes

> Statut : **validée** — toute modification passe par l'humain (le hook `protect-files.sh` bloque l'agent).
> Version : 1.1 — 2026-11-10

## 1. Objectif

Permettre à un client de virer un montant d'un compte source vers un compte destinataire, tous deux tenus par la plateforme, **sans jamais créer ni perdre d'argent**, même si un service, la base ou Kafka tombe au milieu du traitement.

Le virement traverse deux services qui ne partagent pas de base de données : la cohérence est donc **éventuelle** et garantie par une saga.

	Deux systèmes de comptes, le compte courant et le livret, tenus par deux services distincts. C’est ce qui justifie la saga

## 2. Périmètre V1 (au plus tard le 16/11)

| Dans le périmètre | Hors périmètre V1 (voir §9) |
|---|---|
| Virement EUR entre deux comptes internes | Multi-devise, virements externes (SEPA) |
| Débit, crédit, compensation | Relevé de compte (CQRS), grand livre (event sourcing) |
| Idempotence HTTP et Kafka | DLQ, observabilité, sécurité / authentification |
| Publication fiable (outbox) | Contrôle de conformité par LLM |

## 3. Services

| Service | Responsabilité | Données propres |
|---|---|---|
| `payment-service` | Reçoit la demande, porte l'état du virement, **orchestre la saga** | `transfer`, `outbox_message`, `inbox_message` |
| `account-service` | Tient les soldes, exécute débit / crédit / compensation | `account`, `account_movement`, `outbox_message`, `inbox_message` |

Une instance PostgreSQL, **une base par service** (`payment_db`, `account_db`). Aucun service ne lit la base de l'autre.

## 4. Règles métier

- **R1** Montant strictement positif, 2 décimales maximum, devise `EUR` uniquement.
- **R2** Montant maximal par virement : **10 000,00 €**.
- **R3** Compte source ≠ compte destinataire.
- **R4** Pas de découvert : le débit est refusé si `solde < montant`.
- **R5** Un compte `BLOCKED` ne peut être ni débité ni crédité ; un compte `CLOSED` non plus.
- **R6** Chaque mouvement de solde est tracé dans `account_movement` (type, montant, `transferId`, horodatage). Le solde est toujours égal à la somme des mouvements.
- **R7** Un même `transferId` ne produit **jamais** plus d'un débit, d'un crédit ou d'une compensation (idempotence).
- **R8** Montants en `BigDecimal` (jamais `double`), arrondi `HALF_EVEN`.

## 5. Cycle de vie d'un virement

```
REQUESTED ──DebitSucceeded──▶ DEBITED ──CreditSucceeded──▶ COMPLETED
    │                            │
    └─DebitRejected──▶ REJECTED  └─CreditRejected──▶ COMPENSATING ──DebitCompensated──▶ COMPENSATED
```

- `REJECTED` : rien n'a bougé (ex. solde insuffisant).
- `COMPENSATED` : le compte source a été débité puis recrédité ; solde final identique au solde initial.
- États terminaux : `COMPLETED`, `REJECTED`, `COMPENSATED`. Un événement reçu sur un état terminal est ignoré (et journalisé).

## 6. Contrats

### 6.1 API HTTP (`payment-service`)

`POST /transfers` — en-tête **`Idempotency-Key` obligatoire** (UUID)

```json
{ "sourceAccountId": "uuid", "targetAccountId": "uuid", "amount": "150.00", "currency": "EUR" }
```

- `202 Accepted` + `{ "transferId": "uuid", "status": "REQUESTED" }`
- Même `Idempotency-Key` + même corps → même réponse, aucun nouveau virement.
- Même `Idempotency-Key` + corps différent → `409 Conflict`.
- Règles R1 à R3 violées → `400` au format `application/problem+json`.

`GET /transfers/{id}` → `200` avec l'état courant et l'historique des transitions, ou `404`.

`account-service` expose `POST /accounts` (création avec solde initial, pour les tests et la démo) et `GET /accounts/{id}`.

### 6.2 Messages Kafka

| Topic | Producteur | Messages |
|---|---|---|
| `account.commands` | payment | `DebitAccount`, `CreditAccount`, `CompensateDebit` |
| `account.events` | account | `DebitSucceeded`, `DebitRejected`, `CreditSucceeded`, `CreditRejected`, `DebitCompensated` |

- Clé de partition : `transferId` (ordre garanti pour un même virement).
- Enveloppe JSON commune : `messageId` (UUID, unique), `type`, `transferId`, `occurredAt` (ISO-8601 UTC), `payload`.
- Livraison **au moins une fois** : tout consommateur est idempotent sur `messageId` (table `inbox_message`).

## 7. Scénarios d'acceptation

Chaque scénario est un test d'intégration (Testcontainers : PostgreSQL + Kafka) qui passe au vert.

| # | Étant donné | Quand | Alors |
|---|---|---|---|
| S1 | A = 500 €, B = 100 € | virement de 150 € de A vers B | `COMPLETED` ; A = 350 €, B = 250 € |
| S2 | A = 100 € | virement de 150 € | `REJECTED` ; A = 100 €, aucun mouvement |
| S3 | A = 500 €, B `CLOSED` | virement de 150 € | `COMPENSATED` ; A = 500 €, 2 mouvements sur A (débit, compensation) |
| S4 | un `DebitAccount` déjà traité | le même message est relivré | un seul débit sur A |
| S5 | une requête déjà acceptée | rejouée avec la même `Idempotency-Key` | même `transferId`, un seul virement |
| S6 | Kafka arrêté | `POST /transfers` | `202` ; le virement est en base et la commande dans l'outbox ; elle est publiée au redémarrage de Kafka |
| S7 | montant = 0, ou A = B, ou 10 000,01 € | `POST /transfers` | `400`, rien en base |

## 8. Exigences non fonctionnelles

- Java 21, Spring Boot 3.5.x, Maven multi-module avec wrapper.
- Architecture hexagonale vérifiée par **ArchUnit** : le package `domain` ne dépend ni de Spring, ni de Kafka, ni de JPA.
- `docker compose up -d` démarre PostgreSQL et Kafka (KRaft, un seul broker) ; `./mvnw verify` passe sans autre prérequis que Docker.
- Migrations de schéma par Flyway.
- CI GitHub Actions : `./mvnw verify` à chaque push.

## 9. Évolutions prévues (hors V1)

1. CQRS : service `statement` (relevé de compte) alimenté par les événements.
2. Event sourcing du grand livre (`ledger`).
3. Retry et DLQ ; schémas Avro et Schema Registry.
4. Observabilité : OpenTelemetry (traces de bout en bout d'un virement).
5. Service `compliance` : classification du motif libre du virement par un LLM, avec revue humaine et repli déterministe.
6. Serveur MCP exposant la plateforme à un agent (consultation des virements).
