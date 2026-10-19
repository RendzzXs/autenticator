#!/bin/bash
# ============================================
#   🔐 RENDZZ AUTH + GMAIL CHECKER
# ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🔐 RENDZZ AUTH + GMAIL CHECKER            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

read -p "👉 Subdomain (contoh: auth.domain.com): " SUBDOMAIN
WEB_ROOT="/var/www/$SUBDOMAIN"

[[ ! -d "$WEB_ROOT" ]] && { echo -e "${RED}❌ Folder tidak ada: $WEB_ROOT${NC}"; exit 1; }

# ============ 1. PASTIKAN FOLDER API ADA ============
mkdir -p "$WEB_ROOT/api"

# ============ 2. BUAT API GMAIL CHECKER ============
echo -e "${CYAN}[1/3] Bikin API Gmail Checker...${NC}"

cat > "$WEB_ROOT/api/check_gmail.php" << 'PHPEOF'
<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

// Ambil input email (bisa 1 atau banyak sekaligus)
$input = json_decode(file_get_contents('php://input'), true);
$emails = $input['emails'] ?? [];

if (empty($emails)) {
    echo json_encode(['ok' => false, 'error' => 'Tidak ada email yang dikirim']);
    exit;
}

if (count($emails) > 50) {
    echo json_encode(['ok' => false, 'error' => 'Maksimal 50 email per scan!']);
    exit;
}

$results = [];

foreach ($emails as $email) {
    $email = trim($email);
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $results[] = ['email' => $email, 'status' => 'invalid', 'message' => 'Format salah'];
        continue;
    }

    // Gunakan SMTP Socket untuk cek apakah email valid (tanpa kirim email)
    $domain = substr(strrchr($email, "@"), 1);
    
    // Cek MX Record dulu
    if (!checkdnsrr($domain, "MX")) {
        $results[] = ['email' => $email, 'status' => 'invalid', 'message' => 'Domain tidak valid'];
        continue;
    }

    // Ambil MX Record
    getmxrr($domain, $mxHosts);
    if (empty($mxHosts)) {
        $results[] = ['email' => $email, 'status' => 'invalid', 'message' => 'MX Record tidak ditemukan'];
        continue;
    }

    $mxHost = $mxHosts[0];
    $port = 25;
    $timeout = 5;

    // Koneksi ke server SMTP Gmail
    $smtp = @fsockopen($mxHost, $port, $errno, $errstr, $timeout);
    if (!$smtp) {
        $results[] = ['email' => $email, 'status' => 'unknown', 'message' => 'Gagal konek ke server SMTP'];
        continue;
    }

    // Baca greeting
    fgets($smtp, 512);
    
    // Kirim EHLO
    fwrite($smtp, "EHLO " . $_SERVER['HTTP_HOST'] . "\r\n");
    while ($line = fgets($smtp, 512)) {
        if (substr($line, 3, 1) == " ") break;
    }

    // Kirim MAIL FROM
    fwrite($smtp, "MAIL FROM:<checker@" . $_SERVER['HTTP_HOST'] . ">\r\n");
    fgets($smtp, 512);

    // Kirim RCPT TO (ini inti pengecekan)
    fwrite($smtp, "RCPT TO:<" . $email . ">\r\n");
    $response = fgets($smtp, 512);
    
    fwrite($smtp, "QUIT\r\n");
    fclose($smtp);

    // Analisa response code
    $code = substr($response, 0, 3);
    if ($code == "250" || $code == "251") {
        $results[] = ['email' => $email, 'status' => 'valid', 'message' => 'Email Aktif'];
    } elseif ($code == "550" || $code == "551" || $code == "553") {
        $results[] = ['email' => $email, 'status' => 'invalid', 'message' => 'Email Tidak Terdaftar (Die)'];
    } else {
        $results[] = ['email' => $email, 'status' => 'unknown', 'message' => 'Tidak bisa diverifikasi (Code: ' . trim($response) . ')'];
    }
}

echo json_encode(['ok' => true, 'results' => $results]);
PHPEOF

echo -e "${GREEN}  ✓ API Gmail Checker siap${NC}"

# ============ 3. UPDATE HALAMAN GMAIL CHECKER ============
echo -e "${CYAN}[2/3] Bikin Halaman UI Gmail Checker...${NC}"

cat > "$WEB_ROOT/gmail-checker.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
requireLogin();
?>
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Gmail Checker — <?= SITE_NAME ?></title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&family=Space+Mono&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link rel="stylesheet" href="/assets/css/style.css">
<style>
    .result-item {
        background: rgba(0,0,0,0.2);
        border: 1px solid var(--glass-border);
        border-radius: 12px;
        padding: 15px;
        margin-bottom: 10px;
        display: flex;
        justify-content: space-between;
        align-items: center;
        animation: slideDown 0.3s;
    }
    .result-email { font-weight: 600; font-size: 0.95em; word-break: break-all; }
    .result-msg { font-size: 0.8em; color: var(--muted); margin-top: 3px; }
    .badge-valid { background: rgba(16,185,129,0.15); color: var(--success); border: 1px solid rgba(16,185,129,0.3); padding: 4px 10px; border-radius: 20px; font-size: 0.75em; font-weight: 800; text-transform: uppercase; }
    .badge-invalid { background: rgba(239,68,68,0.15); color: var(--danger); border: 1px solid rgba(239,68,68,0.3); padding: 4px 10px; border-radius: 20px; font-size: 0.75em; font-weight: 800; text-transform: uppercase; }
    .badge-unknown { background: rgba(245,158,11,0.15); color: #f59e0b; border: 1px solid rgba(245,158,11,0.3); padding: 4px 10px; border-radius: 20px; font-size: 0.75em; font-weight: 800; text-transform: uppercase; }
    @keyframes slideDown { from { opacity: 0; transform: translateY(-10px); } to { opacity: 1; transform: translateY(0); } }
    .loader-circle { width: 40px; height: 40px; border: 4px solid var(--glass-border); border-top-color: var(--primary); border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto; }
    @keyframes spin { to { transform: rotate(360deg); } }
</style>
</head>
<body>
<div class="navbar">
    <a href="/" class="logo"><i class="fas fa-shield-halved"></i> Auth</a>
    <div class="nav-right">
        <span class="user-badge"><i class="fas fa-user"></i> @<?= htmlspecialchars($_SESSION['username']) ?></span>
        <a href="/logout.php" class="btn btn-danger btn-sm" title="Logout"><i class="fas fa-sign-out-alt"></i></a>
    </div>
</div>

<div class="container">
    <div class="card">
        <div style="display:flex; align-items:center; gap:12px; margin-bottom:20px">
            <div style="width:50px;height:50px;border-radius:14px;background:linear-gradient(135deg,#ef4444,#b91c1c);display:flex;align-items:center;justify-content:center;font-size:1.5em;color:#fff">
                <i class="fas fa-envelope-circle-check"></i>
            </div>
            <div>
                <h2 style="font-size:1.3em;margin:0">Gmail Checker</h2>
                <p style="color:var(--muted);font-size:0.85em;margin:0">Cek valid/die email secara realtime</p>
            </div>
        </div>

        <div class="form-group">
            <label><i class="fas fa-list"></i> Daftar Email (Maks 50, 1 baris = 1 email)</label>
            <textarea id="emailList" rows="6" style="width:100%;padding:14px 16px;border:1px solid var(--glass-border);border-radius:12px;background:rgba(0,0,0,0.3);color:var(--text);font-family:'Space Mono',monospace;font-size:0.9em;outline:none;resize:vertical" placeholder="contoh1@gmail.com
contoh2@gmail.com
contoh3@gmail.com"></textarea>
        </div>

        <div style="display:flex; gap:10px">
            <button class="btn btn-primary" style="flex:1" onclick="startCheck()"><i class="fas fa-search"></i> Mulai Scan</button>
            <button class="btn btn-outline" onclick="clearAll()"><i class="fas fa-trash"></i></button>
        </div>
    </div>

    <div id="resultBox" style="display:none">
        <div class="card" style="padding:15px; margin-bottom:15px; display:flex; justify-content:space-between; align-items:center">
            <div>
                <div style="font-size:0.85em;color:var(--muted)">Hasil Scan</div>
                <div style="font-size:1.2em;font-weight:800" id="summary">0 Valid / 0 Die / 0 Unknown</div>
            </div>
            <button class="btn btn-outline btn-sm" onclick="copyResults()"><i class="fas fa-copy"></i> Copy</button>
        </div>
        <div id="resultsList"></div>
    </div>
</div>

<script>
async function startCheck() {
    const raw = document.getElementById('emailList').value;
    const emails = raw.split('\n').map(e => e.trim()).filter(e => e.length > 0);
    
    if (emails.length === 0) {
        alert('Masukkan minimal 1 email!');
        return;
    }
    if (emails.length > 50) {
        alert('Maksimal 50 email per scan!');
        return;
    }

    const btn = event.target;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Scanning...';

    document.getElementById('resultBox').style.display = 'block';
    document.getElementById('resultsList').innerHTML = '<div class="card" style="text-align:center;padding:40px"><div class="loader-circle"></div><p style="margin-top:15px;color:var(--muted)">Memeriksa ' + emails.length + ' email...</p></div>';

    try {
        const res = await fetch('/api/check_gmail.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ emails: emails })
        });
        const data = await res.json();

        if (!data.ok) throw new Error(data.error || 'Gagal scan');

        let valid = 0, invalid = 0, unknown = 0;
        let html = '';
        let copyText = '';

        data.results.forEach(r => {
            let badge = '';
            if (r.status === 'valid') { badge = '<span class="badge-valid"><i class="fas fa-check"></i> Valid</span>'; valid++; }
            else if (r.status === 'invalid') { badge = '<span class="badge-invalid"><i class="fas fa-times"></i> Die</span>'; invalid++; }
            else { badge = '<span class="badge-unknown"><i class="fas fa-question"></i> Unknown</span>'; unknown++; }

            html += `
                <div class="result-item">
                    <div>
                        <div class="result-email">${escapeHtml(r.email)}</div>
                        <div class="result-msg">${escapeHtml(r.message)}</div>
                    </div>
                    ${badge}
                </div>
            `;
            copyText += `${r.email} | ${r.status.toUpperCase()} | ${r.message}\n`;
        });

        document.getElementById('resultsList').innerHTML = html;
        document.getElementById('summary').textContent = `${valid} Valid / ${invalid} Die / ${unknown} Unknown`;
        window._copyText = copyText;

    } catch(e) {
        document.getElementById('resultsList').innerHTML = `<div class="card" style="text-align:center;padding:30px;color:var(--danger)"><i class="fas fa-exclamation-triangle" style="font-size:2em;margin-bottom:10px"></i><p>${e.message}</p></div>`;
    }

    btn.disabled = false;
    btn.innerHTML = '<i class="fas fa-search"></i> Mulai Scan';
}

function clearAll() {
    document.getElementById('emailList').value = '';
    document.getElementById('resultBox').style.display = 'none';
}

function copyResults() {
    if (!window._copyText) return;
    navigator.clipboard.writeText(window._copyText).then(() => {
        alert('✅ Hasil berhasil dicopy!');
    });
}

function escapeHtml(text) {
    const d = document.createElement('div');
    d.textContent = text;
    return d.innerHTML;
}
</script>
</body>
</html>
PHPEOF

# ============ 4. UPDATE NAVBAR (Tambah Tombol Gmail Checker) ============
echo -e "${CYAN}[3/3] Update Navbar...${NC}"

# Modifikasi file index.php untuk tambah tombol di atas
if ! grep -q "Gmail Checker" "$WEB_ROOT/index.php"; then
    # Insert tombol di navbar (sebelum div user-badge)
    sed -i 's|<div class="nav-right">|<div class="nav-right"><a href="/gmail-checker.php" class="btn btn-sm btn-outline" style="border-color:rgba(239,68,68,0.3);color:#ef4444"><i class="fas fa-envelope-circle-check"></i> Gmail Checker</a>|' "$WEB_ROOT/index.php"
fi

# Fix permission
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"
systemctl restart php8.3-fpm

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ GMAIL CHECKER BERHASIL DITAMBAHKAN!    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 URL:${NC} https://$SUBDOMAIN"
echo -e "${CYAN}📧 Gmail Checker:${NC} https://$SUBDOMAIN/gmail-checker.php"
echo ""
echo -e "${YELLOW}⚠️  Catatan:${NC}"
echo -e "  • Google kadang memblokir port 25 (SMTP)."
echo -e "  • Kalau hasilnya 'Unknown' semua, kemungkinan VPS kamu kena blokir port 25."
echo -e "  • Solusi: Hubungi provider VPS untuk buka port 25, atau pakai API berbayar."
