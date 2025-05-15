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
  secret: process.env.JWT_SECRET,
  sign: { expiresIn: '2h' }
})

const db = await open({
  filename: process.env.AUTH_DB_PATH || './data/user.db',
  driver: sqlite3.Database
})
await db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT PRIMARY KEY,
    avatar TEXT,
    username TEXT NOT NULL,
  )
`)
await db.exec(`
    CREATE TABLE IF NOT EXISTS user_opts (
        uuid TEXT PRIMARY KEY,
        color_items TEXT DEFAULT '#3498db',
        color_bg TEXT DEFAULT '#1a1a1a',
        size_text INTEGER DEFAULT 18,
        speed_moves TEXT DEFAULT 'normal',
        FOREIGN KEY(uuid) REFERENCES users(uuid)
    )
`)
//CREATE: WHEN USER REGISTER
fastify.post('/users', async (request, reply) => {
    const { uuid, username } = request.body;

    try {
      db.prepare(`
        INSERT INTO users (uuid, email, username, password, picture, last_seen)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(uuid, email, username, password, picture || '', Date.now());

      db.prepare(`INSERT INTO user_settings (uuid) VALUES (?)`).run(uuid);

      return { uuid, email, username };
    } catch (err) {
      return reply.code(500).send({ error: 'User already exists or DB error' });
    }
});


app.get('/users/:uuid', (req, res) => {
    const user = db.prepare(`SELECT * FROM users WHERE uuid = ?`).get(req.params.uuid);
    const settings = db.prepare(`SELECT * FROM user_settings WHERE uuid = ?`).get(req.params.uuid);
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json({ ...user, settings });
  });
//TODO
/*
- CREATE USER (CALL ONLY AFTER 200 AUTH)
- Update USER
- DELETE USER ?? > Delete en cascade
- DL USER
- Ano User


*/