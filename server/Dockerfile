FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go test ./...
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/xbd-server ./cmd/api

FROM alpine:3.21
RUN adduser -D -H -u 10001 xbd
USER xbd
COPY --from=build /out/xbd-server /usr/local/bin/xbd-server
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/xbd-server"]
