import Fastify from 'fastify'
import fastifyHttpProxy from '@fastify/http-proxy'
import jwt from '@fastify/jwt'
import dotenv from 'dotenv'
import sqlite3 from 'sqlite3'
import { open } from 'sqlite'
import cors from '@fastify/cors';

dotenv.config()

const db = await open({
  filename: process.env.GATEWAY_DB_PATH || './data/gateway.db',
  driver: sqlite3.Database
})

await db.exec(`
  CREATE TABLE IF NOT EXISTS revoked_tokens (
    token TEXT PRIMARY KEY,
    revoked_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
`)

const fastify = Fastify({ logger: true })
await fastify.register(cors, {
  origin: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
});
await fastify.register(jwt, {
  secret: process.env.JWT_SECRET,
  sign: { expiresIn: '2h' }
})
// Proxy vers AUTH
await fastify.register(fastifyHttpProxy, {
  upstream: process.env.AUTH_URL || 'http://auth:9000',
  prefix: '/auth',               
  rewritePrefix: '',        
  http2: false
})

await fastify.register(fastifyHttpProxy, {
  upstream: process.env.USER_URL || 'http://user:9000',
  prefix: '/user',
  rewritePrefix: '',
  http2: false
});

await fastify.register(fastifyHttpProxy, {
  upstream: process.env.GAME_URL || 'http://game:9000',
  prefix: '/game',
  rewritePrefix: '',
  http2: false
});

fastify.addHook('onRequest', async (req, reply) => {
  if (req.raw.url.startsWith('/auth')) return
  await fastify.authenticate(req, reply)
})

fastify.addHook('onResponse', async (req, reply) => {
  const authHeader = req.headers.authorization;
  const token = authHeader?.split(' ')[1];

  if (!token) return;

  try {
    const payload = await fastify.jwt.verify(token);
    if (!payload?.uuid) return;

    await fetch(`${process.env.AUTH_URL}/internal/lastseen`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });
  } catch (err) {
    fastify.log.warn('Failed to update last_seen:', err.message);
  }
});


fastify.decorate("authenticate", async (request, reply) => {
  try {
    const authHeader = request.headers.authorization
    const token = authHeader?.split(' ')[1]
    if (!token) throw new Error("Missing token")

    const decoded = await fastify.jwt.verify(token)
    request.user = decoded
  } catch (err) {
    reply.code(401).send({ error: 'Unauthorized' })
  }
})

fastify.get('/', async () => ({ gateway: 'OK' }))

fastify.get('/me', async (req, reply) => {
  const auth = req.headers.authorization
  const res = await fetch(`${process.env.AUTH_URL}/me`, {
    headers: { Authorization: auth }
  })

  const json = await res.json()
  reply.code(res.status).send(json)
})



fastify.listen({ port: 443, host: '0.0.0.0' })
