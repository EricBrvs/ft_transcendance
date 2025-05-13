import Fastify from 'fastify'
import jwt from '@fastify/jwt'
import cors from '@fastify/cors'
import bcrypt from 'bcrypt'
import sqlite3 from 'sqlite3'
import { open } from 'sqlite'
import dotenv from 'dotenv'
import fastifyOauth2 from '@fastify/oauth2'
import crypto from 'crypto';


dotenv.config()

const fastify = Fastify({ logger: true })
await fastify.register(cors)
await fastify.register(jwt, {
  secret: process.env.JWT_SECRET,
  sign: { expiresIn: '2h' }
})

const db = await open({
  filename: process.env.AUTH_DB_PATH || './data/auth.db',
  driver: sqlite3.Database
})
await db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE,
    email TEXT UNIQUE,
    password TEXT,
    google_id TEXT,
    name TEXT,
    avatar TEXT,
    last_seen INTEGER
  )
`)

fastify.post('/register', async (req, reply) => {
  const { email, password } = req.body
  const hash = await bcrypt.hash(password, 10)
  const uuid = crypto.randomUUID();
  try {
    await db.run('INSERT INTO users (uuid, email, password) VALUES (?, ?, ?)', [uuid, email, hash])
    reply.send({ status: 'registered', uuid: uuid })
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

  const token = fastify.jwt.sign({ uuid: user.uuid, email: user.email })
  reply.send({ token })
})

fastify.get('/', async (req, reply) => {
  reply.send("Hello world!\n")
})

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
  callbackUri: 'http://localhost:9443/auth/google/callback'
})

fastify.get('/auth/google/callback', async (req, reply) => {
  const { token } = await fastify.googleOAuth2.getAccessTokenFromAuthorizationCodeFlow(req)
  const res = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
    headers: { Authorization: `Bearer ${token.access_token}` }
  })
  const { id: google_id, email, name } = await res.json()
  let debug_info = await res.json()

  const local = await db.get('SELECT password FROM users WHERE email = ?', [email])
  if (local && local.password) {
    return reply
      .code(403)
      .send({ error: "SSO forbidden: email already registered locally" })
  }

  let user = await db.get('SELECT * FROM users WHERE email = ?', [email])
  if (!user) {
    const uuid = crypto.randomUUID();
    await db.run(
      'INSERT INTO users (uuid, email, google_id, name) VALUES (?, ?, ?, ?)',
      [uuid, email, google_id, name]
    )
    user = await db.get('SELECT * FROM users WHERE email = ?', [email])
  }

  const localToken = fastify.jwt.sign({ uuid: user.uuid, email: user.email })
  reply.send({ token: localToken, debug: debug_info  })
})

// DEBUG ENDPOINT FOR MIDDLEWARE CHECK
fastify.get('/me', async (req, reply) => {
  const user = await db.get('SELECT uuid, email, last_seen FROM users WHERE uuid = ?', [req.user.uuid])
  reply.send({ user })
})

fastify.post('/logout', async (req, reply) => {
  const authHeader = req.headers.authorization
  const token = authHeader.split(' ')[1]
  await db.run('INSERT OR IGNORE INTO revoked_tokens (token) VALUES (?)', [token])
  reply.send({ status: 'logged out' })
})

fastify.post('/internal/lastseen', async (req, reply) => {
  const last = await db.get('SELECT last_seen FROM users WHERE uuid = ?', [req.user.uuid])
if (!last || Date.now() - last.last_seen > 10000) {
  await db.run('UPDATE users SET last_seen = ? WHERE uuid = ?', [Date.now(), req.user.uuid])
}



  reply.send({ ok: true })
})

fastify.listen({ port: 9000, host: '0.0.0.0' })
