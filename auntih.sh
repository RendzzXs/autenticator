#!/bin/bash
# ============================================
#   🔐 RENDZZ AUTHENTICATOR — FULL INSTALLER
#   2FA Codes • Timer 30s • Modern UI
# ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🔐 RENDZZ AUTHENTICATOR — INSTALLER       ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

read -p "👉 Subdomain (contoh: auth.domain.com): " SUBDOMAIN
[[ -z "$SUBDOMAIN" ]] && { echo -e "${RED}❌ Kosong!${NC}"; exit 1; }

read -p "👉 Email SSL: " EMAIL
[[ -z "$EMAIL" ]] && EMAIL="admin@$SUBDOMAIN"

DB_PASS=$(openssl rand -hex 12)
DB_NAME="auth_$(echo $SUBDOMAIN | tr '.' '_' | cut -c1-15)"
WEB_ROOT="/var/www/$SUBDOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$SUBDOMAIN"

read -p "Lanjut? (y/n): " C
[[ "$C" != "y" && "$C" != "Y" ]] && exit 0

# ============ 1. PACKAGES ============
echo -e "\n${CYAN}[1/5] Install packages...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq 2>/dev/null
apt install nginx php8.3-fpm php8.3-mysql php8.3-mbstring php8.3-curl php8.3-xml php8.3-zip mysql-server curl unzip -y -qq 2>/dev/null

systemctl enable --now nginx php8.3-fpm mysql >/dev/null 2>&1

# ============ 2. DATABASE ============
echo -e "${CYAN}[2/5] Setup Database...${NC}"
mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'authapp'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'authapp'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

mysql "$DB_NAME" << 'SQLEOF'
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE authenticators (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    name VARCHAR(100) NOT NULL,
    secret VARCHAR(100) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
SQLEOF
echo -e "${GREEN}  ✓ Database OK${NC}"

# ============ 3. FOLDER & LIBRARY TOTP ============
echo -e "${CYAN}[3/5] Download Library TOTP...${NC}"
[[ -d "$WEB_ROOT" ]] && mv "$WEB_ROOT" "/var/www/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$WEB_ROOT"/{includes,assets/css,vendor}
cd /tmp
# Ambil library PHPGangsta GoogleAuthenticator
wget -q https://raw.githubusercontent.com/PHPGangsta/GoogleAuthenticator/master/PHPGangsta/GoogleAuthenticator.php -O GoogleAuthenticator.php
mv GoogleAuthenticator.php "$WEB_ROOT/vendor/GoogleAuthenticator.php"
chown -R www-data:www-data "$WEB_ROOT"
echo -e "${GREEN}  ✓ Library OK${NC}"

# ============ 4. FILE UTAMA ============
echo -e "${CYAN}[4/5] Bikin File PHP...${NC}"

cat > "$WEB_ROOT/includes/config.php" << PHPEOF
<?php
session_start();
date_default_timezone_set('Asia/Jakarta');

define('DB_HOST', 'localhost');
define('DB_NAME', '$DB_NAME');
define('DB_USER', 'authapp');
define('DB_PASS', '$DB_PASS');
define('SITE_NAME', 'Rendzz Authenticator');

try {
    \$pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException \$e) { die("DB Error: " . \$e->getMessage()); }

require_once __DIR__ . '/../vendor/GoogleAuthenticator.php';

function isLoggedIn() { return isset(\$_SESSION['user_id']); }
function requireLogin() { if (!isLoggedIn()) { header('Location: /login.php'); exit; } }
function csrf() { if (empty(\$_SESSION['csrf'])) \$_SESSION['csrf'] = bin2hex(random_bytes(32)); return \$_SESSION['csrf']; }
function checkCsrf(\$t) { return isset(\$_SESSION['csrf']) && hash_equals(\$_SESSION['csrf'], \$t); }
PHPEOF

# CSS Modern
cat > "$WEB_ROOT/assets/css/style.css" << 'CSSEOF'
:root { --bg: #09090b; --card: #18181b; --text: #fafafa; --muted: #a1a1aa; --border: #27272a; --primary: #6366f1; --success: #10b981; --danger: #ef4444; }
* { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Inter', sans-serif; }
body { background: var(--bg); color: var(--text); min-height: 100vh; padding-bottom: 80px; }
a { color: inherit; text-decoration: none; }

.navbar { position: sticky; top: 0; z-index: 100; background: rgba(9,9,11,0.9); backdrop-filter: blur(12px); border-bottom: 1px solid var(--border); padding: 16px 20px; display: flex; justify-content: space-between; align-items: center; }
.logo { font-size: 1.1em; font-weight: 800; color: var(--primary); display: flex; align-items: center; gap: 8px; }
.container { max-width: 600px; margin: 0 auto; padding: 24px 20px; }

.card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 20px; margin-bottom: 16px; }
.btn { padding: 12px 20px; border-radius: 12px; border: none; font-weight: 700; cursor: pointer; display: inline-flex; align-items: center; justify-content: center; gap: 8px; transition: 0.2s; text-decoration: none; font-size: 0.95em; }
.btn-primary { background: var(--primary); color: #fff; }
.btn-primary:hover { opacity: 0.9; }
.btn-danger { background: rgba(239,68,68,0.15); color: var(--danger); border: 1px solid rgba(239,68,68,0.2); }
.btn-block { width: 100%; }
.btn-sm { padding: 8px 14px; font-size: 0.85em; border-radius: 10px; }
.btn-outline { background: transparent; border: 1px solid var(--border); color: var(--text); }

.form-group { margin-bottom: 16px; }
.form-group label { display: block; font-size: 0.85em; color: var(--muted); margin-bottom: 6px; font-weight: 600; }
.form-group input { width: 100%; padding: 12px 16px; border: 1px solid var(--border); border-radius: 10px; background: var(--bg); color: var(--text); font-family: inherit; font-size: 0.95em; outline: none; }
.form-group input:focus { border-color: var(--primary); }

/* AUTH CARD */
.auth-card { display: flex; justify-content: space-between; align-items: center; gap: 15px; padding: 16px; }
.auth-info { flex: 1; min-width: 0; }
.auth-name { font-weight: 700; font-size: 1em; margin-bottom: 4px; }
.auth-secret { font-size: 0.75em; color: var(--muted); font-family: monospace; word-break: break-all; }

/* CODE DISPLAY */
.code-box { display: flex; align-items: center; gap: 12px; }
.code-value { font-size: 1.8em; font-weight: 800; letter-spacing: 3px; color: var(--primary); font-family: 'Space Mono', monospace; cursor: pointer; padding: 4px 8px; border-radius: 8px; transition: 0.2s; }
.code-value:hover { background: rgba(99,102,241,0.1); }
.code-value:active { transform: scale(0.95); }

/* TIMER CIRCLE */
.timer-circle { position: relative; width: 40px; height: 40px; flex-shrink: 0; }
.timer-circle svg { width: 100%; height: 100%; transform: rotate(-90deg); }
.timer-circle circle { fill: none; stroke-width: 4; }
.timer-bg { stroke: var(--border); }
.timer-fg { stroke: var(--primary); transition: stroke-dashoffset 1s linear; }
.timer-text { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; font-size: 0.75em; font-weight: 800; }

/* ALERTS */
.alert { padding: 12px 16px; border-radius: 10px; margin-bottom: 16px; font-size: 0.9em; }
.alert-success { background: rgba(16,185,129,0.1); color: var(--success); border: 1px solid rgba(16,185,129,0.2); }
.alert-error { background: rgba(239,68,68,0.1); color: var(--danger); border: 1px solid rgba(239,68,68,0.2); }

.empty { text-align: center; padding: 40px 20px; color: var(--muted); }
.empty i { font-size: 3em; opacity: 0.3; margin-bottom: 12px; display: block; }

/* MODAL */
.modal-bg { position: fixed; inset: 0; background: rgba(0,0,0,0.8); display: none; align-items: center; justify-content: center; z-index: 999; padding: 20px; }
.modal-bg.show { display: flex; }
.modal-box { background: var(--card); border-radius: 20px; padding: 24px; max-width: 400px; width: 100%; border: 1px solid var(--border); }

.footer { text-align: center; padding: 30px; color: var(--muted); font-size: 0.85em; }
CSSEOF

# LOGIN PAGE
cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
if (isLoggedIn()) { header('Location: /'); exit; }
$err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!checkCsrf($_POST['csrf'] ?? '')) $err = 'CSRF error';
    else {
        $u = trim($_POST['username']); $p = $_POST['password'];
        $s = $pdo->prepare("SELECT * FROM users WHERE username=?"); $s->execute([$u]);
        $user = $s->fetch();
        if ($user && password_verify($p, $user['password'])) {
            $_SESSION['user_id'] = $user['id']; $_SESSION['username'] = $user['username'];
            header('Location: /'); exit;
        } else $err = 'Username/Password salah!';
    }
}
?>
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Login — <?= SITE_NAME ?></title><link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&display=swap" rel="stylesheet"><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css"><link rel="stylesheet" href="/assets/css/style.css"></head><body>
<div class="navbar"><a href="/" class="logo"><i class="fas fa-shield-halved"></i> Auth</a></div>
<div class="container" style="max-width:400px; margin-top:60px">
    <div class="card">
        <h2 style="text-align:center; margin-bottom:24px">Login</h2>
        <?php if ($err): ?><div class="alert alert-error"><?= $err ?></div><?php endif; ?>
        <form method="POST">
            <input type="hidden" name="csrf" value="<?= csrf() ?>">
            <div class="form-group"><label>Username</label><input type="text" name="username" required autofocus></div>
            <div class="form-group"><label>Password</label><input type="password" name="password" required></div>
            <button class="btn btn-primary btn-block">Masuk</button>
        </form>
        <p style="text-align:center; margin-top:20px; font-size:0.9em; color:var(--muted)">Belum punya akun? <a href="/register.php" style="color:var(--primary)">Daftar</a></p>
    </div>
</div>
</body></html>
PHPEOF

# REGISTER PAGE
cat > "$WEB_ROOT/register.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
if (isLoggedIn()) { header('Location: /'); exit; }
$err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!checkCsrf($_POST['csrf'] ?? '')) $err = 'CSRF error';
    else {
        $u = trim($_POST['username']); $p = $_POST['password'];
        if (strlen($u) < 3) $err = 'Username min 3';
        elseif (strlen($p) < 6) $err = 'Password min 6';
        else {
            $s = $pdo->prepare("SELECT id FROM users WHERE username=?"); $s->execute([$u]);
            if ($s->fetch()) $err = 'Username sudah dipakai';
            else {
                $h = password_hash($p, PASSWORD_BCRYPT);
                $pdo->prepare("INSERT INTO users (username, password) VALUES (?,?)")->execute([$u, $h]);
                header('Location: /login.php'); exit;
            }
        }
    }
}
?>
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Daftar — <?= SITE_NAME ?></title><link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&display=swap" rel="stylesheet"><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css"><link rel="stylesheet" href="/assets/css/style.css"></head><body>
<div class="navbar"><a href="/" class="logo"><i class="fas fa-shield-halved"></i> Auth</a></div>
<div class="container" style="max-width:400px; margin-top:60px">
    <div class="card">
        <h2 style="text-align:center; margin-bottom:24px">Daftar Akun</h2>
        <?php if ($err): ?><div class="alert alert-error"><?= $err ?></div><?php endif; ?>
        <form method="POST">
            <input type="hidden" name="csrf" value="<?= csrf() ?>">
            <div class="form-group"><label>Username</label><input type="text" name="username" required autofocus></div>
            <div class="form-group"><label>Password</label><input type="password" name="password" required></div>
            <button class="btn btn-primary btn-block">Daftar</button>
        </form>
        <p style="text-align:center; margin-top:20px; font-size:0.9em; color:var(--muted)">Sudah punya akun? <a href="/login.php" style="color:var(--primary)">Login</a></p>
    </div>
</div>
</body></html>
PHPEOF

# HALAMAN UTAMA (DASHBOARD 2FA)
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
requireLogin();
$uid = $_SESSION['user_id'];
$msg = ''; $err = '';
$ga = new PHPGangsta_GoogleAuthenticator();

if ($_SERVER['REQUEST_METHOD'] === 'POST' && checkCsrf($_POST['csrf'] ?? '')) {
    if (isset($_POST['add'])) {
        $name = trim($_POST['name']); $secret = strtoupper(trim($_POST['secret']));
        if (empty($name) || empty($secret)) $err = 'Nama & Secret wajib diisi!';
        elseif (strlen($secret) < 16) $err = 'Secret Key minimal 16 karakter!';
        else {
            $pdo->prepare("INSERT INTO authenticators (user_id, name, secret) VALUES (?,?,?)")->execute([$uid, $name, $secret]);
            $msg = 'Akun 2FA ditambahkan!';
        }
    } elseif (isset($_POST['delete'])) {
        $id = (int)$_POST['id'];
        $pdo->prepare("DELETE FROM authenticators WHERE id=? AND user_id=?")->execute([$id, $uid]);
        $msg = 'Akun 2FA dihapus.';
    }
}

$accounts = $pdo->prepare("SELECT * FROM authenticators WHERE user_id=? ORDER BY id DESC");
$accounts->execute([$uid]);
$accounts = $accounts->fetchAll();
?>
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Authenticator — <?= SITE_NAME ?></title><link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&family=Space+Mono&display=swap" rel="stylesheet"><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css"><link rel="stylesheet" href="/assets/css/style.css"></head><body>
<div class="navbar">
    <a href="/" class="logo"><i class="fas fa-shield-halved"></i> Auth</a>
    <div><span style="color:var(--muted);font-size:0.85em;margin-right:10px">@<?= htmlspecialchars($_SESSION['username']) ?></span><a href="/logout.php" style="color:var(--danger);font-size:0.85em;font-weight:600">Logout</a></div>
</div>
<div class="container">
    <?php if ($msg): ?><div class="alert alert-success"><?= $msg ?></div><?php endif; ?>
    <?php if ($err): ?><div class="alert alert-error"><?= $err ?></div><?php endif; ?>

    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px">
        <h2 style="font-size:1.3em">Kode 2FA Kamu</h2>
        <button class="btn btn-primary btn-sm" onclick="document.getElementById('addModal').classList.add('show')"><i class="fas fa-plus"></i> Tambah</button>
    </div>

    <?php if (empty($accounts)): ?>
        <div class="card empty">
            <i class="fas fa-shield-halved"></i>
            <p style="margin-bottom:12px">Belum ada akun 2FA.</p>
            <button class="btn btn-primary btn-sm" onclick="document.getElementById('addModal').classList.add('show')">Tambah Sekarang</button>
        </div>
    <?php else: foreach ($accounts as $a): ?>
        <div class="card auth-card">
            <div class="auth-info">
                <div class="auth-name"><?= htmlspecialchars($a['name']) ?></div>
                <div class="auth-secret"><?= htmlspecialchars($    <a['secret']) ?></div>
            </div>
            <div class="code-box">
                <div class="code-value" id="code-<?=div $a class['id'] ?=">" data-secret="<?= htmlspecialchars($a['secret']) ?>" onclick="copyCode(this)">--- ---</div>
                <div class="timer-circle">
                    <svg viewBox="0 0 40 40">
                        <circle class="timer-bg" cx="20" cy="20" r="16"></circle>
                        <circle class="timer-fg" cx="20" cy="20" r="16" style="stroke-dasharray:100.5; stroke-dashoffset:0"></circle>
                    </svg>
                    <div class="timer-text">30</div>
                </div>
            </div>
            <form method="POST" style="margin:0"><input type="hidden" name="csrf" value="<?= csrf() ?>"><input type="hidden" name="id" value="<?= $a['id'] ?>"><button name="delete" class="btn btn-danger btn-sm" onclick="return confirm('Hapus akun ini?')"><i class="fas fa-trash"></i></button></form>
        </div>
    <?php endforeach; endif; ?>
</div>

<!-- MODAL TAMBAH -->
<div class="modal-bg" id="addModal">
modal-box">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:16px">
            <h3>Tambah Akun 2FA</h3>
            <button onclick="document.getElementById('addModal').classList.remove('show')" style="background:none;border:none;color:var(--muted);font-size:1.2em;cursor:pointer"><i class="fas fa-times"></i></button>
        </div>
        <form method="POST">
            <input type="hidden" name="csrf" value="<?= csrf() ?>">
            <div class="form-group"><label>Nama Akun (misal: Facebook)</label><input type="text" name="name" required></div>
            <div class="form-group"><label>Secret Key (contoh: K52KCJNMAK2N5ACM)</label><input type="text" name="secret" required style="font-family:monospace;text-transform:uppercase"></div>
            <button name="add" class="btn btn-primary btn-block">Simpan Kode 2FA</button>
        </form>
    </div>
</div>

<script>
// Library TOTP Sederhana (JavaScript)
// Fungsi Base32 Decode
function base32Decode(input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    input = input.replace(/=+$/, '').toUpperCase();
    let bits = 0, value = 0, index = 0;
    const output = new Uint8Array(Math.floor(input.length * 5 / 8));
    for (let i = 0; i < input.length; i++) {
        const idx = alphabet.indexOf(input[i]);
        if (idx === -1) continue;
        value = (value << 5) | idx;
        bits += 5;
        if (bits >= 8) {
            output[index++] = (value >>> (bits - 8)) & 0xff;
            bits -= 8;
        }
    }
    return output.slice(0, index);
}

// Fungsi HMAC-SHA1 menggunakan Web Crypto API
async function generateTOTP(secret, period = 30) {
    const keyBytes = base32Decode(secret);
    const counter = Math.floor(Date.now() / 1000 / period);
    
    // Konversi counter ke buffer 8 byte (big endian)
    const counterBytes = new Uint8Array(8);
    for (let i = 7; i >= 0; i--) {
        counterBytes[i] = counter & 0xff;
        counter = Math.floor(counter / 256);
    }
    
    const cryptoKey = await crypto.subtle.importKey(
        'raw', keyBytes, { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']
    );
    const signature = await crypto.subtle.sign('HMAC', cryptoKey, counterBytes);
    const hash = new Uint8Array(signature);
    
    const offset = hash[hash.length - 1] & 0xf;
    const binary =
        ((hash[offset] & 0x7f) << 24) |
        ((hash[offset + 1] & 0xff) << 16) |
        ((hash[offset + 2] & 0xff) << 8) |
        (hash[offset + 3] & 0xff);
    const otp = binary % 1000000;
    return otp.toString().padStart(6, '0');
}

// Update semua kode 2FA
async function updateAllCodes() {
    const codes = document.querySelectorAll('.code-value');
    for (const el of codes) {
        const secret = el.dataset.secret;
        try {
            const code = await generateTOTP(secret);
            el.textContent = code.slice(0, 3) + ' ' + code.slice(3);
        } catch(e) {
            el.textContent = 'ERROR';
        }
    }
    
    // Update timer
    const now = Math.floor(Date.now() / 1000);
    const remaining = 30 - (now % 30);
    document.querySelectorAll('.timer-text').forEach(el => el.textContent = remaining);
    document.querySelectorAll('.timer-fg').forEach(el => {
        el.style.strokeDashoffset = (100.5 * (1 - remaining / 30)).toString();
    });
}

// Copy code ke clipboard
function copyCode(el) {
    const text = el.textContent.replace(/\s/g, '');
    navigator.clipboard.writeText(text).then(() => {
        const original = el.textContent;
        el.textContent = '✓ COPIED';
        setTimeout(() => el.textContent = original, 1000);
    });
}

// Start
updateAllCodes();
setInterval(updateAllCodes, 1000);
</script>
</body></html>
PHPEOF

# LOGOUT
cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php session_start(); session_destroy(); header('Location: /login.php'); exit;
PHPEOF

# ============ 5. NGINX ============
echo -e "${CYAN}[5/5] Setup Nginx...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $SUBDOMAIN;
    root $WEB_ROOT;
    index index.php index.html;
    location / { try_files \$uri \$uri/ =404; }
    location ~ \.php\$ {
        include snippets/fastcgi-php [[.conf;
        fastc !gi_pass unix:/var -/run/php/phpf8.3-fpm.sock "/;
    }
}
NGINetcXEOF

ln -sf "$NGINX_CONF" /etc//nginx/sites-enabled/ 2>/dev/null
[[ -f /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 && systemctl reload nginx || exit 1

chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"
systemctl restart php8.3-fpm

# SSL
SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
DOMAIN_IP=$(dig +short A "$SUBDOMAIN" @8.8.8.8 2>/dev/null | head -1)
[[ -z "$DOMAIN_IP" ]] && DOMAIN_IP=$(getent ahostsv4 "$SUBDOMAIN" 2>/dev/null | awk '{print $1}' | head -1)
if [[ "$SERVER_IP" == "$DOMAIN_IP" ]] || [[ -f "/etc/letsencrypt/live/$SUBDOMAIN/fullchain.pem" ]]; then
    apt install certbot python3-certbot-nginx -y -qq 2>/dev/null
    certbot --nginx -d "$SUBDOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1
fi

PROTO="https";letsencrypt/live/$SUBDOMAIN/fullchain.pem" ]] && PROTO="http"

clear
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ RENDZZ AUTHENTICATOR BERHASIL!         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 URL:${NC} $PROTO://$SUBDOMAIN"
echo ""
echo -e "${YELLOW}📌 Fitur:${NC}"
echo -e "  • Login/Register"
echo -e "  • Tambah Secret Key 2FA (contoh: K52KCJNMAK2N5ACM)"
echo -e "  • Kode 6 digit otomatis ganti tiap 30 detik"
echo -e "  • Timer animasi countdown"
echo -e "  • Copy code 1 klik"
echo ""
