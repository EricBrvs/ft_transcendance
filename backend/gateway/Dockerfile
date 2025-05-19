FROM node:24-slim

WORKDIR /app

COPY package*.json ./
RUN npm install
#DEV/DEBUG COMMAND \/ NEED TO DELETE IT
# RUN npm install -g nodemon
# RUN apt update && apt install -y curl
#END DEV/DEBUG COMMAND


COPY . .

RUN mkdir -p ./data

CMD ["npm", "start"]
# CMD ["npm", "run", "dev"]
