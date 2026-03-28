/**
 * QR Code Generator for iTEC OVERRIDE Posters
 * 
 * This script generates QR codes for each poster that can be printed
 * and attached to physical posters for easy scanning.
 * 
 * Usage: node generate_qr_codes.js
 * 
 * Prerequisites: npm install qrcode
 */

const QRCode = require('qrcode');
const fs = require('fs');
const path = require('path');

const posters = [
  { id: 'afis1', name: 'Social Presence' },
  { id: 'afis2', name: 'Digital Marketing' },
  { id: 'afis3', name: 'Tech Innovation' },
  { id: 'afis4', name: 'Creative Design' },
  { id: 'afis5', name: 'Cloud Computing' },
  { id: 'afis6', name: 'AI Revolution' },
  { id: 'afis7', name: 'Cyber Security' },
  { id: 'afis8', name: 'Data Science' },
  { id: 'afis9', name: 'Mobile Future' },
  { id: 'afis10', name: 'Web3 World' }
];

const outputDir = path.join(__dirname, '..', 'qr_codes');

async function generateQRCodes() {
  // Create output directory
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }
  
  console.log('🎨 Generating QR codes for iTEC OVERRIDE posters...\n');
  
  for (const poster of posters) {
    const qrContent = `ITEC_${poster.id.toUpperCase()}`;
    const filename = `qr_${poster.id}.png`;
    const filepath = path.join(outputDir, filename);
    
    try {
      await QRCode.toFile(filepath, qrContent, {
        width: 300,
        margin: 2,
        color: {
          dark: '#00D4FF',  // Neon cyan
          light: '#0A0A0F'  // Dark background
        }
      });
      
      console.log(`✅ Generated: ${filename} (${poster.name})`);
      console.log(`   Content: ${qrContent}\n`);
    } catch (error) {
      console.error(`❌ Error generating ${filename}:`, error.message);
    }
  }
  
  // Generate HTML page with all QR codes for easy printing
  const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <title>iTEC OVERRIDE - QR Codes</title>
  <style>
    body {
      background: #0A0A0F;
      color: #00D4FF;
      font-family: 'Courier New', monospace;
      padding: 20px;
    }
    h1 {
      text-align: center;
      text-shadow: 0 0 10px #00D4FF;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
      gap: 20px;
      max-width: 1200px;
      margin: 0 auto;
    }
    .card {
      background: #12121A;
      border: 1px solid #00D4FF;
      border-radius: 10px;
      padding: 15px;
      text-align: center;
      box-shadow: 0 0 10px rgba(0, 212, 255, 0.3);
    }
    .card img {
      width: 150px;
      height: 150px;
    }
    .card h3 {
      margin: 10px 0 5px;
      color: #FF0080;
    }
    .card p {
      margin: 5px 0;
      font-size: 12px;
      color: #888;
    }
    .instructions {
      max-width: 800px;
      margin: 20px auto;
      padding: 20px;
      background: #12121A;
      border: 1px solid #9D00FF;
      border-radius: 10px;
    }
  </style>
</head>
<body>
  <h1>🎨 iTEC OVERRIDE - QR Codes</h1>
  
  <div class="instructions">
    <h2>📋 Instructions</h2>
    <ol>
      <li>Print these QR codes</li>
      <li>Attach each QR code to its corresponding poster</li>
      <li>Users scan the QR code to join the poster's battle</li>
    </ol>
  </div>
  
  <div class="grid">
    ${posters.map(poster => `
      <div class="card">
        <img src="qr_${poster.id}.png" alt="${poster.name}">
        <h3>${poster.name}</h3>
        <p>ID: ${poster.id}</p>
        <p>QR: ITEC_${poster.id.toUpperCase()}</p>
      </div>
    `).join('')}
  </div>
</body>
</html>
  `;
  
  fs.writeFileSync(path.join(outputDir, 'index.html'), htmlContent);
  console.log('📄 Generated: index.html (printable page with all QR codes)\n');
  console.log(`✨ All QR codes saved to: ${outputDir}`);
}

generateQRCodes().catch(console.error);
