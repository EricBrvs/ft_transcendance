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
		player TEXT,
		guest TEXT,
    guest2 TEXT,
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

fastify.post('/match', async (request, reply) => {
  const { player, guest, guest2, tournament, starttime } = request.body;
  const uuid = crypto.randomUUID();

  if (!player && !guest2 && !tournament) {
    return reply.code(400).send({ error: 'Missing required field: An opponent is missing (Player or guest2)' });
  }

  try {
    await db.run(`
      INSERT INTO matchs (uuid, player, guest, guest2, tournament, starttime)
      VALUES (?, ?, ?, ?, ?, ?)
    `, [uuid, player || null, guest || null, guest2 || null, tournament || null, starttime || null]);

    reply.code(201).send({ success: true, uuid });
  } catch (err) {
    console.error('POST /match error:', err);
    reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.put('/match/:uuid', async (request, reply) => {
  const { uuid } = request.params;
  const { guest, score1, score2, finished, endtime } = request.body;

  try {
    const match = await db.get('SELECT * FROM matchs WHERE uuid = ?', [uuid]);

    if (!match) {
      return reply.code(404).send({ error: 'Match not found' });
    }

    const updates = [];
    const values = [];

    if (guest !== undefined) {
      if (!match.guest) {
        updates.push('guest = ?');
        values.push(guest);
      } else if (!match.guest2) {
        updates.push('guest2 = ?');
        values.push(guest);
      } else {
        return reply.code(400).send({ error: 'Both guest and guest2 are already set' });
      }
    }

    if (score1 !== undefined) updates.push('score1 = ?'), values.push(score1);
    if (score2 !== undefined) updates.push('score2 = ?'), values.push(score2);
    if (finished !== undefined) updates.push('finished = ?'), values.push(finished);
    if (endtime !== undefined) updates.push('endtime = ?'), values.push(endtime);

    if (updates.length === 0) {
      return reply.code(400).send({ error: 'No valid fields to update' });
    }

    values.push(uuid);
    await db.run(`UPDATE matchs SET ${updates.join(', ')} WHERE uuid = ?`, values);

    reply.send({ success: true });
  } catch (err) {
    console.error('PUT /match/:uuid error:', err);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.get('/matchs', async (request, reply) => {
  try {
    const matchs = await db.all('SELECT * FROM matchs ORDER BY starttime DESC');
    reply.send(matchs);
  } catch (err) {
    console.error('GET /matchs error:', err);
    reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.get('/match/:uuid', async (request, reply) => {
  const { uuid } = request.params;

  try {
    const match = await db.get('SELECT * FROM matchs WHERE uuid = ?', [uuid]);
    if (!match) {
      return reply.code(404).send({ error: 'Match not found' });
    }

    reply.send(match);
  } catch (err) {
    console.error('GET /match/:uuid error:', err);
    reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.get('/match/user/:uuid', async (request, reply) => {
  const { uuid } = request.params;

  try {
    const matches = await db.all(`
      SELECT *
      FROM matchs
      WHERE player = ? OR guest = ? OR guest2 = ?
      ORDER BY starttime DESC
    `, [uuid, uuid, uuid]);

    if (!matches || matches.length === 0) {
      return reply.code(404).send({ error: 'No matches found for this user' });
    }

    reply.send(matches);
  } catch (err) {
    console.error('GET /match/user/:uuid error:', err);
    reply.code(500).send({ error: 'Internal server error' });
  }
});


//CRUD TOURNAMENT
fastify.post('/tournament', async (request, reply) => {
  const { host, players } = request.body;
  const uuid = crypto.randomUUID();

  if (!host || !Array.isArray(players) || players.length < 2) {
    return reply.code(400).send({ error: 'Host and minimum 2 players required' });
  }
  try {
    const totalMatches = players.length;
    const matchMap = [];

    const round1Matches = players.length / 2;
    let matchUuid;

    for (let i = 0; i < round1Matches; i++) {
      const player1 = players[i * 2];
      const player2 = players[i * 2 + 1];
      if (player1 === host)
        matchUuid = await createMatch(player1, player2, null, uuid);
      else
        matchUuid = await createMatch(null, player1, player2, uuid);
      matchMap.push({ uuid: matchUuid, round: 1 });
    }

    let currentRound = 2;
    let matchesToGenerate = round1Matches / 2;

    while (matchMap.length < totalMatches) {
      const num = Math.floor(matchesToGenerate);
      if (num <= 0) break;
    
      for (let i = 0; i < num; i++) {
        const matchUuid = await createMatch(null, null, null, uuid);
        matchMap.push({ uuid: matchUuid, round: currentRound });
      }
      matchesToGenerate = num / 2;
      currentRound++;
    }

    await db.run(`
      INSERT INTO tournaments (uuid, host, players, match, finished)
      VALUES (?, ?, ?, ?, 0)
    `, [
      uuid,
      host,
      JSON.stringify(players),
      JSON.stringify(matchMap)
    ]);

    reply.code(201).send({ success: true, uuid, match_map: matchMap });
  } catch (err) {
    console.error('POST /tournament error:', err);
    reply.code(500).send({ error: 'Internal server error' });
  }
});


fastify.put('/tournament/:uuid', async (request, reply) => {
  const { uuid } = request.params;
  const { players, match, winner, finished } = request.body;

  try {
    const existing = await db.get('SELECT * FROM tournaments WHERE uuid = ?', [uuid]);
    if (!existing) {
      return reply.code(404).send({ error: 'Tournament not found' });
    }

    const updates = [];
    const values = [];

    // if (players !== undefined) updates.push('players = ?'), values.push(JSON.stringify(players));
    // if (match !== undefined) updates.push('match = ?'), values.push(JSON.stringify(match));
    if (winner !== undefined) updates.push('winner = ?'), values.push(winner);
    if (finished !== undefined) updates.push('finished = ?'), values.push(finished);

    if (updates.length === 0) {
      return reply.code(400).send({ error: 'No fields to update' });
    }

    values.push(uuid);

    await db.run(`UPDATE tournaments SET ${updates.join(', ')} WHERE uuid = ?`, values);

    reply.send({ success: true });
  } catch (err) {
    console.error('PUT /tournament/:uuid error:', err);
    reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.get('/tournament/:uuid', async (request, reply) => {
  const { uuid } = request.params;

  try {
    const tournament = await db.get('SELECT * FROM tournaments WHERE uuid = ?', [uuid]);

    if (!tournament) {
      return reply.code(404).send({ error: 'Tournament not found' });
    }

    tournament.players = tournament.players ? JSON.parse(tournament.players) : null;
    tournament.match = tournament.match ? JSON.parse(tournament.match) : null;

    reply.send(tournament);
  } catch (err) {
    console.error('GET /tournament/:uuid error:', err);
    reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.get('/tournaments', async (request, reply) => {
  try {
    const rows = await db.all('SELECT * FROM tournaments ORDER BY finished ASC, uuid DESC');

    const tournaments = rows.map(t => ({
      ...t,
      players: t.players ? JSON.parse(t.players) : null,
      match: t.match ? JSON.parse(t.match) : null
    }));

    reply.send(tournaments);
  } catch (err) {
    console.error('GET /tournaments error:', err);
    reply.code(500).send({ error: 'Internal server error' });
  }
});
fastify.get('/tournament/user/:uuid', async (request, reply) => {
  const { uuid } = request.params;

  try {
    const tournaments = await db.all(`
      SELECT *
      FROM tournaments
      WHERE host = ?
      ORDER BY finished ASC, uuid DESC
    `, [uuid]);

    if (!tournaments || tournaments.length === 0) {
      return reply.code(404).send({ error: 'No tournaments found for this user' });
    }

    const parsed = tournaments.map(t => ({
      ...t,
      players: t.players ? JSON.parse(t.players) : null,
      match: t.match ? JSON.parse(t.match) : null
    }));

    reply.send(parsed);
  } catch (err) {
    console.error('GET /tournament/user/:uuid error:', err);
    reply.code(500).send({ error: 'Internal server error' });
  }
});

fastify.delete('/internal/delete', async (request, reply) => {
  if (request.headers['x-internal-key'] !== process.env.JWT_SECRET)
    return reply.code(403).send({ error: 'Forbidden' });

  const { uuid } = request.body;
  try {
    await db.run('DELETE FROM matchs WHERE player = ? OR guest = ? OR guest2 = ?', [uuid, uuid, uuid]);
    await db.run('DELETE FROM tournaments WHERE host = ?', [uuid]);
    reply.send({ deleted: true });
  } catch (err) {
    console.error('Game delete error:', err);
    reply.code(500).send({ error: 'Internal server error' });
  }
});


async function createMatch(player = null, guest = null, guest2 = null, tournament = null) {
  const matchPayload = {
    player,
    guest,
    guest2,
    tournament,
    starttime: null
  };

  const res = await fetch(`${process.env.SELF_URL}/match`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(matchPayload)
  });

  if (!res.ok) {
    throw new Error('Failed to create match');
  }

  const { uuid } = await res.json();
  return uuid;
}

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
