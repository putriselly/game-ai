# Laporan Tahap 4: Automated Planning untuk Boss Battle

Proyek *game AI* (Godot 4.7). Kode Tahap 4 ada di `scripts/battle/plan_model.gd`, `boss_planner.gd`,
`boss_brain.gd` dan integrasinya di `battle.gd`, `debug_overlay.gd`, `roster.gd`. Desain lengkap:
[desain_planning.md](desain_planning.md). Tabel hasil lengkap: [experiments_planning.md](experiments_planning.md),
dibuat ulang dengan:

```bash
godot --headless --path . res://tests/experiments_planning_runner.tscn
```

## 1. Latar belakang dan pilihan domain

Tahap 1-3 memberi NPC pencarian A* di overworld, minimax/alpha-beta untuk memilih aksi, serta CSP +
local search untuk menyusun kombinasi aksi tim. Tahap 4 menambahkan **automated planning**: NPC menyusun
*urutan* aksi menuju sebuah goal, menjalankannya langkah demi langkah, memantau, dan menyusun ulang bila
rencana tidak lagi berlaku.

Planning sengaja **tidak** dipasang pada battle biasa. Musuh biasa hanya punya satu skill dasar dan satu
ultimate otomatis tanpa prasyarat, branching ≤ 4, dan pada Tahap 3 terukur bahwa sebagian besar aksi
rencana untuk giliran berikutnya sudah tidak legal lagi karena aksi player. Planner di sana hanya
menghasilkan "serang, serang, serang" dan mengulang pekerjaan minimax dengan model lawan yang lebih lemah.
Karena itu dibuat **boss battle** baru: Giant Bamboo (120 HP, elemen Wind) dengan skill yang saling
bergantung, sehingga ada rangkaian aksi multi-giliran yang layak direncanakan (Tabel 1).

**Tabel 1 Skill boss, precondition dan efeknya**

| Skill | Target | Efek | Precondition |
|---|---|---|---|
| Root Slam | satu hero | 6 damage | - |
| Sap Surge | diri | status `enraged` | ¬enraged |
| Bamboo Spear | satu hero | 10 damage; **24** bila enraged (menghabiskan enraged) | - |
| Thorn Storm | semua hero | 6 damage + burn 2 giliran (menghabiskan enraged) | enraged ∧ phase2 (HP < 50 %) |
| Harden Bark | diri | shield 15 | shield = 0 |
| Regrow | diri | heal 25, memakai 1 potion | HP < 50 %, sekali per battle |
| Bamboo Fury (ultimate) | semua hero | 8 damage | bar ultimate penuh |

Angka 24 dipilih agar `Sap Surge → Bamboo Spear` (24 dalam 2 aksi) mengalahkan dua Spear biasa (20):
Ninja (22 HP) jatuh dalam 2 aksi dengan rage tetapi 3 tanpa rage, Knight (32 HP) dalam 3 aksi vs 4.
Minimax kedalaman 4 hanya melihat 2 aksi boss, sehingga rangkaian 3 aksi hanya terjangkau planner.

## 2. Perancangan

### 2.1 Representasi (`plan_model.gd`)

* **State abstrak** `PlanState`: HP, shield, burn per unit; himpunan *flag* per unit (`enraged`, `phase2`,
  `used_regrow`); muatan ultimate boss; stok potion. Literal goal berbentuk `pred(unit)` atau
  `not pred(unit)` dengan predikat bawaan `alive, dead, burning, shielded, low_hp, ult_ready` atau nama
  flag.
* **Operator** = skill boss; grounding menghasilkan satu aksi per target hidup (sama dengan
  `legal_actions` simulasi pada mode full targeting). Precondition diambil dari field skill
  (`requires`, `forbids`, `once_per_battle`, `only_if_user_hp_below`), ditambah aturan ultimate otomatis dan
  stok potion.
* **Efek** `apply()`: skill diselesaikan (dengan multiplier elemen), flag dihabiskan/diberikan, lalu kedua
  batas giliran dilewati dengan asumsi **player pasif** (relaxed): burn hero berdetak, burn boss berdetak,
  cek fase 2. Model ini sama persis dengan `BattleSim` ketika player melakukan pass (Eksperimen 1).

### 2.2 Pencarian dan pemilihan goal (`boss_planner.gd`)

* **Goal kandidat** diturunkan dari skill boss: `dead(h)` untuk setiap hero hidup (healer dan hero yang
  lemah terhadap elemen boss didahulukan), `burning(h) ∀h`, *fortify* (`shielded ∧ enraged`), *recover*
  (`not low_hp`) bila HP rendah.
* **A\*** forward dengan biaya 1 per aksi, batas panjang 4, batas 1500 node. Heuristik: `none` (uniform
  cost = BFS), `goal_count` (literal belum terpenuhi), `damage` (batas bawah admissible: HP + shield target
  dibagi damage maksimum satu aksi + burn tick; literal lain = 1). Batas bawah yang sama memangkas cabang
  yang tidak mungkin mencapai goal dalam sisa kedalaman.
* **Pemilihan goal berbasis utilitas**: setiap goal direncanakan, state akhir dinilai dengan
  `BattleEvaluator` (evaluasi `tactical`, sama dengan NPC minimax). Skor default `gain_rate` =
  (V(akhir) − V(sekarang)) / panjang, karena model relaxed mengabaikan player sehingga setiap langkah
  tambahan adalah satu giliran gratis bagi lawan. Alternatif `end_value` = V(akhir) − 3·panjang.

### 2.3 Eksekusi dan pemantauan (`boss_brain.gd`)

Setiap giliran boss: jika rencana masih berlaku, mainkan langkah berikutnya; jika tidak, susun rencana baru;
jika tidak ada goal yang terjangkau, **fallback** ke alpha-beta kedalaman 4. "Masih berlaku" diperiksa dua
lapis: *action monitoring* (precondition langkah berikutnya pada state nyata) dan *plan monitoring*
(seluruh sisa langkah diputar ulang pada state relaxed saat ini dan goal harus tetap tercapai, sehingga
rencana yang dibatalkan player, misalnya target di-heal, dibuang). Mode otak: `planner`, `minimax`
(kontrol), `hybrid` (langkah pertama setiap rencana kandidat menjadi aksi akar minimax). Statistik per
battle (rencana, replan basi, fallback, langkah lanjutan) dan panel PLANNING pada overlay F1 menampilkan
goal, rencana dengan penanda langkah, alasan replan, dan semua goal yang dipertimbangkan.

## 3. Pengujian dan hasil

Semua pengujian headless, seed tetap. Lawan = alpha-beta kedalaman 2, evaluasi `tactical`, full targeting.
HP awal party acak 70-100 %; 30 pertandingan per konfigurasi; 30 posisi giliran boss diambil dari 6
pertandingan planner (8 dari 38 giliran boss terkena stun Bump Knight dan tidak dipakai). Unit test
(`tests/test_battle.gd`, `tests/test_planning.gd`: aturan boss, model vs simulasi ±900 langkah acak,
pencarian, goal selection, brain, boss battle lewat scene asli) seluruhnya lulus (ALL TESTS PASSED).

### 3.1 Validitas model

Pada 30 posisi, himpunan aksi applicable model identik dengan `legal_actions` simulasi (30/30, rata-rata
7,57 aksi), dan prediksi `apply()` untuk 90 langkah acak tepat 90/90 (100 %). Model planning dan aturan
permainan membaca definisi skill yang sama, sehingga rencana yang dihasilkan selalu dapat dieksekusi.

### 3.2 Algoritma pencarian

154 masalah planning (posisi × goal), 125 di antaranya punya rencana ≤ 4 langkah (29 lainnya: hero
ber-HP besar atau burn massal sebelum fase 2). Semua konfigurasi menemukan 125 rencana yang sama
panjangnya (optimal 100 %), tidak ada yang menyentuh batas node.

| Konfigurasi | Node diekspansi | Node dibangkitkan | Waktu (ms) |
|---|---|---|---|
| Uniform cost, tanpa pruning | 110,5 | 495,1 | 34,2 |
| Uniform cost + pruning | 59,1 | 205,4 | 36,3 |
| A* goal_count + pruning | 32,7 | 96,0 | 19,5 |
| A* damage, tanpa pruning | 69,5 | 213,7 | 20,7 |
| A* damage + pruning | **29,3** | **87,7** | **18,4** |

Heuristik `damage` + pruning mengekspansi 73 % lebih sedikit node daripada uniform cost dan separuh
waktunya. Pruning sendiri memotong node BFS hampir setengah tetapi tidak mempercepat (36,3 vs 34,2 ms)
karena batas bawah dihitung untuk setiap anak; manfaatnya muncul saat digabung heuristik. `goal_count`
hampir sebaik `damage` di sini karena sebagian besar goal hanya satu literal; pada goal multi-literal
(burn massal) ia tidak admissible, sedangkan `damage` admissible sehingga optimalitas A* terjamin.

### 3.3 Pemilihan goal

| Skor | Kill | Burn every hero | Fortify | Recover | Panjang rata-rata |
|---|---|---|---|---|---|
| gain_rate (default) | 93,3 % | 0 % | 0 % | 6,7 % | 2,10 |
| end_value | 100 % | 0 % | 0 % | 0 % | 2,77 |

Kedua skor sepakat hanya pada 14/30 posisi (46,7 %): `end_value` memilih rencana lebih panjang (rata-rata
2,77 vs 2,10) karena menilai hasil akhir tanpa memperhitungkan giliran player yang dilewati, persis
fenomena yang ditemukan saat pengujian unit ("bunuh Ninja dalam 4 aksi" mengalahkan "bunuh Monk dalam 2
aksi"). Goal *burn every hero* dan *fortify* **tidak pernah terpilih**: bonus +30 per unit lawan yang mati
pada evaluasi `tactical` selalu mengalahkan nilai burn/shield, sehingga Thorn Storm praktis tidak terpakai
(0 % pada semua otak, Tabel 3.5). Ini temuan desain, bukan kegagalan planner: pemilihan goal mewarisi
preferensi fungsi evaluasi Tahap 2.

### 3.4 Eksekusi: replanning

| Konfigurasi | Win rate boss | Rencana/game | Replan basi/game | Fallback/game | Langkah lanjutan | ms/keputusan |
|---|---|---|---|---|---|---|
| maks. 2 langkah, player d2 | 20 % | 6,10 | 1,30 | 0,63 | 37 % | 8,4 |
| maks. 3 langkah, player d2 | 60 % | 4,97 | 0,87 | 0,00 | 45 % | 17,2 |
| maks. 4 langkah, player d2 (default) | 63 % | 4,93 | 0,87 | 0,00 | 46 % | 38,7 |
| maks. 5 langkah, player d2 | 63 % | 4,93 | 0,87 | 0,00 | 46 % | 63,6 |
| maks. 4 langkah, player d1 | 50 % | 4,03 | 0,03 | 0,00 | 50 % | 49,2 |
| maks. 4 langkah, player d3 | 50 % | 5,03 | 0,93 | 0,03 | 44 % | 37,5 |

Batas 2 langkah terlalu pendek: rantai pembunuhan 3 aksi tidak terjangkau, planner sering jatuh ke
fallback (0,63/game) dan boss hanya menang 20 %. Mulai 3 langkah hasilnya stabil (60-63 %), dan batas 5
tidak mengubah apa pun selain menggandakan waktu (39 → 64 ms): rencana yang berguna memang 2-3 langkah.
Sekitar **46 % langkah** berasal dari rencana giliran sebelumnya; rencana dibuang karena basi 0,87 kali per
pertandingan, **semuanya** karena "goal tidak lagi tercapai oleh sisa langkah" (player meng-heal atau memberi
shield), tidak pernah karena precondition gagal (player tidak bisa mencabut flag boss). Melawan player
greedy (d1) replan basi hampir nol (0,03) karena player itu tidak pernah bertahan.

### 3.5 Perbandingan otak boss

| Otak | Win rate | Sisa HP boss | ms/keputusan | Sap Surge | Harden Bark | Thorn Storm |
|---|---|---|---|---|---|---|
| minimax (alpha-beta d4) | 60 % | 17,7 | 29,9 | 21 % | 20 % | 0 % |
| greedy (d1) | 13 % | 0,3 | 0,4 | 0 % | 12 % | 0 % |
| planner (default) | **63 %** | 6,3 | 36,8 | **28 %** | 0 % | 0 % |
| hybrid | 57 % | 16,3 | 72,2 | 28 % | 10 % | 0 % |

Planner setara dengan alpha-beta kedalaman 4 (63 % vs 60 %) dengan biaya serupa (37 vs 30 ms), dan jauh di
atas greedy (13 %) yang tidak pernah memakai Sap Surge karena nilai setup tidak terlihat dalam satu ply.
Planner paling sering memakai rantai rage (28 %), tetapi **tidak pernah bertahan** (Harden Bark 0 %) dan
menang dengan sisa HP kecil (6,3): model relaxed tidak melihat ancaman lawan. Hybrid mewarisi pertahanan
dari minimax (Harden 10 %) tetapi kehilangan aksi yang tidak diusulkan planner dan dua kali lebih mahal.

### 3.6 Ablasi: boss tanpa rantai

Dengan Sap Surge dan Thorn Storm dibuang (Spear selalu 10), kesamaan aksi pertama planner dengan greedy
naik dari 23 % ke 33 %, dan win rate planner turun dari 63 % ke 33 % sementara minimax bertahan di 50 %.
Keunggulan planner atas minimax hilang begitu struktur setup → payoff dihapus, yang mendukung tesis bahwa
nilai planning berasal dari ketergantungan antar aksi. Planner tidak sepenuhnya menjadi greedy karena
rencana pembunuhan multi-langkah tetap memusatkan serangan pada satu target.

## 4. Kesimpulan

1. Boss battle dengan skill ber-precondition memberi planning persoalan yang nyata; pada battle biasa
   planning akan degeneratif. Pilihan domain ini terbukti: tanpa rantai aksi (ablasi) planner kehilangan
   keunggulannya.
2. Model planning STRIPS + fluent numerik memprediksi simulasi dengan tepat (100 %) karena membaca definisi
   skill yang sama; semua rencana dapat dieksekusi.
3. A* dengan heuristik batas bawah damage + pruning menemukan rencana optimal dengan 73 % lebih sedikit
   ekspansi daripada uniform cost, dalam ±18 ms per goal.
4. Pemilihan goal harus menghukum panjang rencana (skor laju keuntungan); menilai hasil akhir saja memilih
   rencana panjang yang menyerahkan giliran kepada lawan.
5. Eksekusi dengan pemantauan dua lapis menjaga ±46 % langkah berasal dari rencana sebelumnya dan hanya
   membuang <1 rencana per pertandingan; planner menyamai alpha-beta kedalaman 4 dan jauh mengungguli
   greedy, dengan kelemahan jelas: tidak pernah bertahan.

## 5. Saran

1. Tambahkan komponen ancaman lawan (`BattleSim.threat_of`) ke skor goal agar *fortify* dan *recover* terpilih
   saat hero dengan ultimate penuh mengancam; atau turunkan bobot bonus kill pada evaluasi yang dipakai planner.
2. Rancang ulang Thorn Storm atau gerbang fase 2 (misalnya fase 2 di 60 % HP) agar goal burn massal pernah
   menang.
3. Tangani stun: ±21 % giliran boss hilang karena Bump Knight; planner bisa memasukkan `stunned` sebagai
   risiko (mis. prioritaskan membunuh Knight di bawah 50 % HP).
4. Tambahkan GraphPlan pada proyeksi proposisional sebagai pembanding klasik, dan minion yang diatur CSP
   Tahap 3 sementara planner mengatur boss.
5. Hybrid saat ini hanya menyaring aksi akar; alternatif yang lebih murah: nilai rencana memakai minimax
   dangkal pada state akhirnya.
