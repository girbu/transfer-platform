package com.example.savings;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

/** Règles hexagonales d'AGENTS.md et de la spec §8, vérifiées sur le code de production. */
@AnalyzeClasses(
    packages = "com.example.savings",
    importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {

  @ArchTest
  static final ArchRule domain_depends_only_on_the_jdk =
      classes()
          .that()
          .resideInAPackage("..domain..")
          .should()
          .onlyDependOnClassesThat()
          .resideInAnyPackage("java..", "..domain..")
          .because("le domaine est du Java pur : ni Spring, ni JPA, ni Kafka, ni Jackson");

  @ArchTest
  static final ArchRule application_depends_only_on_domain =
      classes()
          .that()
          .resideInAPackage("..application..")
          .should()
          .onlyDependOnClassesThat()
          .resideInAnyPackage(
              "java..",
              "..domain..",
              "..application..",
              "org.slf4j..",
              "org.springframework.transaction.annotation..")
          .because("application dépend du domaine ; seuls les logs et @Transactional sont tolérés");

  @ArchTest
  static final ArchRule inbound_adapters_do_not_use_outbound_adapters =
      noClasses()
          .that()
          .resideInAPackage("..adapter.in..")
          .should()
          .dependOnClassesThat()
          .resideInAPackage("..adapter.out..")
          .because("les adaptateurs passent par les ports");

  @ArchTest
  static final ArchRule outbound_adapters_do_not_use_inbound_adapters =
      noClasses()
          .that()
          .resideInAPackage("..adapter.out..")
          .should()
          .dependOnClassesThat()
          .resideInAPackage("..adapter.in..")
          .because("les adaptateurs passent par les ports");

  @ArchTest
  static final ArchRule jpa_entities_live_in_persistence_adapter =
      classes()
          .that()
          .areAnnotatedWith("jakarta.persistence.Entity")
          .should()
          .resideInAPackage("..adapter.out.persistence..")
          .because("les entités JPA sont mappées vers le domaine, jamais exposées");
}
