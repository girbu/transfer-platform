# transfer-platform

Plateforme de virement interne (**compte courant ↔ livret d'épargne**) en microservices event-driven — **construite avec un agent de code (Claude Code), encadré par un harness explicite et relu par un humain.**

> **Statut au 16/11/2026 : en construction.** Spec, décisions d'architecture et harness en place ; squelette livré (3 services, infrastructure locale, CI). V1 (saga, outbox, inbox, idempotence, concurrence, 8 scénarios d'acceptation) visée le **22/11/2026**. Avancement : [plan de l'agent](docs/prompts/02-plan-v1.md) · [journal de l'agent](docs/journal-agent.md).

## Ce que montre ce dépôt

1. **Une méthode de travail avec un agent**, pas seulement du code : spec validée → décisions d'architecture → plan de l'agent relu et contesté → étapes d'environ 1 h, testées → relecture humaine → commit.
2. **Un humain qui garde la main** : ce que l'agent peut faire, ce qui l'en empêche (et ce qui ne l'en empêche pas), ce qui a été refusé ou corrigé.
3. **Des patterns distribués justifiés par le métier** : chaque pattern répond à une contrainte du virement ([ADR-000](docs/adr/ADR-000-architecture-et-patterns.md), [ADR-001](docs/adr/ADR-001-comptes-routage-unicite.md)).

## Quelques moments du projet

- **Une contradiction dans le kit généré au départ.** La spec plaçait tous les comptes dans un seul service, ce qui rendait la saga inutile (une transaction locale suffisait) ; l'ADR affirmait le contraire. Corrigé par un vrai second système de comptes, le livret, où la compensation a une cause métier (plafond) → [ADR-001](docs/adr/ADR-001-comptes-routage-unicite.md).
- **Consigne ou contrainte ?** Premier test : l'agent refuse de modifier la spec de lui-même (consigne d'`AGENTS.md`) et *affirme* que le hook l'aurait bloqué, sans l'avoir déclenché. Second test, en forçant : le hook bloque réellement l'écriture → [journal](docs/journal-agent.md).
- **L'agent contredit l'humain, à raison.** Dans son plan, il conteste l'ordre des étapes proposé (le scénario nominal crédite un livret, donc le service du livret doit exister avant), et repère un trou d'idempotence sur les commandes refusées → décision D17.
- **Version vérifiée avant la première ligne de code.** Spring Boot 3.5 n'est plus maintenu depuis le 30/06/2026 : passage à Java 25 et Spring Boot 4.1. L'agent a vérifié la compatibilité des outils par des tests jetables plutôt que de l'affirmer.

## Le harness de l'agent

| Élément | Rôle |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Règles : méthode, architecture, conventions, interdits |
| [`docs/spec/`](docs/spec/) | Le besoin, validé par l'humain ; l'agent ne peut pas le modifier |
| [`docs/adr/`](docs/adr/) | Les décisions d'architecture et leurs alternatives écartées ; un ADR n'est pas réécrit, il est amendé |
| [`.claude/settings.json`](.claude/settings.json) | Permissions : `git push` interdit à l'agent ; `git commit` soumis à la validation humaine |
| [`scripts/hooks/`](scripts/hooks/) | Garde-fous exécutés par Claude Code : secrets et spec protégés, commandes dangereuses bloquées, formatage après chaque modification, tests unitaires avant de rendre la main |
| [`docs/prompts/`](docs/prompts/) | Les prompts utilisés |
| [`docs/journal-agent.md`](docs/journal-agent.md) | Ce qui a été délégué, refusé ou corrigé |

### Limites connues du harness

- Les hooks filtrent par motif. Une écriture via le shell (`sed -i`) sur la spec n'est pas interceptée par `protect-files.sh` : la barrière est alors la validation humaine que Claude Code demande pour toute commande non autorisée d'office.
- `guard-bash.sh` se contourne par une variation de syntaxe ; pour `git push`, la règle `deny` des permissions reste la barrière principale.
- Le hook de fin ne lance que les tests unitaires ; les tests d'intégration tournent en CI.
- Non traité ici : la confidentialité du code envoyé au modèle (hébergement, rétention), sujet à part entière en contexte bancaire.

## Architecture (V1)

```
                 ┌──account.commands──▶ account-service   (comptes courants)
client ──HTTP──▶ payment-service ◀──account.events───┘
                 (orchestrateur de la saga)
                 └──savings.commands──▶ savings-service   (livrets, plafond)
                                ◀──savings.events───┘
chaque service : sa propre base PostgreSQL + outbox + inbox
```

**Stack :** Java 25, Spring Boot 4.1, Kafka 4.2 (KRaft), PostgreSQL 16, Flyway, Testcontainers, ArchUnit, GitHub Actions.

## Feuille de route

- **22/11/2026 — V1** : saga compte courant ↔ livret, outbox, inbox, idempotence HTTP et Kafka, débits concurrents.
- **13/12/2026 — V2** : relevé consolidé (CQRS), grand livre en event sourcing, DLQ, OpenTelemetry.
- **10/01/2027 — V3** : contrôle de conformité par LLM (avec repli déterministe), serveur MCP.

## Démarrer

Prérequis : JDK 25, Docker. Maven est fourni par le wrapper (`./mvnw`).

```bash
./mvnw verify              # build, tests unitaires et d'intégration (Testcontainers), contrôle du formatage
./mvnw spotless:apply      # formate le code Java
docker compose up -d       # infrastructure locale : PostgreSQL 16 (payment_db, account_db, savings_db) et Kafka (KRaft)
docker compose down -v     # arrête et supprime les données locales
```

`./mvnw verify` ne dépend pas de `docker compose` : les tests démarrent leurs propres conteneurs.
