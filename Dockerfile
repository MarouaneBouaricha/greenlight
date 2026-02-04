# --- Stage 1: Builder ---
FROM golang:1.24-alpine AS builder

RUN apk add --no-cache make git build-base ca-certificates tzdata

RUN go install honnef.co/go/tools/cmd/staticcheck@latest

WORKDIR /app

COPY go.mod go.sum ./

COPY . .

RUN make audit

RUN CGO_ENABLED=0 make build/api

# --- Stage 2: Runner ---
FROM scratch

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

WORKDIR /app

COPY --from=builder /app/bin/linux_amd64/api ./

USER 10001:10001

EXPOSE 4000

ENTRYPOINT ["./api"]