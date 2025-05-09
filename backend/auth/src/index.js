import Fastify from 'fastify'
import jwt from '@fastify/jwt'
import cors from '@fastify/cors'
import bcrypt from 'bcrypt'
import sqlite3 from 'sqlite3'
import { open } from 'sqlite'
import dotenv from 'dotenv'
import fastifyOauth2 from '@fastify/oauth2'

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
    password TEXT,
    google_id TEXT,
    name TEXT
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

fastify.get('/', async (req, reply) => {
  reply.send("Hello world!\n")
})

// 🟢 Google OAuth2 SSO
fastify.register(fastifyOauth2, {
  name: 'googleOAuth2',
  scope: ['email', 'profile'],
  credentials: {
    client: {
      id: process.env.GOOGLE_CLIENT_ID,
      secret: process.env.GOOGLE_CLIENT_SECRET
    },
    auth: fastifyOauth2.GOOGLE_CONFIGURATION
  },
  startRedirectPath: '/auth/google/login',
  callbackUri: 'http://localhost:9000/auth/google/callback'
})

// 🔁 Callback après login Google
fastify.get('/auth/google/callback', async (req, reply) => {
  const { token } = await fastify.googleOAuth2.getAccessTokenFromAuthorizationCodeFlow(req)

  const res = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
    headers: {
      Authorization: `Bearer ${token.access_token}`
    }
  })

  if (!res.ok) {
    return reply.code(500).send({ error: 'Failed to fetch user info from Google' })
  }

  const profile = await res.json()
  const { id: google_id, email, name } = profile

  let user = await db.get('SELECT * FROM users WHERE email = ?', [email])
  if (!user) {
    await db.run('INSERT INTO users (email, google_id, name) VALUES (?, ?, ?)', [email, google_id, name])
    user = await db.get('SELECT * FROM users WHERE email = ?', [email])
  }

  const localToken = fastify.jwt.sign({ id: user.id, email: user.email })
  reply.send({ token: localToken })
})

// 🔒 Route protégée (test token JWT)
fastify.get('/me', async (req, reply) => {
  try {
    const auth = req.headers.authorization
    const token = auth?.split(' ')[1]
    const user = await fastify.jwt.verify(token)
    reply.send({ user })
  } catch (err) {
    reply.code(401).send({ error: 'Unauthorized' })
  }
})

fastify.listen({ port: 9000, host: '0.0.0.0' })
