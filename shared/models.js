/**
 * Shared data models for iTEC OVERRIDE
 * These models define the data structures used across the app
 */

// Stroke data structure
const StrokeSchema = {
  id: 'string',        // Unique stroke ID
  oderId: 'string',     // User who made the stroke
  oderId: 'string',    // Team the user belongs to
  points: [            // Array of normalized points (0-1 range)
    { x: 'number', y: 'number' }
  ],
  color: 'string',     // Hex color code
  size: 'number',      // Brush size
  timestamp: 'number', // Unix timestamp
  isEraser: 'boolean'  // Whether this is an eraser stroke
};

// Poster data structure
const PosterSchema = {
  id: 'string',            // Unique poster ID (e.g., 'afis1')
  name: 'string',          // Display name
  gridSize: 'number',      // Territory grid size (default: 20)
  referenceImage: 'string' // Path to reference image
};

// User data structure
const UserSchema = {
  socketId: 'string',   // Socket.IO connection ID
  oderId: 'string',      // Unique user ID
  oderId: 'string',     // Current team
  username: 'string',   // Display name
  joinedAt: 'number'    // Timestamp when user joined
};

// Team data structure
const TeamSchema = {
  id: 'string',     // Team ID (red, blue, green, purple)
  name: 'string',   // Display name
  color: 'string'   // Hex color code
};

// Territory data structure
const TerritorySchema = {
  teams: {
    // teamId: { cells: number, percentage: number, color: string }
  },
  dominant: 'string', // Team with most territory
  total: 'number'     // Total grid cells
};

// Room state
const RoomStateSchema = {
  posterId: 'string',
  posterName: 'string',
  users: [],           // Array of User objects
  strokes: [],         // Array of Stroke objects
  grid: [],            // 2D array of team IDs (territory)
  territory: {},       // Territory object
  lastUpdate: 'number' // Last update timestamp
};

// Socket events
const SocketEvents = {
  // Client -> Server
  JOIN_POSTER_ROOM: 'join_poster_room',
  SEND_STROKE: 'send_stroke',
  DRAWING_POINT: 'drawing_point',
  GET_POSTER_STATE: 'get_poster_state',
  LEAVE_ROOM: 'leave_room',
  
  // Server -> Client
  ROOM_JOINED: 'room_joined',
  RECEIVE_STROKE: 'receive_stroke',
  TERRITORY_UPDATE: 'territory_update',
  USER_JOINED: 'user_joined',
  USER_LEFT: 'user_left',
  POSTER_STATE: 'poster_state',
  DRAWING_PREVIEW: 'drawing_preview',
  ERROR: 'error'
};

module.exports = {
  StrokeSchema,
  PosterSchema,
  UserSchema,
  TeamSchema,
  TerritorySchema,
  RoomStateSchema,
  SocketEvents
};
