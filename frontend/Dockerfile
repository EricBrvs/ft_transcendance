FROM node:22-alpine AS builder

WORKDIR /app

COPY src/package.json src/package-lock.json ./

RUN npm i

COPY src/ .

RUN npm run build

FROM nginx:stable-alpine

COPY --from=builder /app/dist /usr/share/nginx/html

COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
