# ADR-000 — Architecture et patterns de la plateforme de virement

- Statut : **accepté** — 2026-11-10 — contexte et D3 amendés par [ADR-001](ADR-001-comptes-routage-unicite.md)
- Décideur : GIRBU Ion
- Contexte métier : [spec 001](../spec/001-virement-interne.md)

## Contexte

Un virement modifie deux soldes tenus par deux services distincts, chacun avec sa base. Une transaction distribuée (2PC / XA) est exclue : couplage fort, mauvaise tenue en charge, mal supportée par Kafka. Il faut donc accepter une **cohérence éventuelle** tout en garantissant qu'aucun euro n'est créé ni perdu (spec, R6 et R7).

Ce dépôt sert aussi de socle réutilisable : chaque pattern doit être **justifié par une contrainte du domaine**, pas ajouté par principe.

## Décisions

| # | Décision | Contrainte qui la justifie | Coût accepté | Alternative écartée |
|---|---|---|---|---|
| D1 | **Architecture hexagonale** dans chaque service (domain / application / adapter) | Domaine testable sans infrastructure ; LLM, Kafka et base remplaçables | Plus de classes et de mapping | Couches Spring classiques : le domaine finit couplé à JPA |
| D2 | **Une base par service** (une instance PostgreSQL) | Autonomie des services, pas de couplage par la base | Pas de jointure ni de transaction entre services | Base partagée : couplage caché |
| D3 | **Saga orchestrée** par `payment-service` | Débit et crédit sur deux services ; un échec du crédit doit déclencher une compensation | Orchestrateur = point central à faire évoluer avec soin | Chorégraphie : flux implicite, difficile à suivre et à tester pour un virement |
| D4 | **Transactional outbox** (table `outbox_message` + publisher par polling, `FOR UPDATE SKIP LOCKED`) | Écriture en base et publication Kafka atomiques (spec S6) | Latence de polling, table à purger | Publier dans la transaction : perte possible ; Debezium (CDC) : infrastructure trop lourde pour la V1, à réévaluer |
| D5 | **Consommateur idempotent** (table `inbox_message`, clé `messageId`) | Kafka livre au moins une fois ; jamais deux débits (R7, S4) | Une écriture de plus par message | Exactly-once Kafka : ne couvre pas les effets en base |
| D6 | **Idempotence HTTP** (`Idempotency-Key` stockée avec le hash du corps) | Rejeu client ou réseau (S5) | Table et purge à gérer | Aucune : doublons de virement |
| D7 | **Kafka en KRaft, un seul broker, messages JSON** en V1 | Démarrage simple en local et en CI | Pas de contrat de schéma fort | Avro + Schema Registry : prévu à l'évolution 3 |
| D8 | **Clé de partition = `transferId`** | Ordre des messages d'un même virement | Répartition dépendante des identifiants | Clé aléatoire : ordre non garanti |

## Reportées volontairement (pas de besoin en V1)

- **CQRS** : aucun besoin de lecture différent du modèle d'écriture tant qu'il n'y a pas de relevé de compte (évolution 1).
- **Event sourcing** : justifié pour le grand livre, pas pour l'état d'un virement (évolution 2).
- **DLQ / retry** : à ajouter quand un consommateur pourra recevoir un message durablement invalide (évolution 3).

## Conséquences

- Un virement est asynchrone : l'API répond `202` et le client consulte l'état.
- Les tests d'intégration doivent attendre la convergence (Awaitility), pas un état immédiat.
- Toute nouvelle décision structurante fait l'objet d'un ADR numéroté (`ADR-00X`), rédigé avant le code.
