# Greenlight

An **idiomatic Go REST API template** you can use as a starting point for your own services. It demonstrates standard patterns: structured routing, JSON request/response handling, database access with migrations, user registration with email activation, token-based authentication, permission-scoped endpoints, rate limiting, CORS, and graceful error handling.

The included **Movies** API is an example resource (CRUD + listing with filters and pagination). You can replace or extend it with your own domain models and endpoints.

## Table of contents

- [What's in the template](#whats-in-the-template)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Quick start](#quick-start)
- [Database migrations](#database-migrations)
- [API reference](#api-reference)
- [Development](#development)

---

## What's in the template

- **cmd/api** — HTTP server, router (httprouter), middleware (recovery, rate limit, CORS, auth)
- **internal/data** — Data layer: models, validation, filters/pagination helpers
- **internal/validator** — Reusable validation helpers
- **internal/jsonlog** — Structured JSON logging
- **internal/mailer** — SMTP mailer with templates (e.g. activation emails)
- **migrations** — PostgreSQL migrations (users, tokens, permissions, plus the example movies schema)
- **Makefile** — Run, migrate, build, audit, Docker

The example **Movies** resource shows how to wire CRUD, listing with query filters, and permission checks (`movies:read`, `movies:write`). Use it as a reference when adding your own resources.

---

## Prerequisites

- **Go** 1.22+
- **PostgreSQL** 16.3+
- **migrate** (CLI) for database migrations — [install](https://github.com/golang-migrate/migrate/tree/master/cmd/migrate)

---

## Configuration

The API is configured via command-line flags and/or environment. Required:

| Flag / env           | Description                    | Default     |
|----------------------|--------------------------------|-------------|
| `-db-dsn`            | PostgreSQL connection string  | *(required)* |

Optional:

| Flag | Description | Default |
|------|-------------|---------|
| `-port` | HTTP server port | `4000` |
| `-env` | Environment: `development`, `staging`, `production` | `development` |
| `-db-max-open-conns` | Max open DB connections | `25` |
| `-db-max-idle-conns` | Max idle DB connections | `25` |
| `-db-max-idle-time` | Max connection idle time | `15m` |
| `-limiter-rps` | Rate limit: requests per second | `2` |
| `-limiter-burst` | Rate limit: burst size | `4` |
| `-limiter-enabled` | Enable rate limiter | `true` |
| `-smtp-host`, `-smtp-port`, etc. | SMTP for activation emails | *(see `cmd/api/main.go`)* |
| `-cors-trusted-origins` | Allowed CORS origins (space-separated) | *(none)* |

Example:

```bash
export GREENLIGHT_DB_DSN="postgres://user:password@localhost:5432/greenlight?sslmode=disable"
./bin/api -port=4000 -env=development
```

---

## Quick start

1. Create a PostgreSQL database and set the DSN:

   ```bash
   export GREENLIGHT_DB_DSN="postgres://myuser:mypassword@hostname/mydatabase?sslmode=disable"
   ```

2. Run migrations (see [Database migrations](#database-migrations)).

3. Start the API:

   ```bash
   make run/api
   # or
   go run ./cmd/api -db-dsn=$GREENLIGHT_DB_DSN
   ```

4. Check health:

   ```bash
   curl http://localhost:4000/v1/healthcheck
   ```

---

## Database migrations

Using the [golang-migrate](https://github.com/golang-migrate/migrate) CLI:

```bash
export GREENLIGHT_DB_DSN="postgres://myuser:mypassword@hostname/mydatabase?sslmode=disable"
migrate -path=./migrations -database=$GREENLIGHT_DB_DSN up
```

To create a new migration:

```bash
make db/migrations/new name=your_migration_name
```

---

## API reference

This section documents the template’s built-in endpoints: healthcheck, users, tokens, and the **example Movies resource**. Use them as a reference when implementing your own resources.

- **Base URL:** `http://localhost:4000` (or your host/port)
- **Version prefix:** All endpoints use `/v1/`.
- **Content type:** Request and response bodies are **JSON**; send `Content-Type: application/json` and optionally `Accept: application/json`.

### Authentication

Protected endpoints require a **Bearer token** in the `Authorization` header:

```http
Authorization: Bearer <token>
```

Obtain a token via **POST /v1/tokens/authentication** (see [Create authentication token](#create-authentication-token)).  
Activation-only endpoints (e.g. **PUT /v1/users/activated**) do not use this header; they use the activation token in the JSON body.

### Error responses

Errors are returned as JSON with an `error` key:

- **Single message:** `{"error": "the requested resource could not be found"}`
- **Validation errors:** `{"error": {"field_name": "message", ...}}`

Common HTTP status codes:

| Code | Meaning |
|------|--------|
| `400` | Bad request (e.g. invalid JSON) |
| `401` | Unauthorized (invalid/missing token or wrong credentials) |
| **403** | Forbidden (inactive account or missing permission) |
| `404` | Resource not found |
| **409** | Conflict (e.g. edit conflict) |
| **422** | Unprocessable entity (validation failed) |
| **429** | Too many requests (rate limit) |
| `500` | Internal server error |

---

### Healthcheck

**GET /v1/healthcheck**  
No authentication.

**Response:** `200 OK`

```json
{
  "status": "available",
  "system_info": {
    "environment": "development",
    "version": "1.0.0"
  }
}
```

---

### Example resource: Movies

The template ships with a sample **Movies** resource to illustrate CRUD, filtering, pagination, and permissions. All movie endpoints require an authenticated user. Permissions:

- **movies:read** — list and get a single movie
- **movies:write** — create, update, delete movies

#### List movies

**GET /v1/movies**  
Permission: `movies:read`.

Query parameters:

| Parameter   | Type   | Default | Description |
|------------|--------|---------|-------------|
| `title`    | string | —       | Filter by title (partial, case-insensitive) |
| `genres`   | string | —       | Comma-separated genres (e.g. `genres=action,sci-fi`) |
| `page`     | int    | `1`     | Page number (1–10,000,000) |
| `page_size`| int    | `20`    | Items per page (1–100) |
| `sort`     | string | `id`    | Sort field: `id`, `title`, `year`, `runtime`; prefix with `-` for descending (e.g. `-year`) |

**Response:** `200 OK`

```json
{
  "movies": [
    {
      "id": 1,
      "title": "Example Movie",
      "year": 2020,
      "runtime": "102 mins",
      "genres": ["drama", "thriller"],
      "version": 1
    }
  ],
  "metadata": {
    "current_page": 1,
    "page_size": 20,
    "first_page": 1,
    "last_page": 1,
    "total_records": 1
  }
}
```

#### Get a movie

**GET /v1/movies/:id**  
Permission: `movies:read`.

**Response:** `200 OK` — same movie object as in the list.  
**404** if the movie does not exist.

#### Create a movie

**POST /v1/movies**  
Permission: `movies:write`.

**Request body:**

```json
{
  "title": "Example Movie",
  "year": 2020,
  "runtime": "102 mins",
  "genres": ["drama", "thriller"]
}
```

- **title** (string, required): max 500 bytes  
- **year** (integer, required): 1888 ≤ year ≤ current year  
- **runtime** (string, required): e.g. `"102 mins"` (positive integer + `" mins"`)  
- **genres** (array of strings, required): 1–5 unique values  

**Response:** `201 Created` with `Location: /v1/movies/<id>` and body:

```json
{
  "movie": {
    "id": 1,
    "title": "Example Movie",
    "year": 2020,
    "runtime": "102 mins",
    "genres": ["drama", "thriller"],
    "version": 1
  }
}
```

#### Update a movie

**PATCH /v1/movies/:id**  
Permission: `movies:write`.

Send only the fields to update (all optional):

```json
{
  "title": "Updated Title",
  "year": 2021,
  "runtime": "105 mins",
  "genres": ["drama", "thriller", "mystery"]
}
```

Validation rules are the same as for create. **409 Conflict** on edit conflict.

**Response:** `200 OK` with the updated movie object.

#### Delete a movie

**DELETE /v1/movies/:id**  
Permission: `movies:write`.

**Response:** `200 OK`

```json
{
  "message": "movie successfully deleted"
}
```

**404** if the movie does not exist.

---

### Users

#### Register a user

**POST /v1/users**  
No authentication. Creates an inactive user and sends an activation email (if SMTP is configured).

**Request body:**

```json
{
  "name": "Jane Doe",
  "email": "jane@example.com",
  "password": "securepassword"
}
```

- **name** (string): required  
- **email** (string): required, must be valid and unique  
- **password** (string): required, min length 8  

**Response:** `202 Accepted`

```json
{
  "user": {
    "id": 1,
    "created_at": "2024-01-15T10:00:00Z",
    "name": "Jane Doe",
    "email": "jane@example.com",
    "activated": false
  }
}
```

The user receives an email containing an activation token. Use it in **PUT /v1/users/activated** to activate the account.

#### Activate user

**PUT /v1/users/activated**  
No Bearer token; uses the activation token in the body.

**Request body:**

```json
{
  "token": "<activation_token_from_email>"
}
```

**Response:** `200 OK` with the activated user (e.g. `"activated": true`).  
**422** if the token is invalid or expired.

---

### Tokens

#### Create authentication token

**POST /v1/tokens/authentication**  
No authentication. Use this to log in and get a Bearer token for protected endpoints. The user must be activated.

**Request body:**

```json
{
  "email": "jane@example.com",
  "password": "securepassword"
}
```

**Response:** `201 Created`

```json
{
  "authentication_token": {
    "token": "XYZ123...",
    "expiry": "2024-01-16T10:00:00Z"
  }
}
```

Use the `token` value in the `Authorization: Bearer <token>` header. **401** for invalid or inactive credentials.

---

### Debug (development)

**GET /debug/vars**  
Exposes expvar metrics (version, goroutines, database stats, timestamp). Not part of the main API contract; may be disabled or restricted in production.

---

## Development

| Command | Description |
|--------|-------------|
| `make help` | List all make targets |
| `make run/api` | Run the API (uses `GREENLIGHT_DB_DSN`) |
| `make db/psql` | Connect to DB with `psql` |
| `make db/migrations/up` | Apply migrations (with confirmation) |
| `make db/migrations/new name=<name>` | Create a new migration |
| `make audit` | Tidy, format, vet, staticcheck, tests |
| `make build/api` | Build API binary (local + linux_amd64) |
| `make build/container` | Build Docker image |

Build with version info:

```bash
make build/api
./bin/api -db-dsn=$GREENLIGHT_DB_DSN
```

Version only:

```bash
go run ./cmd/api -version
```
