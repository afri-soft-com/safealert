FROM node:20-alpine

WORKDIR /app

# Dépendances de production uniquement
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY . .

# Utilisateur non-root
RUN addgroup -S safealert && adduser -S safealert -G safealert \
  && chown -R safealert:safealert /app
USER safealert

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/server.js"]
