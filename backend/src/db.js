const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      email VARCHAR(255) UNIQUE NOT NULL,
      username VARCHAR(100) UNIQUE NOT NULL,
      password_hash VARCHAR(255) NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS posters (
      id VARCHAR(50) PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      description TEXT,
      image_url TEXT,
      grid_size INTEGER DEFAULT 20,
      is_custom BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS stickers (
      id VARCHAR(50) PRIMARY KEY,
      prompt TEXT NOT NULL,
      creator_id VARCHAR(100),
      image_base64 TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS map_pins (
      poster_id VARCHAR(50) PRIMARY KEY,
      x DOUBLE PRECISION NOT NULL,
      y DOUBLE PRECISION NOT NULL,
      z DOUBLE PRECISION NOT NULL,
      nx DOUBLE PRECISION DEFAULT 0,
      ny DOUBLE PRECISION DEFAULT 1,
      nz DOUBLE PRECISION DEFAULT 0,
      created_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS territory_state (
      poster_id VARCHAR(50) PRIMARY KEY,
      grid_json  TEXT NOT NULL,
      territory_json TEXT NOT NULL,
      dominant   VARCHAR(50),
      updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS team_anthems (
      team_id    VARCHAR(50) PRIMARY KEY,
      audio_data BYTEA NOT NULL,
      mime_type  VARCHAR(50) DEFAULT 'audio/mpeg',
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);
  console.log('DB schema ready');
}

module.exports = { pool, initDB };
