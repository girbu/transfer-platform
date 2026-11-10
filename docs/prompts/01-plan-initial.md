# Prompt 01 — plan initial (à lancer en mode plan : Shift+Tab jusqu'à « plan mode »)

```
Lis AGENTS.md, docs/spec/001-virement-interne.md et docs/adr/ADR-000-architecture-et-patterns.md.

Objectif : livrer la V1 décrite dans la spec (scénarios S1 à S7 verts) en respectant AGENTS.md.

Produis un plan, sans écrire de code :
1. Les questions ou ambiguïtés que tu relèves dans la spec et l'ADR (je réponds avant tout code).
2. Un découpage en 8 à 12 étapes, chacune d'environ 1 h, testable et livrée en un seul commit.
   Pour chaque étape : objectif, fichiers créés ou modifiés, tests ajoutés, critère de fin.
3. L'étape 1 doit être le squelette : parent Maven multi-module avec wrapper (Java 21,
   Spring Boot 3.5.x), plugin Spotless, modules payment-service et account-service vides,
   docker-compose.yml (PostgreSQL 16 + Kafka en KRaft, un seul broker), test ArchUnit des règles
   hexagonales, CI GitHub Actions (./mvnw verify), .gitignore.
4. Les risques que tu vois (ordre des messages, transactions, tests asynchrones) et comment le plan les couvre.
5. Les dépendances Maven que tu comptes ajouter, avec une ligne de justification chacune.

Attends ma validation explicite avant de commencer l'étape 1.
```

# Prompt type pour chaque étape suivante

```
Étape N du plan validé : <objectif>.
Commence par le ou les tests qui doivent échouer, montre-les-moi, puis implémente.
Termine par : tests verts, résumé des fichiers modifiés, proposition de message de commit
et proposition d'entrée pour docs/journal-agent.md. Ne commite pas avant mon accord.
```
