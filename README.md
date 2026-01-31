GreenLight

## Prerequisite
```shell
Go 1.22+
PostgreSQL 16.3+
```

## Database Migrations
```shell
cd repo_name
export GREENLIGHT_DB_DSN="postgres://myuser:mypassword@hostname/mydatabase"
migrate -path=./migrations -database=$GREENLIGHT_DB_DSN up
```