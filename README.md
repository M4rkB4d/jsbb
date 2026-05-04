# jsbb — Java Spring Boot Bank CLI

Scaffolds Spring Boot 4.0.5 + Java 21 backend services for EastWest Bank, following the **compliance-event-logger** pattern (AFASA Engine architecture).

## What it generates

- Spring Boot 4.0.5 + Java 21 with virtual threads enabled
- Flyway migrations wired with the v2.3.8 AFASA-pattern schema
- Spring Security stubs (OAuth2 / JWT)
- ShedLock for distributed `@Scheduled` job coordination
- Resilience4j for outbound HTTP retry / circuit-breaker / timeout
- Micrometer + Actuator endpoints
- Structured JSON logging (Logback)
- 4 environment-specific `application-{env}.yml` files (dev / uat / prod / local)
- OpenAPI / SpringDoc Swagger UI
- Maven wrapper + standard project structure

## Install

```bash
cd C:/Projects/jsbb
npm install
npm link
```

`npm link` exposes `jsbb` globally on your PATH.

## Use

```bash
mkdir my-new-service
cd my-new-service
jsbb init
```

You'll be prompted for:

| Prompt | Default | Notes |
|---|---|---|
| `groupId` | `com.eastwest` | Reverse-domain, validated |
| `projectName` | `afasa-engine` | kebab-case, validated |
| `javaVersion` | `21` | Pick 21 or 17 |
| `springBootVersion` | `4.0.5` | |
| `dbServerName` | `localhost` | Override per environment |
| `eapiBaseUrl` | `http://eapi-internal/api` | Override per environment |

## Commands

- `jsbb init` — scaffold compliance-event-logger into current directory
- `jsbb list` — show available templates and prompts

### `init` flags

- `-o, --output <dir>` — target directory (default: current)
- `--dry-run` — preview without writing files
- `--no-git` — skip git init/commit
- `--no-install` — skip `mvnw validate`

## What it does NOT generate

- Workflow controllers (TPP / KS / ML / THF — these are AFASA-specific, hand-written)
- Stored procedure invocation code (Java side)
- EAPI client implementation
- Business logic
- Scheduled job implementations

These are **hand-written on top of the scaffold**. The CLI gives you the boilerplate; you add the domain.

## Origins

Implementation patterns lifted from [forge-cli](https://github.com/...) — specifically:
- `init` command flow (orphan detection, no metadata file)
- Java variable derivation (`groupId` + `projectName` → `packageName`/`packagePath`)
- EJS template rendering with path placeholders (`__packagePath__`)
- Cleaner orphan-detection without manifest files

## License

Internal use — EastWest Bank.
