import Fastify from 'fastify'
import fastifyHttpProxy from '@fastify/http-proxy'
import dotenv from 'dotenv'

dotenv.config()

const fastify = Fastify({ logger: true })

// Proxy vers l’auth-service
await fastify.register(fastifyHttpProxy, {
  upstream: process.env.AUTH_URL || 'http://auth:9000',
  prefix: '/auth',               // Toute route /auth/* est redirigée
  rewritePrefix: '/auth',        // Garde le /auth
  http2: false
})

// Route de test
fastify.get('/', async () => ({ gateway: 'OK' }))

// (optionnel) Route protégée avec token
fastify.get('/me', async (req, reply) => {
  const auth = req.headers.authorization
  if (!auth) return reply.code(401).send({ error: 'No token' })

  // Redirige vers /me de l’auth-service
  const res = await fetch(`${process.env.AUTH_URL}/me`, {
    headers: { Authorization: auth }
  })

  const json = await res.json()
  reply.code(res.status).send(json)
})

fastify.listen({ port: 443, host: '0.0.0.0' })
