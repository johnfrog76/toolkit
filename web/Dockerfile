# Build stage -- compiles the React SPA
#
# THE BUILD CONTEXT IS THE PACKAGE ROOT, not web/ (see docker-compose.yml's
# `context: ..`). web/src/shell/consts.ts imports ../consts.json through the
# @consts alias, and Vite inlines it at build time -- a context rooted at web/
# cannot see the file at all, so the image would fail to build while
# `npm run build` on a developer's machine succeeded.
FROM node:24-alpine AS builder
WORKDIR /app
COPY web/package.json web/package-lock.json ./
RUN npm ci
# The files the build-time aliases resolve to, at the paths they resolve to:
# /app is web/, so ../consts.json is /consts.json and
# ../Config/settings-workflows.json is /Config/settings-workflows.json (the
# @workflows alias, settings by workflow). tests/viteconfig.mjs holds the rule:
# every alias vite.config.ts points outside web/ has a COPY line here.
COPY consts.json /consts.json
COPY Config/settings-workflows.json /Config/settings-workflows.json
COPY web/ .
RUN npm run build

# Production stage -- serve with nginx
FROM nginx:alpine
COPY --from=builder /app/dist/client /usr/share/nginx/html
# A TEMPLATE, not a config: the image's entrypoint runs envsubst over
# /etc/nginx/templates/*.template at container start and writes the result to
# /etc/nginx/conf.d/default.conf. That is how the agent's port reaches the
# proxy_pass -- docker-compose.yml passes P20_AGENT_PORT in -- without the
# number being baked into the image. The filter keeps envsubst off nginx's own
# $host, $uri and $remote_addr: only P20_* names are substituted.
COPY --from=builder /app/nginx.conf.template /etc/nginx/templates/default.conf.template
ENV NGINX_ENVSUBST_FILTER=^P20_
EXPOSE 5173
