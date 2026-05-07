FROM rust:1.92-alpine AS builder

RUN apk add --no-cache musl-dev pkgconfig openssl-dev openssl-libs-static

WORKDIR /build

COPY Cargo.toml Cargo.lock* ./
COPY .cargo ./.cargo

RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release && rm -rf src

COPY src src
RUN touch src/main.rs && cargo build --release

FROM alpine:3.20

RUN apk add --no-cache ca-certificates openssl

RUN addgroup -S telemt && adduser -S telemt -G telemt

COPY --from=builder /build/target/release/telemt /usr/local/bin/telemt

USER telemt

ENTRYPOINT ["telemt"]
CMD ["--help"]
