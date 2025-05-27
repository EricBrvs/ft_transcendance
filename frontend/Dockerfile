FROM node:22-alpine AS builder

WORKDIR /app

COPY src/ .

RUN npm install
RUN npm run build

FROM nginx:stable-alpine

COPY --from=builder /app/dist /usr/share/nginx/html

COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /etc/nginx/certs

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
