FROM mcr.microsoft.com/playwright:v1.59.1-noble

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

ENV NODE_ENV=production
ENV PORT=3000
ENV UX_HEADLESS=true
ENV UX_KEEP_OPEN=false

EXPOSE 3000

CMD ["npm", "run", "server"]
