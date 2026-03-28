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
const { pool, initDB } = require('./db');

const JWT_SECRET = process.env.JWT_SECRET || 'itec_override_secret_2025';

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

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
    for (const row of rows) {
      const entry = { id: row.id, name: row.name, description: row.description, imageUrl: row.image_url, gridSize: row.grid_size, isCustom: true };
      customPosters[row.id] = entry;
      POSTERS[row.id] = entry;
    }
    console.log(`Loaded ${rows.length} custom posters from DB`);
  } catch (e) { console.error('DB load posters error:', e); }
}

// In-memory state for each poster room
const posterRooms = {};

// Initialize a poster room
function initPosterRoom(posterId) {
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
  socket.on('join_poster_room', (data) => {
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
    
    // Initialize room if needed
    const room = initPosterRoom(posterId);
    
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

async function startServer() {
  try {
    await initDB();
    await loadCustomPostersFromDB();
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
