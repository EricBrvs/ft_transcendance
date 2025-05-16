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
  filename: process.env.USER_DB_PATH || './data/user.db',
  driver: sqlite3.Database
})
await db.exec(`
    CREATE TABLE IF NOT EXISTS users (
        uuid TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        username TEXT NOT NULL,
        avatar TEXT
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

await db.exec(`
  CREATE TABLE IF NOT EXISTS friendships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    requester_uuid TEXT NOT NULL,
    target_uuid TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'declined')),
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (requester_uuid) REFERENCES users(uuid),
    FOREIGN KEY (target_uuid) REFERENCES users(uuid)
  );
`);

//CREATE: WHEN USER REGISTER (ACCESSIBLE ONLY BY AUTH)
fastify.post('/internal/init', async (request, reply) => {
  const authHeader = request.headers['x-internal-key'];
  if (authHeader !== process.env.JWT_SECRET) {
    return reply.code(403).send({ error: 'Forbidden' });
  }

  const { uuid, email, username, avatar } = request.body;
  if (!uuid || !email || !username) {
    return reply.code(400).send({ error: 'Missing required fields' });
  }

  try {
    const user = await db.get('SELECT 1 FROM users WHERE uuid = ?', [uuid]);
    if (user) {
      return reply.code(409).send({ error: 'User already exists' });
    }

    await db.run(
      'INSERT INTO users (uuid, email, username, avatar) VALUES (?, ?, ?, ?)',
      [uuid, email, username, avatar || '']
    );

    await db.run('INSERT INTO user_opts (uuid) VALUES (?)', [uuid]);

    return reply.code(201).send({ uuid, email, username });
  } catch (err) {
    console.error('DB Error:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});



fastify.get('/:uuid', async (request, reply) => {
  const { uuid } = request.params;

  try {
    const user = await db.get(`
      SELECT
        u.uuid,
        u.email,
        u.username,
        u.avatar,
        o.color_items,
        o.color_bg,
        o.size_text,
        o.speed_moves
      FROM users u
      JOIN user_opts o ON u.uuid = o.uuid
      WHERE u.uuid = ?
    `, [uuid]);

    if (!user) {
      return reply.code(404).send({ error: 'User not found' });
    }

    return reply.send(user);
  } catch (err) {
    console.error('DB error on GET /:uuid:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});


fastify.put('/update', async (request, reply) => {
  let uuid;
  try {
    uuid = await getUserUUIDFromJWT(request);
  } catch {
    return reply.code(401).send({ error: 'Invalid or missing token' });
  }

  const { email, username, avatar } = request.body;

  if (!email && !username && !avatar) {
    return reply.code(400).send({ error: 'Nothing to update' });
  }
  console.log('UUID', uuid);
  try {
    const userExists = await db.get('SELECT 1 FROM users WHERE uuid = ?', [uuid]);
    if (!userExists) {
      return reply.code(404).send({ error: 'User not found' });
    }

    const fields = [];
    const values = [];

    if (email) fields.push('email = ?'), values.push(email);
    if (username) fields.push('username = ?'), values.push(username);
    if (avatar) fields.push('avatar = ?'), values.push(avatar);
    values.push(uuid);

    const query = `UPDATE users SET ${fields.join(', ')} WHERE uuid = ?`;
    await db.run(query, values);

    return reply.send({ success: true });
  } catch (err) {
    console.error('PUT /update error:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.put('/options', async (request, reply) => {
  let uuid;
  try {
    uuid = await getUserUUIDFromJWT(request);
  } catch {
    return reply.code(401).send({ error: 'Invalid or missing token' });
  }

  const { color_items, color_bg, size_text, speed_moves } = request.body;

  try {
    const optsExist = await db.get('SELECT 1 FROM user_opts WHERE uuid = ?', [uuid]);
    if (!optsExist) {
      return reply.code(404).send({ error: 'User options not found' });
    }

    const fields = [];
    const values = [];

    if (color_items) fields.push('color_items = ?'), values.push(color_items);
    if (color_bg) fields.push('color_bg = ?'), values.push(color_bg);
    if (size_text) fields.push('size_text = ?'), values.push(size_text);
    if (speed_moves) fields.push('speed_moves = ?'), values.push(speed_moves);

    if (fields.length === 0) {
      return reply.code(400).send({ error: 'No fields provided' });
    }

    values.push(uuid);
    const query = `UPDATE user_opts SET ${fields.join(', ')} WHERE uuid = ?`;

    await db.run(query, values);

    return reply.send({ success: true });
  } catch (err) {
    console.error('PUT /update/options error:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.get('/friends', async (request, reply) => {
  let uuid;
  try {
    uuid = await getUserUUIDFromJWT(request);
  } catch {
    return reply.code(401).send({ error: 'Unauthorized' });
  }

  try {
    const accepted = await db.all(`
      SELECT * FROM friendships
      WHERE (requester_uuid = ? OR target_uuid = ?) AND status = 'accepted'
    `, [uuid, uuid]);

    const outgoing = await db.all(`
      SELECT * FROM friendships
      WHERE requester_uuid = ? AND status = 'pending'
    `, [uuid]);

    const incoming = await db.all(`
      SELECT * FROM friendships
      WHERE target_uuid = ? AND status = 'pending'
    `, [uuid]);

    return reply.send({
      friends: accepted,
      requests_sent: outgoing,
      requests_received: incoming
    });
  } catch (err) {
    console.error('GET /friends error:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});


fastify.post('/friends/:uuid', async (request, reply) => {
  let requester_uuid;
  try {
    requester_uuid = await getUserUUIDFromJWT(request);
  } catch {
    return reply.code(401).send({ error: 'Unauthorized' });
  }

  const target_uuid = request.params.uuid;
  if (target_uuid === requester_uuid) {
    return reply.code(400).send({ error: 'Cannot add yourself as friend' });
  }

  try {
    const existing = await db.get(`
      SELECT * FROM friendships
      WHERE (requester_uuid = ? AND target_uuid = ?)
         OR (requester_uuid = ? AND target_uuid = ?)
    `, [requester_uuid, target_uuid, target_uuid, requester_uuid]);

    if (existing) {
      return reply.code(409).send({ error: 'Friend request already exists or already friends' });
    }

    await db.run(`
      INSERT INTO friendships (requester_uuid, target_uuid, status)
      VALUES (?, ?, 'pending')
    `, [requester_uuid, target_uuid]);

    return reply.send({ success: true, message: 'Friend request sent' });
  } catch (err) {
    console.error('POST /friends error:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.put('/friends/:uuid', async (request, reply) => {
  let target_uuid;
  try {
    target_uuid = await getUserUUIDFromJWT(request);
  } catch {
    return reply.code(401).send({ error: 'Unauthorized' });
  }

  const requester_uuid = request.params.uuid;
  const { action } = request.body; // 'accept' ou 'decline'

  if (!['accept', 'decline'].includes(action)) {
    return reply.code(400).send({ error: 'Invalid action' });
  }

  try {
    const friendship = await db.get(`
      SELECT * FROM friendships
      WHERE requester_uuid = ? AND target_uuid = ? AND status = 'pending'
    `, [requester_uuid, target_uuid]);

    if (!friendship) {
      return reply.code(404).send({ error: 'No pending request from this user' });
    }

    const newStatus = action === 'accept' ? 'accepted' : 'declined';
    await db.run(`
      UPDATE friendships SET status = ? WHERE id = ?
    `, [newStatus, friendship.id]);

    return reply.send({ success: true, status: newStatus });
  } catch (err) {
    console.error('PUT /friends error:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.delete('/friends/:uuid', async (request, reply) => {
  let user_uuid;
  try {
    user_uuid = await getUserUUIDFromJWT(request);
  } catch {
    return reply.code(401).send({ error: 'Unauthorized' });
  }

  const other_uuid = request.params.uuid;

  try {
    const friendship = await db.get(`
      SELECT * FROM friendships
      WHERE (requester_uuid = ? AND target_uuid = ?)
         OR (requester_uuid = ? AND target_uuid = ?)
    `, [user_uuid, other_uuid, other_uuid, user_uuid]);

    if (!friendship) {
      return reply.code(404).send({ error: 'No relationship with this user' });
    }

    // Suppression de la relation
    await db.run('DELETE FROM friendships WHERE id = ?', [friendship.id]);

    return reply.send({ success: true, deleted: friendship });
  } catch (err) {
    console.error('DELETE /friends error:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.get('/me', async (request, reply) => {
  let uuid;
  try {
    uuid = await getUserUUIDFromJWT(request);
  } catch {
    return reply.code(401).send({ error: 'Invalid or missing token' });
  }

  try {
    const user = await db.get(`
      SELECT
        u.uuid,
        u.email,
        u.username,
        u.avatar,
        o.color_items,
        o.color_bg,
        o.size_text,
        o.speed_moves
      FROM users u
      JOIN user_opts o ON u.uuid = o.uuid
      WHERE u.uuid = ?
    `, [uuid]);

    if (!user) {
      return reply.code(404).send({ error: 'User not found' });
    }

    return reply.send(user);
  } catch (err) {
    console.error('DB error on GET /me:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.get('/users', async (request, reply) => {
  try {
    try {
      await getUserUUIDFromJWT(request);
    } catch {
      return reply.code(401).send({ error: 'Unauthorized' });
    }

    const users = await db.all(`
      SELECT
        u.uuid,
        u.email,
        u.username,
        u.avatar
      FROM users u
      ORDER BY u.username
    `);

    return reply.send(users);
  } catch (err) {
    console.error('DB error on GET /users:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});




//TODO
/*
- CREATE USER (CALL ONLY AFTER 200 AUTH)
- Update USER
- DELETE USER ?? > Delete en cascade
- DL USER
- Ano User


*/

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
