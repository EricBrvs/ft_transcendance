import Fastify from 'fastify'
import jwt from '@fastify/jwt'
import cors from '@fastify/cors'
import bcrypt from 'bcrypt'
import sqlite3 from 'sqlite3'
import { open } from 'sqlite'
import dotenv from 'dotenv'
import fastifyOauth2 from '@fastify/oauth2'
import crypto from 'crypto';
import { Logger } from './logger.js';

dotenv.config()

// Initialize our custom logger
const logger = new Logger({ serviceName: 'auth' });

// Use built-in Fastify logger for HTTP requests
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
    username TEXT UNIQUE,
    google_id TEXT,
    avatar TEXT,
    last_seen INTEGER
  )
`)

fastify.post('/register', async (req, reply) => {
  const { email, password } = req.body;
  const isValidPassword = (pwd) => {
    return /^(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$/.test(pwd);
  };
  if (!isValidPassword(password)) {
    return reply.code(400).send({
      error: 'Password must be at least 8 characters, include one uppercase letter, one number, and one special character.'
    });
  }
  const hash = await bcrypt.hash(password, 10);
  const uuid = crypto.randomUUID();
  try {
    const localPart = email.split('@')[0].toLowerCase().trim();
    const username = localPart.replace(/[^a-z0-9]/g, '');
    await db.run(
      'INSERT INTO users (uuid, email, password, username) VALUES (?, ?, ?, ?)',
      [uuid, email, hash, username]
    );
    const userPayload = {
      uuid: uuid,
      email: email,
      username: username
    };
    console.log(userPayload);
    await fetch(`${process.env.USER_URL}/internal/init`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-internal-key': process.env.JWT_SECRET
      },
      body: JSON.stringify(userPayload)
    });
    reply.send({ status: 'registered', uuid });
  } catch (err) {
    console.error(err);
    reply.code(400).send({ error: 'Email already used or invalid' });
  }
});


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
  startRedirectPath: '/google/login',
  callbackUri: `${process.env.GLOBAL_URL}/auth/google/callback`
})

fastify.get('/google/callback', async (req, reply) => {
  const { token } = await fastify.googleOAuth2.getAccessTokenFromAuthorizationCodeFlow(req)
  const res = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
    headers: { Authorization: `Bearer ${token.access_token}` }
  })
  const { id: google_id, email, picture } = await res.json()


  const local = await db.get('SELECT password FROM users WHERE email = ?', [email])
  if (local && local.password) {
    return reply
      .code(403)
      .send({ error: "SSO forbidden: email already registered locally" })
  }

  let user = await db.get('SELECT * FROM users WHERE email = ?', [email])
  if (!user) {
    const uuid = crypto.randomUUID();
    const localPart = email.split('@')[0].toLowerCase().trim();
    const username = localPart.replace(/[^a-z0-9]/g, '');
    await db.run(
      'INSERT INTO users (uuid, email, username, google_id, avatar, last_seen) VALUES (?, ?, ?, ?, ?, ?)',
      [uuid, email, username, google_id, picture, Date.now()]
    )
    user = await db.get('SELECT * FROM users WHERE email = ?', [email])
  }
  const userPayload = {
    uuid: user.uuid,
    email: user.email,
    username: user.username,
    avatar: user.avatar
  };
  await fetch(`${process.env.USER_URL}/internal/init`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-internal-key': process.env.JWT_SECRET
    },
    body: JSON.stringify(userPayload)
  });
  const localToken = fastify.jwt.sign({ uuid: user.uuid, email: user.email })
  //reply.send({ token: localToken })
	reply.redirect(`http://localhost:5173/?code=${localToken}`)
})

fastify.put('/update', async (request, reply) => {
  let uuid;
  try {
    uuid = await getUserUUIDFromJWT(request);
  } catch {
    return reply.code(401).send({ error: 'Unauthorized' });
  }

  const { old_password, new_password } = request.body;

  if (!old_password || !new_password) {
    return reply.code(400).send({ error: 'Missing passwords' });
  }

  const isValidPassword = (pwd) => {
    return /^(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$/.test(pwd);
  };

  if (!isValidPassword(new_password)) {
    return reply.code(400).send({
      error: 'New password must be at least 8 characters, include one uppercase letter, one number, and one special character.'
    });
  }
  try {
    const user = await db.get('SELECT password FROM users WHERE uuid = ?', [uuid]);
    if (!user) {
      return reply.code(404).send({ error: 'User not found' });
    }

    const match = await bcrypt.compare(old_password, user.password);
    if (!match) {
      return reply.code(403).send({ error: 'Invalid current password' });
    }

    const newHash = await bcrypt.hash(new_password, 10);
    await db.run('UPDATE users SET password = ? WHERE uuid = ?', [newHash, uuid]);

    return reply.send({ success: true, message: 'Password updated' });
  } catch (err) {
    console.error('PUT /update error:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.get('/me', async (req, reply) => {
  const user = await db.get('SELECT uuid, email, username, last_seen, avatar FROM users WHERE uuid = ?', [req.query.uuid])
  console.log(user);
  reply.send({ user })
})

fastify.post('/logout', async (req, reply) => {
  const authHeader = req.headers.authorization
  const token = authHeader.split(' ')[1]
  await db.run('INSERT OR IGNORE INTO revoked_tokens (token) VALUES (?)', [token])
  reply.send({ status: 'logged out' })
})


/* 

  INTERNAL ROUTES
  ROUTE FOR INTERNAL USE ONLY (Can't be exposed to the public)

*/
fastify.post('/internal/lastseen', async (req, reply) => {
  try {
    const auth = req.headers.authorization
    const token = auth?.split(' ')[1]
    if (!token) throw new Error('No token')

    const payload = await fastify.jwt.verify(token)
    const uuid = payload.uuid
    if (!uuid) throw new Error('Missing uuid in token')

    const last = await db.get('SELECT last_seen FROM users WHERE uuid = ?', [uuid])
    if (!last || Date.now() - last.last_seen > 10000) {
      await db.run('UPDATE users SET last_seen = ? WHERE uuid = ?', [Date.now(), uuid])
    }

    reply.send({ ok: true })
  } catch (err) {
    reply.code(401).send({ error: 'Unauthorized' })
  }
})

fastify.get('/internal/lastseen', async (req, reply) => {
  try {
    const auth = req.headers.authorization;
    const token = auth?.split(' ')[1];
    if (!token) throw new Error('No token');

    const payload = await fastify.jwt.verify(token);
    const uuid = payload.uuid;
    if (!uuid) throw new Error('Missing uuid in token');

    const user = await db.get('SELECT last_seen FROM users WHERE uuid = ?', [uuid]);
    if (!user) return reply.code(404).send({ error: 'User not found' });

    reply.send({ last_seen: user.last_seen });
  } catch (err) {
    console.error('GET /internal/lastseen error:', err.message);
    reply.code(401).send({ error: 'Unauthorized or token invalid' });
  }
});


fastify.get('/internal/lastseen/user/:uuid', async (req, reply) => {
  try {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) throw new Error('No token');
    await fastify.jwt.verify(token);

    const { uuid } = req.params;
    if (!uuid) return reply.code(400).send({ error: 'Missing uuid in params' });

    const user = await db.get('SELECT last_seen FROM users WHERE uuid = ?', [uuid]);
    if (!user) {
      return reply.code(404).send({ error: 'User not found' });
    }

    reply.send({ last_seen: user.last_seen });
  } catch (err) {
    console.error('GET /internal/lastseen/user/:uuid error:', err.message);
    return reply.code(401).send({ error: 'Unauthorized' });
  }
});

fastify.delete('/account', async (request, reply) => {
  const authHeader = request.headers.authorization;
  const token = authHeader?.split(' ')[1];
  if (!token) return reply.code(401).send({ error: 'Unauthorized' });

  let uuid;
  try {
    const payload = await fastify.jwt.verify(token);
    uuid = payload.uuid;
  } catch (err) {
    console.error('JWT verification error:', err);
    
    return reply.code(401).send({ error: 'Invalid token' });
  }

  try {

    await fetch(`${process.env.USER_URL}/internal/delete`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'x-internal-key': process.env.JWT_SECRET
      },
      body: JSON.stringify({ uuid })
    });

    await fetch(`${process.env.GAME_URL}/internal/delete`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'x-internal-key': process.env.JWT_SECRET
      },
      body: JSON.stringify({ uuid })
    });
    await db.run('DELETE FROM users WHERE uuid = ?', [uuid]);

    reply.send({ status: 'account fully deleted', uuid });
  } catch (err) {
    console.error('Full account deletion failed:', err);
    reply.code(500).send({ error: 'Account deletion failed' });
  }
});



async function getUserUUIDFromJWT(request) {
  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('No token');
  }

  const token = authHeader.split(' ')[1];
  const payload = await request.jwtVerify(); // ou: fastify.jwt.verify(token)
  return payload.uuid;
}

fastify.listen({ port: 9000, host: '0.0.0.0' })
