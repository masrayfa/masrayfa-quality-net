FROM ruby:3.3.2 AS builder

# Default image stays production-shaped; local/test builds pass BUNDLE_WITHOUT="".
ARG BUNDLE_WITHOUT="development test"

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  git \
  libpq-dev \
  tzdata \
  libjemalloc2 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /interview

COPY Gemfile Gemfile.lock ./
RUN if [ -n "$BUNDLE_WITHOUT" ]; then bundle config set --local without "$BUNDLE_WITHOUT"; else bundle config unset --local without; fi && \
    bundle install --deployment --frozen --jobs 4

COPY . .

# ============================================================================

FROM ruby:3.3.2

RUN apt-get update && apt-get install -y --no-install-recommends \
  libpq-dev \
  tzdata \
  libjemalloc2 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /interview

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /interview /interview

ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

RUN mkdir -p tmp/pids tmp/cache tmp/sockets log

EXPOSE 3001

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
