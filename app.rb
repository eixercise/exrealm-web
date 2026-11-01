# app.rb - EiXercise Realm Full-Stack CMS & Community Portal
require 'sinatra'
require 'sqlite3'
require 'securerandom'
require 'digest'

set :bind, '0.0.0.0'
set :port, 4567
enable :sessions
set :session_secret, SecureRandom.hex(32)

# ==========================================
# 1. INISIALISASI DATABASE & AUTO-SEED CMS
# ==========================================
DB = SQLite3::Database.new("eixercise.db")
DB.results_as_hash = true

DB.execute_batch <<-SQL
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE,
    password TEXT,
    role TEXT DEFAULT 'member',
    tickets INTEGER DEFAULT 3,
    title TEXT DEFAULT 'Realm Citizen'
  );

  CREATE TABLE IF NOT EXISTS posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
    category TEXT,
    content TEXT,
    author TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS gacha_pool (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_name TEXT,
    rarity TEXT,
    weight INTEGER
  );

  CREATE TABLE IF NOT EXISTS draw_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT,
    item_name TEXT,
    rarity TEXT,
    verify_hash TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS tournaments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    game TEXT,
    status TEXT,
    champion TEXT DEFAULT 'Belum Ditentukan'
  );
SQL

# Seed Data Awal jika Database masih kosong
if DB.get_first_value("SELECT COUNT(*) FROM users") == 0
  DB.execute("INSERT INTO users (username, password, role, tickets, title) VALUES (?, ?, ?, ?, ?)", 
             ['Founder_Ei', 'admin123', 'admin', 99, 'Eternal Sovereign'])
  DB.execute("INSERT INTO users (username, password, role, tickets, title) VALUES (?, ?, ?, ?, ?)", 
             ['Chief_Villager', 'mod123', 'moderator', 25, 'Town Hall Elder'])
  DB.execute("INSERT INTO users (username, password, role, tickets, title) VALUES (?, ?, ?, ?, ?)", 
             ['Vergil_Slayer', 'member123', 'member', 5, 'Ascendant Knight'])

  DB.execute("INSERT INTO posts (title, category, content, author) VALUES (?, ?, ?, ?)",
             ['Manifesto Phoenix Hitam-Ungu: Legacy Abadi', 'Legacy Lore', 'EiXercise Realm dibangun bukan untuk satu masa, melainkan sebagai warisan abadi yang akan terus menyala melintasi generasi.', 'Founder_Ei'])
  DB.execute("INSERT INTO posts (title, category, content, author) VALUES (?, ?, ?, ?)",
             ['Grand Tournament Catur & MLBB Season I Dibuka!', 'Turnamen', 'Siapkan strategi terbaikmu di papan catur maupun Land of Dawn. Pendaftaran dibuka di Member Dashboard.', 'Chief_Villager'])

  DB.execute("INSERT INTO gacha_pool (item_name, rarity, weight) VALUES ('Crest of Black-Purple Phoenix (Mythic)', 'SSR - Gold', 5)")
  DB.execute("INSERT INTO gacha_pool (item_name, rarity, weight) VALUES ('Engulfing Lightning - Raiden Blessing', 'SR - Purple', 15)")
  DB.execute("INSERT INTO gacha_pool (item_name, rarity, weight) VALUES ('Yamato Dark Slayer Pass (DMC)', 'SR - Purple', 20)")
  DB.execute("INSERT INTO gacha_pool (item_name, rarity, weight) VALUES ('Clan War Elixir Chest (CoC)', 'R - Obsidian', 60)")

  DB.execute("INSERT INTO tournaments (name, game, status, champion) VALUES ('Grandmaster Sovereign Cup', 'Chess Online (Lichess Arena)', 'Pendaftaran Dibuka', 'Menunggu Pertandingan')")
  DB.execute("INSERT INTO tournaments (name, game, status, champion) VALUES ('Electro Abyssal Cup 5v5', 'Mobile Legends: Bang Bang', 'Berlangsung', 'Menunggu Pertandingan')")
  DB.execute("INSERT INTO tournaments (name, game, status, champion) VALUES ('Town Hall 16 Clan War', 'Clash of Clans', 'Selesai', 'Squad RaidenVanguard')")
end

# ==========================================
# 2. HELPER AUTENTIKASI & ROLE GUARD
# ==========================================
helpers do
  def current_user
    return nil unless session[:user_id]
    DB.get_first_row("SELECT * FROM users WHERE id = ?", [session[:user_id]])
  end

  def require_role(*roles)
    user = current_user
    if user.nil? || !roles.include?(user['role'])
      session[:flash] = "Akses Ditolak! Halaman tersebut membutuhkan otoritas: #{roles.join(' / ').upcase}."
      redirect '/'
    end
  end
end

# ==========================================
# 3. ROUTES: LANDING PAGE & AUTH
# ==========================================
get '/' do
  @posts = DB.execute("SELECT * FROM posts ORDER BY id DESC LIMIT 6")
  @tournaments = DB.execute("SELECT * FROM tournaments ORDER BY id DESC")
  @recent_draws = DB.execute("SELECT * FROM draw_logs ORDER BY id DESC LIMIT 5")
  erb :index
end

# Simulasi Quick-Switch Role (Memudahkan testing Admin/Mod/Member)
post '/quick-login/:role' do
  user = DB.get_first_row("SELECT * FROM users WHERE role = ?", [params[:role]])
  if user
    session[:user_id] = user['id']
    session[:flash] = "Berhasil masuk sebagai #{user['username']} (Role: #{user['role'].upcase})"
  end
  redirect "/#{params[:role]}"
end

post '/login' do
  user = DB.get_first_row("SELECT * FROM users WHERE username = ? AND password = ?", [params[:username], params[:password]])
  if user
    session[:user_id] = user['id']
    redirect "/#{user['role']}"
  else
    session[:flash] = "Username atau Password salah!"
    redirect '/'
  end
end

get '/logout' do
  session.clear
  redirect '/'
end

# ==========================================
# 4. ROUTES: MEMBER PAGE (Draw & Arena)
# ==========================================
get '/member' do
  require_role('member', 'moderator', 'admin')
  @my_draws = DB.execute("SELECT * FROM draw_logs WHERE username = ? ORDER BY id DESC LIMIT 10", [current_user['username']])
  @tournaments = DB.execute("SELECT * FROM tournaments")
  erb :member
end

# Server-Side RNG Roll (Anti Inspect-Element Cheat)
post '/member/roll' do
  require_role('member', 'moderator', 'admin')
  user = current_user
  if user['tickets'] <= 0
    session[:flash] = "Tiket Draw kamu habis! Hubungi Moderator/Admin saat event berlangsung."
    redirect '/member'
  end

  pool = DB.execute("SELECT * FROM gacha_pool")
  total_weight = pool.sum { |item| item['weight'] }
  random_pick = SecureRandom.random_number(total_weight) + 1

  selected_item = nil
  current_weight = 0
  pool.each do |item|
    current_weight += item['weight']
    if random_pick <= current_weight
      selected_item = item
      break
    end
  end

  verify_hash = Digest::SHA256.hexdigest("#{user['username']}-#{selected_item['item_name']}-#{Time.now.to_f}-#{SecureRandom.hex(4)}")[0..15]

  DB.execute("UPDATE users SET tickets = tickets - 1 WHERE id = ?", [user['id']])
  DB.execute("INSERT INTO draw_logs (username, item_name, rarity, verify_hash) VALUES (?, ?, ?, ?)",
             [user['username'], selected_item['item_name'], selected_item['rarity'], verify_hash])

  session[:flash] = "DRAW BERHASIL! Kamu mendapatkan: [#{selected_item['rarity']}] #{selected_item['item_name']} (Hash: ##{verify_hash})"
  redirect '/member'
end

# ==========================================
# 5. ROUTES: MODERATOR PAGE (Town Hall CMS)
# ==========================================
get '/moderator' do
  require_role('moderator', 'admin')
  @posts = DB.execute("SELECT * FROM posts ORDER BY id DESC")
  @tournaments = DB.execute("SELECT * FROM tournaments ORDER BY id DESC")
  @users = DB.execute("SELECT id, username, role, tickets, title FROM users")
  erb :moderator
end

post '/moderator/post' do
  require_role('moderator', 'admin')
  DB.execute("INSERT INTO posts (title, category, content, author) VALUES (?, ?, ?, ?)",
             [params[:title], params[:category], params[:content], current_user['username']])
  session[:flash] = " Berita / Event baru berhasil diterbitkan ke halaman utama!"
  redirect '/moderator'
end

post '/moderator/tournament/update' do
  require_role('moderator', 'admin')
  DB.execute("UPDATE tournaments SET status = ?, champion = ? WHERE id = ?",
             [params[:status], params[:champion], params[:id]])
  session[:flash] = "Data Turnamen berhasil diperbarui!"
  redirect '/moderator'
end

post '/moderator/grant-ticket' do
  require_role('moderator', 'admin')
  DB.execute("UPDATE users SET tickets = tickets + ? WHERE username = ?", [params[:amount].to_i, params[:username]])
  session[:flash] = "Berhasil menambahkan #{params[:amount]} Tiket Draw ke #{params[:username]}!"
  redirect '/moderator'
end

# ==========================================
# 6. ROUTES: ADMIN PAGE (Plane of Euthymia)
# ==========================================
get '/admin' do
  require_role('admin')
  @users = DB.execute("SELECT * FROM users")
  @gacha_pool = DB.execute("SELECT * FROM gacha_pool")
  @posts = DB.execute("SELECT * FROM posts ORDER BY id DESC")
  @tournaments = DB.execute("SELECT * FROM tournaments")
  erb :admin
end

post '/admin/user/role' do
  require_role('admin')
  DB.execute("UPDATE users SET role = ?, title = ? WHERE id = ?", [params[:role], params[:title], params[:user_id]])
  session[:flash] = "Otoritas & Gelar pengguna berhasil diubah!"
  redirect '/admin'
end

post '/admin/gacha/add' do
  require_role('admin')
  DB.execute("INSERT INTO gacha_pool (item_name, rarity, weight) VALUES (?, ?, ?)",
             [params[:item_name], params[:rarity], params[:weight].to_i])
  session[:flash] = "Item baru berhasil dimasukkan ke Pool Undian!"
  redirect '/admin'
end

post '/admin/tournament/add' do
  require_role('admin')
  DB.execute("INSERT INTO tournaments (name, game, status) VALUES (?, ?, ?)",
             [params[:name], params[:game], params[:status]])
  session[:flash] = "Turnamen baru berhasil dibuka!"
  redirect '/admin'
end

post '/admin/post/delete/:id' do
  require_role('admin')
  DB.execute("DELETE FROM posts WHERE id = ?", [params[:id]])
  session[:flash] = "Postingan CMS telah dihapus."
  redirect '/admin'
end

__END__

@@ layout
<!DOCTYPE html>
<html lang="id" class="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>EiXercise Realm — Legacy of the Obsidian Phoenix</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@600;800&family=Plus+Jakarta+Sans:wght@400;600;700&display=swap" rel="stylesheet">
  <style>
    body {
      background-color: #07060b;
      color: #e2e8f0;
      font-family: 'Plus Jakarta Sans', sans-serif;
      background-image: radial-gradient(circle at 50% 0%, rgba(107, 33, 168, 0.22), transparent 60%),
                        radial-gradient(circle at 90% 80%, rgba(212, 175, 55, 0.1), transparent 50%);
    }
    .font-royal { font-family: 'Cinzel', serif; }
    .gold-gradient {
      background: linear-gradient(135deg, #fde047 0%, #d4af37 50%, #aa771c 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .border-gold-glow {
      border: 1px solid rgba(212, 175, 55, 0.35);
      box-shadow: 0 0 20px rgba(147, 51, 234, 0.15);
    }
    .bg-obsidian { background: rgba(16, 14, 24, 0.85); backdrop-filter: blur(12px); }
  </style>
</head>
<body class="min-h-screen flex flex-col justify-between">

  <!-- NAVBAR -->
  <nav class="sticky top-0 z-50 bg-obsidian border-b border-purple-900/60 px-6 py-4">
    <div class="max-w-7xl mx-auto flex flex-wrap justify-between items-center gap-4">
      <a href="/" class="flex items-center gap-3 group">
        <div class="w-10 h-10 rounded-full bg-gradient-to-br from-purple-700 via-black to-amber-500 p-0.5 flex items-center justify-center shadow-lg shadow-purple-600/30">
          <span class="text-xl">🐦‍⬛</span>
        </div>
        <div>
          <span class="font-royal text-xl font-extrabold tracking-wider gold-gradient">EIXERCISE REALM</span>
          <span class="block text-[10px] uppercase tracking-widest text-purple-400">Phoenix Eternal Legacy</span>
        </div>
      </a>

      <!-- Navigasi & Panel Quick-Switch Role -->
      <div class="flex flex-wrap items-center gap-3 text-sm">
        <a href="/" class="px-3 py-1.5 rounded hover:text-amber-400 transition">Beranda</a>
        <a href="/member" class="px-3 py-1.5 rounded bg-purple-950/60 border border-purple-700/50 text-purple-200 hover:border-amber-400 transition">⚡ Member Area</a>
        <a href="/moderator" class="px-3 py-1.5 rounded bg-purple-950/60 border border-purple-700/50 text-purple-200 hover:border-amber-400 transition">🛡️ Mod Town Hall</a>
        <a href="/admin" class="px-3 py-1.5 rounded bg-amber-950/50 border border-amber-500/50 text-amber-300 hover:bg-amber-900/40 transition">👑 Admin Shogunate</a>

        <!-- Simulasi Ganti Role 1-Klik -->
        <div class="flex items-center gap-1 bg-black/60 px-2 py-1 rounded border border-gray-800">
          <span class="text-[11px] text-gray-400 mr-1">Demo Role:</span>
          <form action="/quick-login/member" method="POST" class="inline"><button class="text-xs px-2 py-0.5 rounded bg-gray-800 hover:bg-purple-700 text-gray-200">Member</button></form>
          <form action="/quick-login/moderator" method="POST" class="inline"><button class="text-xs px-2 py-0.5 rounded bg-purple-900 hover:bg-purple-600 text-purple-200">Mod</button></form>
          <form action="/quick-login/admin" method="POST" class="inline"><button class="text-xs px-2 py-0.5 rounded bg-amber-700 hover:bg-amber-500 text-black font-bold">Admin</button></form>
        </div>
      </div>
    </div>
  </nav>

  <!-- FLASH NOTIFICATION -->
  <% if session[:flash] %>
    <div class="max-w-7xl mx-auto mt-4 px-6 w-full">
      <div class="bg-gradient-to-r from-purple-950 via-black to-amber-950 border border-amber-500/60 text-amber-200 px-4 py-3 rounded-lg flex justify-between items-center shadow-lg">
        <span>✨ <%= session[:flash] %></span>
        <% session[:flash] = nil %>
      </div>
    </div>
  <% end %>

  <!-- KONTEN UTAMA -->
  <main class="flex-grow max-w-7xl w-full mx-auto px-6 py-8">
    <%= yield %>
  </main>

  <!-- FOOTER -->
  <footer class="border-t border-purple-900/40 bg-black/80 py-8 px-6 text-center text-xs text-gray-400">
    <p class="font-royal text-sm gold-gradient font-bold mb-1">IGNIS AETERNUM — THE BLACK-PURPLE PHOENIX</p>
    <p>"Meskipun sang pendiri telah tiada, EiXercise Realm akan tetap berdiri dan dilanjutkan oleh generasi berikutnya."</p>
    <p class="mt-3 text-gray-600">eixercise.my.id • Powered by Ruby Sinatra CMS • Obsidian, Electro Purple & Royal Gold</p>
  </footer>

</body>
</html>

@@ index
<!-- HERO SECTION: BLACK/PURPLE PHOENIX & RAIDEN EI -->
<section class="relative rounded-2xl overflow-hidden border-gold-glow bg-obsidian p-8 md:p-12 mb-12">
  <div class="grid md:grid-cols-12 gap-8 items-center">
    <div class="md:col-span-7 space-y-5">
      <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-purple-950/90 border border-amber-500/40 text-amber-300 text-xs uppercase tracking-widest">
        <span>🐦‍⬛ Simbol Legacy Abadi</span>
      </div>
      <h1 class="font-royal text-4xl md:text-6xl font-extrabold leading-tight">
        <span class="text-white">THE ETERNAL</span><br>
        <span class="gold-gradient">EIXERCISE REALM</span>
      </h1>
      <p class="text-gray-300 leading-relaxed text-base md:text-lg">
        Di bawah sayap <strong class="text-purple-400">Phoenix Hitam-Ungu</strong> dan otoritas abadi <strong class="text-amber-400">Raiden Shogun (Ei)</strong>, realm ini dirancang sebagai rumah lintas generasi. Tempat berkumpulnya para grandmaster catur, klan strategi, dan petarung arena.
      </p>
      <div class="flex flex-wrap gap-4 pt-2">
        <a href="/member" class="px-6 py-3 rounded-lg font-bold text-black bg-gradient-to-r from-amber-400 via-yellow-500 to-amber-600 hover:brightness-110 transition shadow-lg shadow-amber-500/20">
          🎲 Masuk Altar Undian (Draw/Roll)
        </a>
        <a href="#arena" class="px-6 py-3 rounded-lg font-semibold text-purple-200 bg-purple-950/80 border border-purple-500/50 hover:border-amber-400 transition">
          ♟️ Lihat Turnamen Catur & Game
        </a>
      </div>
    </div>

    <!-- PHOENIX LEGACY CREST CARD -->
    <div class="md:col-span-5 bg-gradient-to-b from-purple-950/50 via-black to-black p-6 rounded-xl border border-amber-500/40 text-center space-y-4">
      <div class="w-24 h-24 mx-auto rounded-full bg-gradient-to-tr from-purple-900 via-black to-amber-500 p-1 flex items-center justify-center shadow-2xl shadow-purple-600/50">
        <span class="text-5xl">🐦‍⬛</span>
      </div>
      <h3 class="font-royal text-xl font-bold gold-gradient">SUMPAH PHOENIX UNGU</h3>
      <p class="text-xs text-gray-300 italic leading-relaxed">
        "Api hitam dan ungu tidak pernah padam. Saat pencipta awal beristirahat, takhta dan panji EiXercise akan diwariskan kepada penjaga generasi selanjutnya."
      </p>
      <div class="grid grid-cols-3 gap-2 pt-2 border-t border-purple-900/50 text-xs">
        <div><span class="block text-amber-400 font-bold">UNDIAN</span><span class="text-gray-400">Anti-Cheat RNG</span></div>
        <div><span class="block text-purple-400 font-bold">ARENA</span><span class="text-gray-400">Catur & MOBA</span></div>
        <div><span class="block text-amber-400 font-bold">LEGACY</span><span class="text-gray-400">Lintas Generasi</span></div>
      </div>
    </div>
  </div>
</section>

<!-- PANTHEON KARAKTER PENJAGA REALM -->
<section class="mb-12">
  <div class="flex items-center justify-between mb-6">
    <div>
      <h2 class="font-royal text-2xl md:text-3xl font-bold gold-gradient">PANTHEON PENJAGA REALM</h2>
      <p class="text-sm text-gray-400">Lima pilar karakter yang mewakili divisi dan filosofi EiXercise Realm</p>
    </div>
  </div>

  <div class="grid sm:grid-cols-2 lg:grid-cols-5 gap-4">
    <!-- 1. Phoenix -->
    <div class="bg-obsidian p-5 rounded-xl border border-purple-800/60 hover:border-amber-400 transition flex flex-col justify-between">
      <div>
        <span class="text-xs px-2 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/40">Simbol Utama</span>
        <h3 class="font-royal text-lg font-bold text-white mt-3">Obsidian Phoenix</h3>
        <p class="text-xs text-purple-400 mb-2">Immortal Legacy</p>
        <p class="text-xs text-gray-400">Jiwa abadi komunitas. Melambangkan regenerasi kepemimpinan agar server tetap hidup selamanya.</p>
      </div>
      <div class="mt-4 pt-3 border-t border-gray-800 text-[11px] text-amber-400 font-semibold">🔥 Core Identity</div>
    </div>

    <!-- 2. Raiden Shogun / Ei -->
    <div class="bg-obsidian p-5 rounded-xl border border-purple-800/60 hover:border-amber-400 transition flex flex-col justify-between">
      <div>
        <span class="text-xs px-2 py-0.5 rounded bg-purple-500/20 text-purple-300 border border-purple-500/40">Genshin Impact</span>
        <h3 class="font-royal text-lg font-bold text-white mt-3">Raiden Shogun (Ei)</h3>
        <p class="text-xs text-purple-400 mb-2">Her Excellency, Ogosho</p>
        <p class="text-xs text-gray-400">Penguasa Plane of Euthymia. Memegang kendali tertinggi atas sistem Admin dan hukum keabadian Realm.</p>
      </div>
      <div class="mt-4 pt-3 border-t border-gray-800 text-[11px] text-purple-300 font-semibold">⚡ Admin Sovereign</div>
    </div>

    <!-- 3. Clash of Clans Villager & Archer Queen -->
    <div class="bg-obsidian p-5 rounded-xl border border-purple-800/60 hover:border-amber-400 transition flex flex-col justify-between">
      <div>
        <span class="text-xs px-2 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/40">Clash of Clans</span>
        <h3 class="font-royal text-lg font-bold text-white mt-3">Maiden & Queen</h3>
        <p class="text-xs text-purple-400 mb-2">Town Hall Overseer</p>
        <p class="text-xs text-gray-400">Sang gadis desa & Archer Queen yang mengatur pembangunan markas, distribusi tiket, dan jadwal Moderator.</p>
      </div>
      <div class="mt-4 pt-3 border-t border-gray-800 text-[11px] text-amber-400 font-semibold">🏰 Moderator Hub</div>
    </div>

    <!-- 4. Devil May Cry - Vergil -->
    <div class="bg-obsidian p-5 rounded-xl border border-purple-800/60 hover:border-amber-400 transition flex flex-col justify-between">
      <div>
        <span class="text-xs px-2 py-0.5 rounded bg-purple-500/20 text-purple-300 border border-purple-500/40">Devil May Cry</span>
        <h3 class="font-royal text-lg font-bold text-white mt-3">Vergil (The Alpha)</h3>
        <p class="text-xs text-purple-400 mb-2">Grandmaster of Focus</p>
        <p class="text-xs text-gray-400">Penjaga turnamen Catur & strategi. Menuntut presisi mutlak layaknya tebasan Yamato di setiap langkah.</p>
      </div>
      <div class="mt-4 pt-3 border-t border-gray-800 text-[11px] text-purple-300 font-semibold">♟️ Chess & Arena</div>
    </div>

    <!-- 5. Mobile Legends - Valentina / Lunox -->
    <div class="bg-obsidian p-5 rounded-xl border border-purple-800/60 hover:border-amber-400 transition flex flex-col justify-between">
      <div>
        <span class="text-xs px-2 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/40">Mobile Legends</span>
        <h3 class="font-royal text-lg font-bold text-white mt-3">Valentina & Lunox</h3>
        <p class="text-xs text-purple-400 mb-2">Mistress of Fate & Chaos</p>
        <p class="text-xs text-gray-400">Penjaga Altar Undian (Draw/Roll) serta pelindung divisi turnamen kompetitif 5v5 Land of Dawn.</p>
      </div>
      <div class="mt-4 pt-3 border-t border-gray-800 text-[11px] text-amber-400 font-semibold">🎲 Mystic Draw & MOBA</div>
    </div>
  </div>
</section>

<!-- ARENA TURNAMEN & BERITA CMS -->
<div id="arena" class="grid md:grid-cols-12 gap-8">
  <!-- Pengumuman CMS -->
  <div class="md:col-span-7 space-y-4">
    <h2 class="font-royal text-2xl font-bold gold-gradient">📜 DEKRIT & BERITA REALM (CMS)</h2>
    <% @posts.each do |post| %>
      <div class="bg-obsidian p-5 rounded-xl border border-purple-900/60">
        <div class="flex justify-between items-center text-xs text-amber-400 mb-1">
          <span class="uppercase font-bold px-2 py-0.5 rounded bg-purple-950 border border-purple-700"><%= post['category'] %></span>
          <span class="text-gray-500">Oleh: <%= post['author'] %></span>
        </div>
        <h3 class="text-lg font-bold text-white mt-2"><%= post['title'] %></h3>
        <p class="text-sm text-gray-300 mt-1"><%= post['content'] %></p>
      </div>
    <% end %>
  </div>

  <!-- Live Turnamen & Log Undian -->
  <div class="md:col-span-5 space-y-6">
    <div class="bg-obsidian p-6 rounded-xl border-gold-glow">
      <h2 class="font-royal text-xl font-bold gold-gradient mb-4">♟️ PAPAN TURNAMEN AKTIF</h2>
      <div class="space-y-3">
        <% @tournaments.each do |t| %>
          <div class="p-3 rounded-lg bg-black/60 border border-purple-900/50 flex justify-between items-center">
            <div>
              <h4 class="font-bold text-sm text-white"><%= t['name'] %></h4>
              <p class="text-xs text-purple-400"><%= t['game'] %></p>
              <p class="text-[11px] text-gray-400 mt-1">🏆 Juara: <span class="text-amber-300"><%= t['champion'] %></span></p>
            </div>
            <span class="text-xs px-2.5 py-1 rounded-full bg-purple-900/70 text-amber-300 border border-amber-500/30"><%= t['status'] %></span>
          </div>
        <% end %>
      </div>
    </div>

    <div class="bg-obsidian p-6 rounded-xl border border-purple-900/60">
      <h2 class="font-royal text-xl font-bold text-purple-300 mb-3">🎲 LOG UNDIAN (LIVE DRAW)</h2>
      <div class="space-y-2 text-xs">
        <% if @recent_draws.empty? %>
          <p class="text-gray-500">Belum ada riwayat undian. Jadilah yang pertama di Member Area!</p>
        <% else %>
          <% @recent_draws.each do |d| %>
            <div class="p-2.5 rounded bg-black/50 border border-gray-800 flex justify-between">
              <span><strong class="text-amber-400"><%= d['username'] %></strong> memperoleh <span class="text-purple-300"><%= d['item_name'] %></span></span>
              <span class="text-gray-500 font-mono">#<%= d['verify_hash'][0..5] %></span>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
  </div>
</div>

@@ member
<!-- MEMBER PAGE: ALTAR UNDIAN & LOBBY CATUR -->
<div class="space-y-8">
  <div class="bg-obsidian p-6 rounded-2xl border-gold-glow flex flex-wrap justify-between items-center gap-4">
    <div>
      <span class="text-xs uppercase tracking-widest text-purple-400">Member Sanctum • Citizen Portal</span>
      <h1 class="font-royal text-3xl font-bold gold-gradient">Selamat Datang, <%= current_user['username'] %></h1>
      <p class="text-sm text-gray-400">Gelar Realm: <strong class="text-white"><%= current_user['title'] %></strong> | Hak Akses: <span class="uppercase text-amber-400"><%= current_user['role'] %></span></p>
    </div>
    <div class="bg-black/80 px-6 py-4 rounded-xl border border-amber-500/50 text-center">
      <span class="block text-xs text-gray-400">Tiket Event Undian (Draw)</span>
      <span class="font-royal text-3xl font-extrabold text-amber-400">🎟️ <%= current_user['tickets'] %></span>
    </div>
  </div>

  <div class="grid md:grid-cols-2 gap-8">
    <!-- FITUR 1: ALTAR GACHA / ROLL (LUNOX & VALENTINA) -->
    <div class="bg-obsidian p-6 rounded-2xl border border-purple-700/60 space-y-4">
      <div class="flex justify-between items-center">
        <h2 class="font-royal text-xl font-bold gold-gradient">🎲 ALTAR UNDIAN (SERVER-SIDE RNG)</h2>
        <span class="text-xs text-purple-300">Penjaga: Valentina & Ei</span>
      </div>
      <p class="text-xs text-gray-300 leading-relaxed">
        Setiap kali kamu menekan tombol Roll, angka acak dihitung langsung di server Ruby menggunakan algoritma kriptografi <code>SecureRandom</code> dan menghasilkan kode Hash SHA-256 yang tidak bisa dimanipulasi lewat browser.
      </p>
      <form action="/member/roll" method="POST">
        <button type="submit" class="w-full py-4 rounded-xl font-royal font-extrabold text-lg text-black bg-gradient-to-r from-amber-400 via-yellow-500 to-amber-600 hover:brightness-110 transition shadow-xl shadow-amber-500/20">
          ⚡ TARIK UNDIAN SEKARANG (1 TIKET)
        </button>
      </form>

      <div class="pt-4 border-t border-gray-800">
        <h3 class="text-xs font-bold uppercase text-purple-400 mb-2">Riwayat Undian Pribadimu:</h3>
        <div class="space-y-2 max-h-48 overflow-y-auto text-xs">
          <% @my_draws.each do |log| %>
            <div class="p-2.5 rounded bg-black/70 border border-purple-900/40 flex justify-between items-center">
              <div>
                <span class="px-1.5 py-0.5 rounded bg-purple-900 text-amber-300 font-bold mr-1"><%= log['rarity'] %></span>
                <span class="text-white"><%= log['item_name'] %></span>
              </div>
              <span class="font-mono text-[10px] text-gray-500">Hash: #<%= log['verify_hash'] %></span>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <!-- FITUR 2: ARENA CATUR & MINIGAME ONLINE (VERGIL) -->
    <div class="bg-obsidian p-6 rounded-2xl border border-purple-700/60 space-y-4">
      <div class="flex justify-between items-center">
        <h2 class="font-royal text-xl font-bold gold-gradient">♟️ ARENA CATUR & TURNAMEN</h2>
        <span class="text-xs text-purple-300">Overseer: Vergil (DMC)</span>
      </div>
      <p class="text-xs text-gray-300">
        Papan catur latihan interaktif terintegrasi langsung dengan Lichess Embed. Untuk pertandingan turnamen resmi, klik tombol Room Turnamen di bawah.
      </p>
      <!-- Embed Live Chess Puzzle / Board dari Lichess (Gratis & Bebas Iklan) -->
      <div class="rounded-xl overflow-hidden border border-amber-500/40 bg-black flex justify-center">
        <iframe src="https://lichess.org/training/frame?theme=purple&bg=dark" style="width: 100%; height: 320px;" allowtransparency="true" frameborder="0"></iframe>
      </div>
    </div>
  </div>
</div>

@@ moderator
<!-- MODERATOR PAGE: CLASH OF CLANS TOWN HALL -->
<div class="space-y-8">
  <div class="bg-obsidian p-6 rounded-2xl border border-purple-600/60 flex justify-between items-center">
    <div>
      <span class="text-xs uppercase tracking-widest text-amber-400">🛡️ Town Hall Operations • Clash of Clans Division</span>
      <h1 class="font-royal text-3xl font-bold text-white">PANEL MODERATOR REALM</h1>
      <p class="text-sm text-gray-400">Dikelola bersama Gadis Desa (Villager) & Archer Queen — Kelola Berita CMS, Status Turnamen, dan Distribusi Tiket Member.</p>
    </div>
  </div>

  <div class="grid md:grid-cols-12 gap-8">
    <!-- Form Tambah Berita CMS -->
    <div class="md:col-span-6 bg-obsidian p-6 rounded-xl border border-purple-800/60 space-y-4">
      <h2 class="font-royal text-lg font-bold gold-gradient">📝 TERBITKAN PENGUMUMAN / EVENT CMS</h2>
      <form action="/moderator/post" method="POST" class="space-y-3 text-sm">
        <div>
          <label class="block text-xs text-gray-400 mb-1">Judul Pengumuman</label>
          <input type="text" name="title" required placeholder="Contoh: Jadwal Turnamen Catur Malam Minggu" class="w-full p-2.5 rounded bg-black border border-purple-800 text-white">
        </div>
        <div>
          <label class="block text-xs text-gray-400 mb-1">Kategori</label>
          <select name="category" class="w-full p-2.5 rounded bg-black border border-purple-800 text-amber-300">
            <option value="Turnamen">Turnamen Arena</option>
            <option value="Event Undian">Event Undian (Draw/Roll)</option>
            <option value="Clan War">Clan War (CoC / MLBB)</option>
            <option value="Legacy Lore">Legacy Lore</option>
          </select>
        </div>
        <div>
          <label class="block text-xs text-gray-400 mb-1">Isi Pengumuman</label>
          <textarea name="content" rows="3" required placeholder="Tulis detail acara atau pengumuman..." class="w-full p-2.5 rounded bg-black border border-purple-800 text-white"></textarea>
        </div>
        <button type="submit" class="w-full py-2.5 rounded bg-purple-700 hover:bg-purple-600 text-white font-bold">Terbitkan ke Landing Page</button>
      </form>
    </div>

    <!-- Distribusi Tiket & Update Turnamen -->
    <div class="md:col-span-6 space-y-6">
      <div class="bg-obsidian p-6 rounded-xl border border-amber-500/40 space-y-3">
        <h2 class="font-royal text-lg font-bold gold-gradient">🎟️ BAGIKAN TIKET UNDIAN KE MEMBER</h2>
        <form action="/moderator/grant-ticket" method="POST" class="flex gap-3 text-sm">
          <select name="username" class="flex-grow p-2.5 rounded bg-black border border-gray-700 text-white">
            <% @users.each do |u| %>
              <option value="<%= u['username'] %>"><%= u['username'] %> (Tiket saat ini: <%= u['tickets'] %>)</option>
            <% end %>
          </select>
          <input type="number" name="amount" value="3" min="1" max="50" class="w-20 p-2.5 rounded bg-black border border-gray-700 text-amber-400 text-center">
          <button type="submit" class="px-4 py-2.5 rounded bg-amber-500 text-black font-bold">Kirim</button>
        </form>
      </div>

      <div class="bg-obsidian p-6 rounded-xl border border-purple-800/60 space-y-3">
        <h2 class="font-royal text-lg font-bold gold-gradient">🏆 UPDATE PEMENANG TURNAMEN</h2>
        <% @tournaments.each do |t| %>
          <form action="/moderator/tournament/update" method="POST" class="p-3 rounded bg-black/60 border border-gray-800 grid grid-cols-12 gap-2 items-center text-xs">
            <input type="hidden" name="id" value="<%= t['id'] %>">
            <div class="col-span-4 font-bold text-white"><%= t['name'] %></div>
            <div class="col-span-3">
              <select name="status" class="w-full p-1.5 rounded bg-gray-900 border border-gray-700 text-purple-300">
                <option value="Pendaftaran Dibuka" <%= 'selected' if t['status']=='Pendaftaran Dibuka' %>>Dibuka</option>
                <option value="Berlangsung" <%= 'selected' if t['status']=='Berlangsung' %>>Berlangsung</option>
                <option value="Selesai" <%= 'selected' if t['status']=='Selesai' %>>Selesai</option>
              </select>
            </div>
            <div class="col-span-3">
              <input type="text" name="champion" value="<%= t['champion'] %>" class="w-full p-1.5 rounded bg-gray-900 border border-gray-700 text-amber-300">
            </div>
            <div class="col-span-2">
              <button type="submit" class="w-full py-1.5 rounded bg-purple-800 hover:bg-purple-600 text-white font-bold">Simpan</button>
            </div>
          </form>
        <% end %>
      </div>
    </div>
  </div>
</div>

@@ admin
<!-- ADMIN PAGE: PLANE OF EUTHYMIA (RAIDEN SHOGUN & PHOENIX CORE) -->
<div class="space-y-8">
  <div class="bg-gradient-to-r from-purple-950 via-black to-amber-950 p-6 rounded-2xl border border-amber-400/60 flex justify-between items-center">
    <div>
      <span class="text-xs uppercase tracking-widest text-amber-300">👑 Plane of Euthymia • Sovereign CMS Core</span>
      <h1 class="font-royal text-3xl font-bold gold-gradient">SHOGUNATE ADMIN CONTROL</h1>
      <p class="text-sm text-gray-300">Otoritas Tertinggi Raiden Ei & Phoenix Hitam-Ungu: Kelola Pewaris Takhta (Role), Pool Item Gacha, dan Turnamen Baru.</p>
    </div>
  </div>

  <div class="grid md:grid-cols-12 gap-8">
    <!-- 1. Manajemen Role & Pewaris Legacy -->
    <div class="md:col-span-7 bg-obsidian p-6 rounded-xl border border-amber-500/40 space-y-4">
      <h2 class="font-royal text-lg font-bold gold-gradient">🐦‍⬛ MANAJEMEN WARISAN TAKHTA & ROLE USER</h2>
      <p class="text-xs text-gray-400">Tetapkan siapa yang menjadi Admin penerus (Sovereign), Moderator (Elder), atau Member.</p>
      <div class="space-y-3">
        <% @users.each do |u| %>
          <form action="/admin/user/role" method="POST" class="p-3 rounded bg-black/70 border border-gray-800 grid grid-cols-12 gap-2 items-center text-xs">
            <input type="hidden" name="user_id" value="<%= u['id'] %>">
            <div class="col-span-3 font-bold text-amber-400"><%= u['username'] %></div>
            <div class="col-span-4">
              <input type="text" name="title" value="<%= u['title'] %>" class="w-full p-1.5 rounded bg-gray-900 border border-gray-700 text-white">
            </div>
            <div class="col-span-3">
              <select name="role" class="w-full p-1.5 rounded bg-gray-900 border border-purple-700 text-purple-300">
                <option value="member" <%= 'selected' if u['role']=='member' %>>Member</option>
                <option value="moderator" <%= 'selected' if u['role']=='moderator' %>>Moderator</option>
                <option value="admin" <%= 'selected' if u['role']=='admin' %>>Admin (Sovereign)</option>
              </select>
            </div>
            <div class="col-span-2">
              <button type="submit" class="w-full py-1.5 rounded bg-amber-500 text-black font-bold">Update</button>
            </div>
          </form>
        <% end %>
      </div>

      <!-- Hapus Postingan CMS -->
      <div class="pt-4 border-t border-gray-800">
        <h3 class="font-royal text-sm font-bold text-purple-300 mb-2">Manajemen Postingan CMS</h3>
        <div class="space-y-2 text-xs">
          <% @posts.each do |p| %>
            <div class="flex justify-between items-center p-2 rounded bg-black/50 border border-gray-800">
              <span><strong>[<%= p['category'] %>]</strong> <%= p['title'] %></span>
              <form action="/admin/post/delete/<%= p['id'] %>" method="POST">
                <button class="px-2 py-1 rounded bg-red-900/60 text-red-200 hover:bg-red-700">Hapus</button>
              </form>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <!-- 2. Konfigurasi Pool Gacha & Buat Turnamen -->
    <div class="md:col-span-5 space-y-6">
      <div class="bg-obsidian p-6 rounded-xl border border-purple-800/60 space-y-3">
        <h2 class="font-royal text-lg font-bold gold-gradient">🎲 KONFIGURASI HADIAH UNDIAN (GACHA POOL)</h2>
        <form action="/admin/gacha/add" method="POST" class="space-y-2 text-xs">
          <input type="text" name="item_name" required placeholder="Nama Hadiah / Item" class="w-full p-2 rounded bg-black border border-gray-700 text-white">
          <div class="grid grid-cols-2 gap-2">
            <select name="rarity" class="p-2 rounded bg-black border border-gray-700 text-amber-300">
              <option value="SSR - Gold">SSR - Gold (Langka)</option>
              <option value="SR - Purple">SR - Purple (Menengah)</option>
              <option value="R - Obsidian">R - Obsidian (Umum)</option>
            </select>
            <input type="number" name="weight" placeholder="Bobot Peluang (Contoh: 10)" required class="p-2 rounded bg-black border border-gray-700 text-white">
          </div>
          <button type="submit" class="w-full py-2 rounded bg-gradient-to-r from-purple-700 to-amber-600 text-white font-bold">Tambah Hadiah ke Altar</button>
        </form>
        <div class="text-xs space-y-1 pt-2">
          <% @gacha_pool.each do |g| %>
            <div class="flex justify-between text-gray-400">
              <span><%= g['item_name'] %> (<%= g['rarity'] %>)</span>
              <span class="text-amber-400">Weight: <%= g['weight'] %></span>
            </div>
          <% end %>
        </div>
      </div>

      <div class="bg-obsidian p-6 rounded-xl border border-purple-800/60 space-y-3">
        <h2 class="font-royal text-lg font-bold gold-gradient">⚔️ BUKA TURNAMEN BARU</h2>
        <form action="/admin/tournament/add" method="POST" class="space-y-2 text-xs">
          <input type="text" name="name" required placeholder="Nama Turnamen (Contoh: EiXercise Chess Cup II)" class="w-full p-2 rounded bg-black border border-gray-700 text-white">
          <select name="game" class="w-full p-2 rounded bg-black border border-gray-700 text-purple-300">
            <option value="Chess Online (Lichess Arena)">Chess Online (Lichess Arena)</option>
            <option value="Mobile Legends: Bang Bang">Mobile Legends: Bang Bang</option>
            <option value="Clash of Clans Clan War">Clash of Clans Clan War</option>
            <option value="Devil May Cry Style Combo Contest">Devil May Cry Style Contest</option>
          </select>
          <input type="hidden" name="status" value="Pendaftaran Dibuka">
          <button type="submit" class="w-full py-2 rounded bg-amber-500 text-black font-bold">Buat Turnamen</button>
        </form>
      </div>
    </div>
  </div>
</div>
