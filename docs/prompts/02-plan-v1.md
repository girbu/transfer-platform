# Prompt 02 — plan de la V1 (spec v1.1, ADR-001) — à lancer en mode plan

Remplace le prompt 01, écrit pour la spec v1.0 (un seul système de comptes).

```
Lis AGENTS.md, docs/spec/001-virement-interne.md (v1.1), docs/adr/ADR-000-architecture-et-patterns.md
et docs/adr/ADR-001-comptes-routage-unicite.md. ADR-001 amende ADR-000 : en cas de contradiction, ADR-001 prévaut.

Objectif : livrer la V1 = trois services (payment-service, account-service, savings-service) et les
scénarios du périmètre V1 (spec §7 : S1, S3, S4, S6, S7, S8, S9, S10) verts, en respectant AGENTS.md.

Produis un plan, sans écrire de code ni créer de fichier :

1. Questions et ambiguïtés relevées dans la spec et les ADR, numérotées. N'invente aucune règle :
   si la spec ne dit rien, c'est une question pour moi.
2. Un découpage en 10 à 14 étapes d'environ 1 h, chacune testable et livrée en un seul commit.
   Pour chaque étape : objectif ; fichiers créés ou modifiés ; tests ajoutés (avec les scénarios S<n>
   concernés) ; critère de fin vérifiable par une commande.
3. L'étape 1 est le squelette : parent Maven multi-module avec wrapper (Java 25, Spring Boot 4.1.x — révisé le 16/11 : Spring Boot 3.5 n'a plus de support OSS depuis le 30/06/2026),
   Spotless, modules payment-service, account-service et savings-service vides (un module commun pour
   l'enveloppe des messages seulement si tu le justifies, avec son coût en couplage),
   docker-compose.yml (PostgreSQL 16 avec trois bases, Kafka KRaft à un broker), test ArchUnit des
   règles hexagonales, CI GitHub Actions (./mvnw verify).
4. Ordre que je propose ensuite, à contester si tu en vois un meilleur : account-service seul
   (domaine, persistance, débit conditionnel D12, contrainte d'unicité D13) → outbox et inbox → 
   payment-service (API, idempotence HTTP, machine à états) → saga nominale S1 → refus S3 →
   savings-service et compensation S4 → robustesse S6, S8, S10.
5. Les risques (ordre des messages, transactions base/Kafka, tests asynchrones, concurrence) et,
   pour chacun, le test qui le couvre.
6. Les dépendances Maven, avec une ligne de justification chacune. Rien d'autre sans me demander.
7. La liste des fichiers que le plan va créer, avec leur rôle en une ligne.

Attends ma validation explicite avant de commencer l'étape 1.
```
