# Multi-stage: install deps in builder, ship a slim runtime.
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

FROM node:20-alpine AS runtime
WORKDIR /app

# Run as a non-root user. node:alpine ships a `node` user (uid 1000); use it.
USER node

COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node server.js ./

ENV NODE_ENV=production
ENV PORT=5678
EXPOSE 5678

# tini-style PID 1 handling can be added later; for a lab, node directly is fine.
CMD ["node", "server.js"]
