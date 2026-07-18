FROM node:26-slim AS build
WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends git openssh-client ca-certificates && \
    rm -rf /var/lib/apt/lists/*
ARG REPO_URL=https://github.com/sunsetTech/overlaybot-web.git
RUN --mount=type=ssh \
    --mount=type=secret,id=known_hosts,target=/root/.ssh/known_hosts \
    git clone $REPO_URL ./
RUN npm install
ARG VITE_TWITCH_CLIENT_ID
ARG VITE_TWITCH_REDIRECT_URI
ARG VITE_VIEWER_WS_URI
ENV VITE_TWITCH_CLIENT_ID=$VITE_TWITCH_CLIENT_ID
ENV VITE_TWITCH_REDIRECT_URI=$VITE_TWITCH_REDIRECT_URI
ENV VITE_VIEWER_WS_URI=$VITE_VIEWER_WS_URI
RUN npm run build --workspace=packages/client

FROM build AS build-debug
CMD bash

FROM caddy:builder AS caddy-builder
RUN xcaddy build --with github.com/caddy-dns/route53

FROM caddy:2.11 AS frontend
COPY --from=caddy-builder /usr/bin/caddy /usr/bin/caddy
COPY --from=build /app/packages/client/dist /srv/www
ARG CADDYFILE=Caddyfile
COPY ${CADDYFILE} /etc/caddy/Caddyfile

FROM frontend AS frontend-debug
CMD bash

FROM node:26-alpine AS backend
WORKDIR /srv/node
COPY --from=build /app/packages/server ./packages/server
COPY --from=build /app/packages/shared ./packages/shared
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/package-lock.json ./package-lock.json
COPY --from=build /app/tsconfig.json ./tsconfig.json
ARG DB_URL
ENV DATABASE_URL=$DB_URL
CMD npm run migrate -w @overlaybot/server && npm run dev -w @overlaybot/server
