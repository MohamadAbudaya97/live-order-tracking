FROM node:24-alpine AS build
WORKDIR /app

# The install hook builds the Prisma client, so the schema has to be there first.
COPY package.json package-lock.json prisma.config.ts ./
COPY prisma ./prisma
RUN npm ci

COPY tsconfig.json tsconfig.build.json nest-cli.json ./
COPY src ./src
RUN npm run build


FROM node:24-alpine
ENV NODE_ENV=production
WORKDIR /app

# Omitting "optional" as well keeps out the Prisma CLI and TypeScript, which are
# optional peers of @prisma/client and would add about 250 MB.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --omit=optional --ignore-scripts && npm cache clean --force

COPY --from=build /app/dist ./dist

USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
