# AGENTS.md — règles pour les agents de code

Plateforme de virement interne en microservices event-driven (Java 21, Spring Boot 3.5, Kafka, PostgreSQL).
Sources de vérité, à lire **avant toute tâche** :

1. `docs/spec/001-virement-interne.md` — le besoin (validé, non modifiable par l'agent)
2. `docs/adr/` — les décisions d'architecture
3. ce fichier

## Méthode de travail (obligatoire)

1. **Plan d'abord.** Toute tâche commence en mode plan : étapes numérotées, fichiers touchés, tests prévus, questions ouvertes. Aucun code avant validation explicite de l'humain.
2. **Petites étapes.** Une étape = un objectif testable ≈ 1 h de travail = **un commit**.
3. **Test d'abord pour le domaine** : écrire le test qui échoue, puis le code.
4. **Rendre la main tests verts.** Le hook `Stop` lance les tests unitaires ; s'ils échouent, corrige avant de conclure.
5. **Journal.** À la fin de chaque étape, propose une entrée pour `docs/journal-agent.md` (l'humain la valide).
6. **En cas de doute sur une règle métier : demande.** N'invente jamais une règle absente de la spec.

## Commandes

| Action | Commande |
|---|---|
| Infrastructure locale | `docker compose up -d` |
| Build complet + tests d'intégration | `./mvnw verify` |
| Tests unitaires d'un module | `./mvnw -pl payment-service test` |
| Formatage | `./mvnw spotless:apply` (lancé automatiquement après chaque modification de fichier Java) |

## Architecture (vérifiée par ArchUnit)

```
<service>/src/main/java/com/example/<service>/
├── domain/            # Java pur : entités, value objects, règles, événements du domaine
├── application/       # cas d'usage + ports (interfaces) in/out
└── adapter/
    ├── in/web|kafka   # contrôleurs REST, consommateurs Kafka
    └── out/persistence|kafka   # JPA, outbox publisher, producteurs
```

- `domain` ne dépend de **rien** d'autre que le JDK (ni Spring, ni JPA, ni Kafka, ni Jackson).
- `application` dépend de `domain` uniquement ; les adaptateurs dépendent des ports, jamais l'inverse.
- Les entités JPA vivent dans `adapter/out/persistence` et sont mappées vers le domaine.
- Aucun service n'accède à la base d'un autre service.

## Conventions de code

- Java 21 : `record` pour les value objects et messages, `sealed` pour les hiérarchies d'événements, pattern matching `switch`.
- Montants : `BigDecimal` + value object `Money`, jamais `double`.
- Injection par constructeur uniquement. Pas de Lombok.
- Pas de `@Transactional` dans le domaine ; la transaction est posée dans `application` ou l'adaptateur.
- Logs : SLF4J, avec `transferId` en contexte (MDC). Jamais de solde ni de numéro de compte complet en log `INFO`.
- Erreurs HTTP au format `application/problem+json`.

## Tests

- Unitaires (`*Test`) : domaine et cas d'usage, sans Spring, sans mock du domaine.
- Intégration (`*IT`, failsafe) : Testcontainers (PostgreSQL + Kafka), Awaitility pour la convergence asynchrone.
- Chaque scénario S1 à S7 de la spec a son test d'intégration, nommé `S1_...`.
- Interdits : `@Disabled`, suppression ou affaiblissement d'une assertion pour faire passer un test, `Thread.sleep` dans les tests.

## Git

- Conventional Commits : `feat(payment): ...`, `test(account): ...`, `docs: ...`, `chore: ...`.
- Un commit par étape du plan validé ; message qui cite l'étape (`step 3/8`).
- Jamais de `git push`, de `--amend` sur un commit existant, de `reset --hard` ni de `--no-verify` (bloqués par hook).

## Ce que l'agent ne fait jamais

- Modifier `docs/spec/`, `.claude/` ou `scripts/hooks/` (bloqué par hook) : il propose le changement en texte.
- Ajouter une dépendance Maven sans l'avoir demandé et justifié.
- Lire ou écrire un fichier `.env`, une clé ou un secret.
- Introduire un pattern ou une technologie absents des ADR sans proposer d'abord un nouvel ADR.
