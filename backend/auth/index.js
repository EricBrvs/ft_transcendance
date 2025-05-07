import Fastify from 'fastify'
import jwt from '@fastify/jwt'
import cors from '@fastify/cors'
import bcrypt from 'bcrypt'
import sqlite3 from 'sqlite3'
import { open } from 'sqlite'
import dotenv from 'dotenv'

dotenv.config()

const fastify = Fastify({ logger: true })
await fastify.register(cors)
await fastify.register(jwt, { secret: process.env.JWT_SECRET })

const db = await open({
  filename: process.env.AUTH_DB_PATH || './data/auth.db',
  driver: sqlite3.Database
})

await db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE,
    password TEXT
  )
`)

fastify.post('/register', async (req, reply) => {
  const { email, password } = req.body
  const hash = await bcrypt.hash(password, 10)
  try {
    await db.run('INSERT INTO users (email, password) VALUES (?, ?)', [email, hash])
    reply.send({ status: 'registered' })
  } catch (err) {
    reply.code(400).send({ error: 'Email already used' })
  }
})

fastify.post('/login', async (req, reply) => {
  const { email, password } = req.body
  const user = await db.get('SELECT * FROM users WHERE email = ?', [email])
  if (!user) return reply.code(401).send({ error: 'Invalid credentials' })

  const valid = await bcrypt.compare(password, user.password)
  if (!valid) return reply.code(401).send({ error: 'Invalid credentials' })

  const token = fastify.jwt.sign({ id: user.id, email: user.email })
  reply.send({ token })
})

fastify.listen({ port: 9000, host: '0.0.0.0' })
