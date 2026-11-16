# transfer-platform

Plateforme de virement interne en microservices event-driven — **construite avec un agent de code (Claude Code), encadré par un harness explicite.**

> Statut : en construction (V1 visée : saga de virement, outbox, consommateurs idempotents).

## Ce que montre ce dépôt

1. **Une méthode de travail avec un agent**, pas seulement du code :
   spec écrite et validée avant la première ligne de code → plan validé → petites étapes testées → relecture humaine → commit.
2. **Des patterns d'architecture justifiés par le métier** : chaque pattern répond à une contrainte du virement (voir [ADR-000](docs/adr/ADR-000-architecture-et-patterns.md)).

## Le harness de l'agent

| Élément | Rôle |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Règles : méthode, architecture, conventions, interdits |
| [`docs/spec/`](docs/spec/) | Le besoin, validé par l'humain ; l'agent ne peut pas le modifier |
| [`docs/adr/`](docs/adr/) | Les décisions d'architecture et leurs alternatives écartées |
| [`.claude/settings.json`](.claude/settings.json) + [`scripts/hooks/`](scripts/hooks/) | Garde-fous automatiques : secrets et spec protégés, commandes dangereuses bloquées, formatage après chaque modification, tests unitaires obligatoires avant de rendre la main |
| [`docs/prompts/`](docs/prompts/) | Les prompts utilisés |
| [`docs/journal-agent.md`](docs/journal-agent.md) | Ce qui a été délégué, refusé ou corrigé |

## Architecture (V1)

```
client ──HTTP──▶ payment-service ──account.commands──▶ account-service
                 (orchestrateur        ◀──account.events──  (soldes, mouvements)
                  de la saga)
        chaque service : PostgreSQL dédiée + outbox + inbox
```

## Démarrer

Prérequis : JDK 25, Docker. Maven est fourni par le wrapper (`./mvnw`).

```bash
./mvnw verify              # build, tests unitaires et d'intégration (Testcontainers), contrôle du formatage
./mvnw spotless:apply      # formate le code Java
docker compose up -d       # infrastructure locale : PostgreSQL 16 (payment_db, account_db, savings_db) et Kafka (KRaft)
docker compose down -v     # arrête et supprime les données locales
```

`./mvnw verify` ne dépend pas de `docker compose` : les tests démarrent leurs propres conteneurs.
