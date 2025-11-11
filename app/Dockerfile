FROM node:18-alpine

WORKDIR /usr/src/app

COPY package*.json ./
RUN npm install --production

COPY . .

# Accept environment (dev, staging, prod)
ARG NODE_ENV=dev
ENV NODE_ENV=$NODE_ENV

EXPOSE 3000
CMD ["node", "index.js"]
