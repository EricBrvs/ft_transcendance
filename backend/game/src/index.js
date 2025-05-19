import Fastify from 'fastify'
import jwt from '@fastify/jwt'
import cors from '@fastify/cors'
import sqlite3 from 'sqlite3'
import { open } from 'sqlite'
import dotenv from 'dotenv'


dotenv.config()

const fastify = Fastify({ logger: true })
await fastify.register(cors)
await fastify.register(jwt, {
  secret: process.env.JWT_SECRET
})

const db = await open({
  filename: process.env.GAME_DB_PATH || './data/game.db',
  driver: sqlite3.Database
})

await db.exec(`
    CREATE TABLE IF NOT EXISTS matchs (
        uuid TEXT PRIMARY KEY,
		player TEXT NOT NULL,
		guest TEXT,
		tournament TEXT,
		score1 INTEGER DEFAULT 0, 
		score2 INTEGER DEFAULT 0,
		finished INTEGER DEFAULT 0,
		starttime INTEGER,
		endtime INTEGER
    )
`)

await db.exec(`
    CREATE TABLE IF NOT EXISTS tournaments (
        uuid TEXT PRIMARY KEY,
		host TEXT NOT NULL,
		players BLOB,
		match BLOB,
		winner TEXT,
		finished INT
    )
`)
fastify.get('/', async () => ({ game: 'OK' }))
//CRUD MATCH





//CRUD TOURNAMENT

async function getUserUUIDFromJWT(request) {
  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('No token');
  }

  const token = authHeader.split(' ')[1];
  const payload = await request.jwtVerify(); 
  return payload.uuid;
}

fastify.listen({ port: 9000, host: '0.0.0.0' })
