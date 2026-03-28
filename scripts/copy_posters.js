/**
 * Copy poster images to Flutter assets folder
 * 
 * Usage: node copy_posters.js
 */

const fs = require('fs');
const path = require('path');

const sourceDir = path.join(__dirname, '..', 'images');
const targetDir = path.join(__dirname, '..', 'mobile_app', 'assets', 'posters');

function copyPosters() {
  console.log('📁 Copying poster images to Flutter assets...\n');
  
  // Ensure target directory exists
  if (!fs.existsSync(targetDir)) {
    fs.mkdirSync(targetDir, { recursive: true });
  }
  
  // Get all PNG files from source
  const files = fs.readdirSync(sourceDir).filter(f => f.endsWith('.png'));
  
  for (const file of files) {
    const sourcePath = path.join(sourceDir, file);
    const targetPath = path.join(targetDir, file);
    
    try {
      fs.copyFileSync(sourcePath, targetPath);
      console.log(`✅ Copied: ${file}`);
    } catch (error) {
      console.error(`❌ Error copying ${file}:`, error.message);
    }
  }
  
  console.log(`\n✨ Done! ${files.length} poster(s) copied to: ${targetDir}`);
}

copyPosters();
