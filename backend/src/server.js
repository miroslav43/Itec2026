require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const multer = require('multer');
const { pool, initDB } = require('./db');
const Jimp = require('jimp');

const JWT_SECRET = process.env.JWT_SECRET || 'itec_override_secret_2025';

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// ── Anthem storage setup (memory → DB) ───────────────────────────────────────
const anthemUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 20 * 1024 * 1024 }, // 20 MB max
  fileFilter: (req, file, cb) => {
    const ok = file.mimetype === 'audio/mpeg' || file.mimetype === 'audio/mp3'
               || file.originalname.endsWith('.mp3');
    cb(null, ok);
  },
});

// Serve custom poster images statically
const CUSTOM_POSTERS_DIR = path.join(__dirname, 'custom_posters');
if (!fs.existsSync(CUSTOM_POSTERS_DIR)) fs.mkdirSync(CUSTOM_POSTERS_DIR);
app.use('/custom-posters', express.static(CUSTOM_POSTERS_DIR));

// Auth middleware
function requireAuth(req, res, next) {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) return res.status(401).json({ error: 'Unauthorized' });
  try {
    req.user = jwt.verify(auth.slice(7), JWT_SECRET);
    next();
  } catch { res.status(401).json({ error: 'Invalid token' }); }
}

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// ============================================
// DATA STRUCTURES
// ============================================

// Poster definitions - add new posters here
const POSTERS = {
  'afis1': { id: 'afis1', name: 'Social Presence', gridSize: 20 },
  'afis2': { id: 'afis2', name: 'Digital Marketing', gridSize: 20 },
  'afis3': { id: 'afis3', name: 'Tech Innovation', gridSize: 20 },
  'afis4': { id: 'afis4', name: 'Creative Design', gridSize: 20 },
  'afis5': { id: 'afis5', name: 'Cloud Computing', gridSize: 20 },
  'afis6': { id: 'afis6', name: 'AI Revolution', gridSize: 20 },
  'afis7': { id: 'afis7', name: 'Cyber Security', gridSize: 20 },
  'afis8': { id: 'afis8', name: 'Data Science', gridSize: 20 },
  'afis9': { id: 'afis9', name: 'Mobile Future', gridSize: 20 },
  'afis10': { id: 'afis10', name: 'Web3 World', gridSize: 20 }
};

// Team definitions
const TEAMS = {
  'red': { id: 'red', name: 'Red Team', color: '#FF0040' },
  'blue': { id: 'blue', name: 'Blue Team', color: '#00D4FF' },
  'green': { id: 'green', name: 'Green Team', color: '#00FF88' },
  'purple': { id: 'purple', name: 'Purple Team', color: '#9D00FF' }
};

// Custom posters (persisted to disk as fallback + DB)
const CUSTOM_POSTERS_FILE = path.join(__dirname, 'custom_posters.json');
let customPosters = {};
try {
  if (fs.existsSync(CUSTOM_POSTERS_FILE)) {
    customPosters = JSON.parse(fs.readFileSync(CUSTOM_POSTERS_FILE, 'utf8'));
    Object.assign(POSTERS, customPosters);
  }
} catch (e) { console.error('Error loading custom posters:', e); }

function saveCustomPosters() {
  fs.writeFileSync(CUSTOM_POSTERS_FILE, JSON.stringify(customPosters, null, 2));
}

async function loadCustomPostersFromDB() {
  try {
    const { rows } = await pool.query('SELECT * FROM posters WHERE is_custom = true');
    // Clear stale custom posters (JSON may have entries deleted from DB)
    for (const id of Object.keys(customPosters)) {
      delete POSTERS[id];
    }
    customPosters = {};
    for (const row of rows) {
      const entry = { id: row.id, name: row.name, description: row.description, imageUrl: row.image_url, gridSize: row.grid_size, isCustom: true };
      customPosters[row.id] = entry;
      POSTERS[row.id] = entry;
    }
    saveCustomPosters(); // sync JSON to match DB
    console.log(`Loaded ${rows.length} custom posters from DB`);
  } catch (e) { console.error('DB load posters error:', e); }
}

// In-memory state for each poster room
const posterRooms = {};

// ── Territory DB helpers ─────────────────────────────────────────────────────
async function saveTerritoryToDB(posterId, grid, territory) {
  try {
    await pool.query(
      `INSERT INTO territory_state (poster_id, grid_json, territory_json, dominant, updated_at)
       VALUES ($1,$2,$3,$4,NOW())
       ON CONFLICT (poster_id) DO UPDATE
       SET grid_json=$2, territory_json=$3, dominant=$4, updated_at=NOW()`,
      [posterId, JSON.stringify(grid), JSON.stringify(territory), territory.dominant || null]
    );
  } catch (e) {
    console.error('[DB] saveTerritoryToDB error:', e.message);
  }
}

async function loadTerritoryFromDB(posterId) {
  try {
    const { rows } = await pool.query(
      'SELECT grid_json, territory_json FROM territory_state WHERE poster_id=$1',
      [posterId]
    );
    if (rows.length > 0) {
      return {
        grid: JSON.parse(rows[0].grid_json),
        territory: JSON.parse(rows[0].territory_json)
      };
    }
  } catch (e) {
    console.error('[DB] loadTerritoryFromDB error:', e.message);
  }
  return null;
}

// Initialize a poster room (async to load territory from DB)
async function initPosterRoom(posterId) {
  if (!posterRooms[posterId]) {
    const poster = POSTERS[posterId];
    if (!poster) return null;
    
    const gridSize = poster.gridSize;
    posterRooms[posterId] = {
      posterId,
      posterName: poster.name,
      users: new Map(),
      strokes: [],
      grid: Array(gridSize).fill(null).map(() => Array(gridSize).fill(null)),
      territory: {},
      lastUpdate: Date.now()
    };

    // Restore from DB
    const saved = await loadTerritoryFromDB(posterId);
    if (saved) {
      posterRooms[posterId].grid = saved.grid;
      posterRooms[posterId].territory = saved.territory;
      console.log(`[DB] Restored territory for ${posterId} (dominant: ${saved.territory.dominant})`);
    }
  }
  return posterRooms[posterId];
}

// Calculate territory ownership
function calculateTerritory(room) {
  const gridSize = room.grid.length;
  const totalCells = gridSize * gridSize;
  const teamCounts = {};
  
  for (let y = 0; y < gridSize; y++) {
    for (let x = 0; x < gridSize; x++) {
      const teamId = room.grid[y][x];
      if (teamId) {
        teamCounts[teamId] = (teamCounts[teamId] || 0) + 1;
      }
    }
  }
  
  const territory = {};
  let dominantTeam = null;
  let maxCount = 0;
  
  for (const [teamId, count] of Object.entries(teamCounts)) {
    const percentage = Math.round((count / totalCells) * 100);
    territory[teamId] = {
      cells: count,
      percentage,
      color: TEAMS[teamId]?.color || '#FFFFFF'
    };
    if (count > maxCount) {
      maxCount = count;
      dominantTeam = teamId;
    }
  }
  
  territory.dominant = dominantTeam;
  territory.total = totalCells;
  
  return territory;
}

// Update grid cells based on stroke points
function updateGridFromStroke(room, stroke) {
  const gridSize = room.grid.length;
  
  for (const point of stroke.points) {
    const gridX = Math.floor(point.x * gridSize);
    const gridY = Math.floor(point.y * gridSize);
    
    // Update cell and surrounding cells based on brush size
    const radius = Math.ceil(stroke.size / 20);
    for (let dy = -radius; dy <= radius; dy++) {
      for (let dx = -radius; dx <= radius; dx++) {
        const nx = gridX + dx;
        const ny = gridY + dy;
        if (nx >= 0 && nx < gridSize && ny >= 0 && ny < gridSize) {
          room.grid[ny][nx] = stroke.teamId;
        }
      }
    }
  }
  
  room.territory = calculateTerritory(room);
  // Persist to DB (fire-and-forget)
  saveTerritoryToDB(room.posterId, room.grid, room.territory);
  return room.territory;
}

// ============================================
// REST ENDPOINTS
// ============================================

app.get('/', (req, res) => {
  res.json({
    name: 'iTEC OVERRIDE Backend',
    version: '1.0.0',
    status: 'running',
    posters: Object.keys(POSTERS).length,
    activeRooms: Object.keys(posterRooms).length
  });
});

app.get('/api/posters', (req, res) => {
  res.json(POSTERS);
});

app.get('/api/posters/:posterId', (req, res) => {
  const { posterId } = req.params;
  const poster = POSTERS[posterId];
  if (!poster) {
    return res.status(404).json({ error: 'Poster not found' });
  }
  
  const room = posterRooms[posterId];
  res.json({
    ...poster,
    hasActiveRoom: !!room,
    userCount: room ? room.users.size : 0,
    territory: room ? room.territory : {}
  });
});

// ============================================
// AUTH ROUTES
// ============================================

app.post('/api/auth/register', async (req, res) => {
  const { email, username, password } = req.body;
  if (!email || !username || !password) return res.status(400).json({ error: 'All fields required' });
  if (password.length < 6) return res.status(400).json({ error: 'Password too short (min 6 chars)' });
  try {
    const hash = await bcrypt.hash(password, 10);
    const { rows } = await pool.query(
      'INSERT INTO users (email, username, password_hash) VALUES ($1, $2, $3) RETURNING id, email, username, created_at',
      [email.toLowerCase(), username.trim(), hash]
    );
    const user = rows[0];
    const token = jwt.sign({ id: user.id, email: user.email, username: user.username }, JWT_SECRET, { expiresIn: '30d' });
    res.json({ token, user: { id: user.id, email: user.email, username: user.username } });
  } catch (e) {
    if (e.code === '23505') {
      const field = e.constraint?.includes('email') ? 'Email' : 'Username';
      return res.status(409).json({ error: `${field} already taken` });
    }
    console.error('Register error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/auth/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'Email and password required' });
  try {
    const { rows } = await pool.query('SELECT * FROM users WHERE email = $1', [email.toLowerCase()]);
    if (rows.length === 0) return res.status(401).json({ error: 'Invalid email or password' });
    const user = rows[0];
    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) return res.status(401).json({ error: 'Invalid email or password' });
    const token = jwt.sign({ id: user.id, email: user.email, username: user.username }, JWT_SECRET, { expiresIn: '30d' });
    res.json({ token, user: { id: user.id, email: user.email, username: user.username } });
  } catch (e) {
    console.error('Login error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

app.get('/api/auth/verify', requireAuth, (req, res) => {
  res.json({ user: req.user });
});

app.get('/api/teams', (req, res) => {
  res.json(TEAMS);
});

app.get('/api/custom-posters', (req, res) => {
  res.json(Object.values(customPosters));
});

// ============================================
// STICKER API
// ============================================

app.get('/api/stickers', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, prompt, creator_id, image_base64, created_at FROM stickers ORDER BY created_at DESC LIMIT 100'
    );
    res.json(rows);
  } catch (e) {
    console.error('GET /api/stickers error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

app.delete('/api/stickers', async (req, res) => {
  try {
    const { rowCount } = await pool.query('DELETE FROM stickers');
    res.json({ ok: true, deleted: rowCount });
  } catch (e) {
    console.error('DELETE /api/stickers error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/stickers', async (req, res) => {
  const { id, prompt, creatorId, imageBase64 } = req.body;
  if (!id || !prompt || !imageBase64) {
    return res.status(400).json({ error: 'id, prompt, imageBase64 required' });
  }
  try {
    await pool.query(
      'INSERT INTO stickers (id, prompt, creator_id, image_base64, created_at) VALUES ($1, $2, $3, $4, NOW()) ON CONFLICT (id) DO NOTHING',
      [id, prompt, creatorId || 'anonymous', imageBase64]
    );
    res.json({ ok: true, id });
  } catch (e) {
    console.error('POST /api/stickers error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

// ============================================
// MAP PINS API
// ============================================

app.get('/api/map-pins', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT poster_id, x, y, z, nx, ny, nz FROM map_pins ORDER BY created_at ASC'
    );
    res.json(rows);
  } catch (e) {
    console.error('GET /api/map-pins error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/map-pins/:posterId', async (req, res) => {
  const { posterId } = req.params;
  const { x, y, z, nx = 0, ny = 1, nz = 0 } = req.body;
  if (x == null || y == null || z == null) {
    return res.status(400).json({ error: 'x, y, z required' });
  }
  try {
    await pool.query(
      `INSERT INTO map_pins (poster_id, x, y, z, nx, ny, nz, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,NOW())
       ON CONFLICT (poster_id) DO UPDATE
       SET x=$2, y=$3, z=$4, nx=$5, ny=$6, nz=$7`,
      [posterId, x, y, z, nx, ny, nz]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error('POST /api/map-pins error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

app.delete('/api/map-pins/:posterId', async (req, res) => {
  const { posterId } = req.params;
  try {
    await pool.query('DELETE FROM map_pins WHERE poster_id=$1', [posterId]);
    res.json({ ok: true });
  } catch (e) {
    console.error('DELETE /api/map-pins error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

app.delete('/api/map-pins', async (req, res) => {
  try {
    const { rowCount } = await pool.query('DELETE FROM map_pins');
    res.json({ ok: true, deleted: rowCount });
  } catch (e) {
    console.error('DELETE /api/map-pins (all) error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

// Reset all poster territories (clear battle results so fights can restart)
app.delete('/api/territory/reset', async (req, res) => {
  try {
    // Clear in-memory territory for all rooms
    for (const [posterId, room] of Object.entries(posterRooms)) {
      if (room.grid) {
        const size = room.grid.length;
        room.grid = Array(size).fill(null).map(() => Array(size).fill(''));
      }
      room.territory = null;
      // Notify connected clients
      io.to(posterId).emit('territory_update', { posterId, teams: {}, dominant: null, total: 0 });
    }
    // Clear from DB
    try { await pool.query('DELETE FROM territory_state'); } catch (_) {}
    try { await pool.query('DELETE FROM strokes'); } catch (_) {}
    res.json({ ok: true });
  } catch (e) {
    console.error('DELETE /api/territory/reset error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

// ── Anthem endpoints (stored in DB as BYTEA) ─────────────────────────────────
// Upload MP3 for a team — stores in team_anthems table
app.post('/api/anthem/:teamId', (req, res) => {
  anthemUpload.single('anthem')(req, res, async (err) => {
    if (err) return res.status(400).json({ error: err.message });
    if (!req.file) return res.status(400).json({ error: 'No MP3 file received' });
    const { teamId } = req.params;
    try {
      await pool.query(
        `INSERT INTO team_anthems (team_id, audio_data, mime_type, updated_at)
         VALUES ($1,$2,'audio/mpeg',NOW())
         ON CONFLICT (team_id) DO UPDATE
         SET audio_data=$2, updated_at=NOW()`,
        [teamId, req.file.buffer]
      );
      console.log(`[Anthem] Stored in DB for team ${teamId} (${req.file.size} bytes)`);
      res.json({ ok: true, teamId, size: req.file.size });
    } catch (e) {
      console.error('[Anthem] DB insert error:', e.message);
      res.status(500).json({ error: 'DB error' });
    }
  });
});

// Stream MP3 for a team from DB
app.get('/api/anthem/:teamId', async (req, res) => {
  const { teamId } = req.params;
  try {
    const { rows } = await pool.query(
      'SELECT audio_data, mime_type FROM team_anthems WHERE team_id=$1',
      [teamId]
    );
    if (!rows.length) return res.status(404).json({ error: 'No anthem' });
    const buf = rows[0].audio_data;
    res.setHeader('Content-Type', rows[0].mime_type || 'audio/mpeg');
    res.setHeader('Content-Length', buf.length);
    res.send(buf);
  } catch (e) {
    res.status(500).json({ error: 'DB error' });
  }
});

// Check if anthem exists for a team
app.get('/api/anthem/:teamId/exists', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT 1 FROM team_anthems WHERE team_id=$1',
      [req.params.teamId]
    );
    res.json({ exists: rows.length > 0 });
  } catch (e) {
    res.json({ exists: false });
  }
});

// Delete anthem for a team
app.delete('/api/anthem/:teamId', async (req, res) => {
  try {
    await pool.query('DELETE FROM team_anthems WHERE team_id=$1', [req.params.teamId]);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: 'DB error' });
  }
});

// Expose territory for all posters — in-memory + DB fallback
app.get('/api/territory', async (req, res) => {
  const result = {};
  // 1. In-memory rooms
  for (const [posterId, room] of Object.entries(posterRooms)) {
    if (room.territory && room.territory.dominant) {
      result[posterId] = room.territory;
    }
  }
  // 2. DB — posters not yet loaded into memory
  try {
    const { rows } = await pool.query(
      'SELECT poster_id, territory_json FROM territory_state WHERE dominant IS NOT NULL'
    );
    for (const row of rows) {
      if (!result[row.poster_id]) {
        result[row.poster_id] = JSON.parse(row.territory_json);
      }
    }
  } catch (e) { /* ignore */ }
  res.json(result);
});

app.post('/api/custom-posters/match', async (req, res) => {
  const { imageBase64 } = req.body;
  if (!imageBase64) return res.status(400).json({ error: 'imageBase64 required' });

  const ids = Object.keys(customPosters);
  if (ids.length === 0) return res.json({ posterId: null, confidence: 0 });

  try {
    const imgBuffer = Buffer.from(imageBase64, 'base64');
    const scanned = await Jimp.read(imgBuffer);
    scanned.resize(16, 16).grayscale();
    const sp = [];
    scanned.scan(0, 0, 16, 16, (x, y, idx) => sp.push(scanned.bitmap.data[idx]));

    let bestId = null;
    let bestScore = 0;

    for (const id of ids) {
      const filepath = path.join(CUSTOM_POSTERS_DIR, `${id}.jpg`);
      if (!fs.existsSync(filepath)) continue;
      try {
        const stored = await Jimp.read(filepath);
        stored.resize(16, 16).grayscale();
        const tp = [];
        stored.scan(0, 0, 16, 16, (x, y, idx) => tp.push(stored.bitmap.data[idx]));
        let diff = 0;
        for (let i = 0; i < sp.length; i++) diff += Math.abs(sp[i] - tp[i]);
        const score = 1 - diff / (sp.length * 255);
        if (score > bestScore) { bestScore = score; bestId = id; }
      } catch (e) { console.error(`Match error for ${id}:`, e); }
    }

    const THRESHOLD = 0.70;
    res.json({ posterId: bestScore >= THRESHOLD ? bestId : null, confidence: bestScore });
  } catch (e) {
    console.error('Match endpoint error:', e);
    res.status(500).json({ error: 'Image processing failed' });
  }
});

app.post('/api/custom-posters', async (req, res) => {
  const { name, description, imageBase64 } = req.body;
  if (!name || !imageBase64) {
    return res.status(400).json({ error: 'name and imageBase64 required' });
  }

  const customCount = Object.keys(customPosters).length + 1;
  const id = `custom_${customCount}`;
  const filename = `${id}.jpg`;
  const filepath = path.join(CUSTOM_POSTERS_DIR, filename);
  const imageUrl = `/custom-posters/${filename}`;

  const imgBuffer = Buffer.from(imageBase64, 'base64');
  fs.writeFileSync(filepath, imgBuffer);

  const posterEntry = { id, name, description: description || name, imageUrl, gridSize: 20, isCustom: true };
  customPosters[id] = posterEntry;
  POSTERS[id] = posterEntry;
  saveCustomPosters();

  // Persist to DB
  try {
    await pool.query(
      'INSERT INTO posters (id, name, description, image_url, grid_size, is_custom) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING',
      [id, name, description || name, imageUrl, 20, true]
    );
  } catch (e) { console.error('DB save poster error:', e); }

  console.log(`Custom poster added: ${id} - ${name}`);
  res.json(posterEntry);
});

app.get('/api/rooms/:posterId/state', (req, res) => {
  const { posterId } = req.params;
  const room = posterRooms[posterId];
  
  if (!room) {
    return res.json({
      posterId,
      strokes: [],
      territory: {},
      userCount: 0
    });
  }
  
  res.json({
    posterId,
    posterName: room.posterName,
    strokes: room.strokes,
    territory: room.territory,
    userCount: room.users.size,
    grid: room.grid
  });
});

// ============================================
// SOCKET.IO EVENTS
// ============================================

io.on('connection', (socket) => {
  console.log(`User connected: ${socket.id}`);
  
  let currentRoom = null;
  let currentUser = null;
  
  // Join a poster room
  socket.on('join_poster_room', async (data) => {
    const { posterId, userId, teamId, username } = data;
    
    // Validate poster
    if (!POSTERS[posterId]) {
      socket.emit('error', { message: 'Invalid poster ID' });
      return;
    }
    
    // Leave current room if any
    if (currentRoom) {
      socket.leave(currentRoom);
      const oldRoom = posterRooms[currentRoom];
      if (oldRoom) {
        oldRoom.users.delete(socket.id);
        io.to(currentRoom).emit('user_left', {
          socketId: socket.id,
          userId: currentUser?.userId,
          userCount: oldRoom.users.size
        });
      }
    }
    
    // Initialize room if needed (async — loads territory from DB)
    const room = await initPosterRoom(posterId);
    
    // Auto-assign a different team if the requested team is already taken by someone else
    const usedTeams = new Set(Array.from(room.users.values()).map(u => u.teamId));
    let assignedTeam = teamId;
    if (!assignedTeam || (usedTeams.has(assignedTeam) && usedTeams.size < Object.keys(TEAMS).length)) {
      const available = Object.keys(TEAMS).filter(t => !usedTeams.has(t));
      assignedTeam = available.length > 0
        ? available[0]
        : Object.keys(TEAMS)[Math.floor(Math.random() * Object.keys(TEAMS).length)];
    }

    // Create user
    currentUser = {
      socketId: socket.id,
      userId: userId || uuidv4(),
      teamId: assignedTeam,
      username: username || `User_${socket.id.slice(0, 4)}`,
      joinedAt: Date.now()
    };
    
    // Join room
    currentRoom = posterId;
    socket.join(posterId);
    room.users.set(socket.id, currentUser);
    
    // Send current state to user
    socket.emit('room_joined', {
      posterId,
      posterName: room.posterName,
      user: currentUser,
      strokes: room.strokes,
      territory: room.territory,
      userCount: room.users.size,
      users: Array.from(room.users.values())
    });
    
    // Notify others
    socket.to(posterId).emit('user_joined', {
      user: currentUser,
      userCount: room.users.size
    });
    
    console.log(`User ${currentUser.username} joined room ${posterId} as ${currentUser.teamId}`);
  });
  
  // Handle stroke data
  socket.on('send_stroke', (data) => {
    if (!currentRoom || !currentUser) {
      socket.emit('error', { message: 'Not in a room' });
      return;
    }
    
    const room = posterRooms[currentRoom];
    if (!room) return;
    
    const stroke = {
      id: uuidv4(),
      oderId: currentUser.userId,
      teamId: currentUser.teamId,
      points: data.points,
      color: data.color || TEAMS[currentUser.teamId]?.color || '#FFFFFF',
      size: data.size || 5,
      timestamp: Date.now(),
      isEraser: data.isEraser || false
    };
    
    // Store stroke
    room.strokes.push(stroke);
    
    // Limit stored strokes to prevent memory issues
    if (room.strokes.length > 1000) {
      room.strokes = room.strokes.slice(-500);
    }
    
    // Update territory grid
    if (!stroke.isEraser) {
      const territory = updateGridFromStroke(room, stroke);
      
      // Broadcast stroke and territory update
      io.to(currentRoom).emit('receive_stroke', stroke);
      io.to(currentRoom).emit('territory_update', territory);
    } else {
      io.to(currentRoom).emit('receive_stroke', stroke);
    }
  });
  
  // Handle drawing in progress (for real-time preview)
  socket.on('drawing_point', (data) => {
    if (!currentRoom || !currentUser) return;
    
    socket.to(currentRoom).emit('drawing_preview', {
      socketId: socket.id,
      userId: currentUser.userId,
      teamId: currentUser.teamId,
      point: data.point,
      color: data.color,
      size: data.size
    });
  });
  
  // Get current poster state
  socket.on('get_poster_state', (data) => {
    const { posterId } = data;
    const room = posterRooms[posterId];
    
    socket.emit('poster_state', {
      posterId,
      strokes: room ? room.strokes : [],
      territory: room ? room.territory : {},
      userCount: room ? room.users.size : 0
    });
  });
  
  // Clear canvas for everyone in the room
  socket.on('clear_canvas', () => {
    if (!currentRoom || !currentUser) return;
    const room = posterRooms[currentRoom];
    if (!room) return;

    room.strokes = [];
    const gridSize = room.grid.length;
    room.grid = Array(gridSize).fill(null).map(() => Array(gridSize).fill(null));
    room.territory = {};

    io.to(currentRoom).emit('canvas_cleared', {
      clearedBy: currentUser.username
    });
    console.log(`Canvas cleared in ${currentRoom} by ${currentUser.username}`);
  });

  // Leave room
  socket.on('leave_room', () => {
    if (currentRoom) {
      const room = posterRooms[currentRoom];
      if (room) {
        room.users.delete(socket.id);
        socket.to(currentRoom).emit('user_left', {
          socketId: socket.id,
          userId: currentUser?.userId,
          userCount: room.users.size
        });
      }
      socket.leave(currentRoom);
      currentRoom = null;
      currentUser = null;
    }
  });
  
  // Disconnect
  socket.on('disconnect', () => {
    console.log(`User disconnected: ${socket.id}`);
    
    if (currentRoom) {
      const room = posterRooms[currentRoom];
      if (room) {
        room.users.delete(socket.id);
        io.to(currentRoom).emit('user_left', {
          socketId: socket.id,
          userId: currentUser?.userId,
          userCount: room.users.size
        });
        
        // Clean up empty rooms after 5 minutes
        if (room.users.size === 0) {
          setTimeout(() => {
            if (posterRooms[currentRoom]?.users.size === 0) {
              delete posterRooms[currentRoom];
              console.log(`Room ${currentRoom} cleaned up`);
            }
          }, 5 * 60 * 1000);
        }
      }
    }
  });
});

// ============================================
// START SERVER
// ============================================

const PORT = process.env.PORT || 3000;

async function migrateAnthemsFromDisk() {
  const ANTHEMS_DIR = path.join(__dirname, '..', 'anthems');
  if (!fs.existsSync(ANTHEMS_DIR)) return;
  const files = fs.readdirSync(ANTHEMS_DIR).filter(f => f.endsWith('.mp3'));
  for (const file of files) {
    const teamId = path.basename(file, '.mp3');
    try {
      const { rows } = await pool.query('SELECT 1 FROM team_anthems WHERE team_id=$1', [teamId]);
      if (rows.length > 0) continue; // already in DB
      const buf = fs.readFileSync(path.join(ANTHEMS_DIR, file));
      await pool.query(
        `INSERT INTO team_anthems (team_id, audio_data, mime_type, updated_at)
         VALUES ($1,$2,'audio/mpeg',NOW())
         ON CONFLICT (team_id) DO UPDATE SET audio_data=$2, updated_at=NOW()`,
        [teamId, buf]
      );
      console.log(`[Anthem] Migrated ${file} → DB (${buf.length} bytes)`);
    } catch (e) {
      console.warn(`[Anthem] Migration failed for ${file}:`, e.message);
    }
  }
}

async function startServer() {
  try {
    await initDB();
    await loadCustomPostersFromDB();
    await migrateAnthemsFromDisk();
  } catch (e) {
    console.warn('DB init failed (continuing without DB):', e.message);
  }
  server.listen(PORT, '0.0.0.0', () => {
    console.log(`
╔════════════════════════════════════════════╗
║        iTEC OVERRIDE Backend v1.0          ║
║────────────────────────────────────────────║
║  Server running on port ${PORT}               ║
║  WebSocket ready for connections           ║
║  Neon PostgreSQL connected                 ║
║  ${Object.keys(POSTERS).length} posters configured                 ║
╚════════════════════════════════════════════╝
    `);
  });
}

startServer().catch(err => { console.error('Failed to start:', err); process.exit(1); });
