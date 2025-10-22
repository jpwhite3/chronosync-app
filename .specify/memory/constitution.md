<!--
Sync Impact Report:
- Version change: none → 1.0.0 (initial constitution)
- Added principles: I. Specification-Driven Development, II. Template-Driven Consistency, III. Progressive Enhancement, IV. Quality Gates, V. Tool Integration
- Added sections: Development Standards, Quality Assurance
- Templates requiring updates: ✅ plan-template.md, ✅ spec-template.md, ✅ tasks-template.md
- Follow-up TODOs: none
-->

# Cronos App Constitution

## Core Principles

### I. Specification-Driven Development
Every feature MUST begin with a complete specification before implementation. Specifications must define user scenarios, functional requirements, success criteria, and acceptance tests. Implementation without approved specification is prohibited. This ensures alignment between stakeholders and prevents scope creep during development.

### II. Template-Driven Consistency
All project artifacts MUST follow standardized templates for specifications, plans, tasks, and checklists. Templates ensure consistency across features and enable automation. Deviation from templates requires explicit justification and constitutional amendment. This principle maintains quality and enables tool integration.

### III. Progressive Enhancement (NON-NEGOTIABLE)
Features MUST be developed in priority order with independent testing at each increment. Each user story must be independently implementable and deliverable. This enables early validation, reduces risk, and allows for iterative feedback incorporation.

### IV. Quality Gates
All features MUST pass constitutional compliance checks before proceeding to the next phase. Quality gates include specification completeness, plan validation, task coverage, and implementation verification. Gate violations MUST be resolved or explicitly justified before advancement.

### V. Tool Integration
All development processes MUST support both interactive and automated execution. Commands must provide JSON output for automation and human-readable output for manual use. This enables CI/CD integration and maintains developer experience flexibility.

## Development Standards

Development MUST follow semantic versioning for all artifacts. Breaking changes require MAJOR version increments. New capabilities require MINOR version increments. Bug fixes and clarifications require PATCH version increments. All version changes MUST be documented with rationale.

File organization MUST follow the prescribed directory structure with `.specify/` for templates and scripts, `specs/` for feature documentation, and source code at repository root. Absolute file paths MUST be used in all automation to ensure reliability across environments.

## CI/CD Standards

- All features should be developed on a new branch off of `main`, and use the following format: feature/[name-of-feature]
- Tasks should be completed within a single commit, and pushed to the feature branch with a descriptive commit message.

## Quality Assurance

Code reviews MUST verify constitutional compliance before merge. All pull requests MUST include constitutional checklist validation. Quality metrics MUST be measured and reported for each feature delivery. Performance against success criteria MUST be validated post-deployment.

## Governance

This constitution supersedes all other development practices and guidelines. Amendments require documentation of impact analysis, approval by project maintainers, and migration plan for existing artifacts. Constitutional violations MUST be addressed immediately upon discovery.

All development tools and commands MUST verify compliance with these principles. Complexity introductions MUST be justified against constitutional principles. Teams MUST use agent-specific guidance files for runtime development assistance while maintaining constitutional compliance.

**Version**: 1.0.0 | **Ratified**: 2025-10-22 | **Last Amended**: 2025-10-22
