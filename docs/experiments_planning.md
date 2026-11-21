# Hasil Eksperimen Tahap 4: Automated Planning untuk Boss

Dihasilkan oleh `tests/experiments_planning.gd`. Boss: Giant Bamboo (120 HP, Wind) melawan party Ninja, Flame, Knight, Monk dengan HP awal acak 70-100 % (seed tetap, 30 pertandingan per konfigurasi). Lawan (pihak player) = kebijakan tetap alpha-beta kedalaman 2, evaluasi tactical, full targeting. Planner default: A* heuristik damage + pruning, panjang rencana maks. 4, skor gain_rate, fallback alpha-beta kedalaman 4.


## 1. Validitas model planning (PlanModel vs BattleSim)

Pada setiap posisi uji: aksi applicable menurut model dibandingkan dengan `legal_actions` simulasi (full targeting); lalu untuk tiga aksi acak, state yang diprediksi `PlanModel.apply` dibandingkan dengan simulasi setelah boss bertindak dan player pass. Posisi uji diambil dari giliran boss pada 6 pertandingan planner; 8 dari 38 giliran boss terkena stun (Bump Knight) dan tidak dipakai.

| Posisi uji | Posisi fase 2 | Aksi applicable rata-rata | Himpunan aksi sama dengan simulasi | Langkah diuji | Prediksi state tepat |
|---|---|---|---|---|---|
| 30 | 13 | 7.57 | 30/30 | 90 | 90/90 (100.0 %) |

## 2. Algoritma pencarian: uniform cost (BFS) vs A* dengan heuristik goal_count / damage

Setiap posisi uji x setiap goal kandidat = satu masalah planning (panjang maks. 4, batas 1500 node diekspansi). Pruning = cabang dengan batas bawah damage melampaui sisa kedalaman dibuang. 'Optimal' dihitung pada masalah yang diselesaikan semua konfigurasi: panjang rencana sama dengan panjang terpendek yang ditemukan.

Masalah planning: 154 (goal dengan rencana pada minimal satu konfigurasi: 125; diselesaikan semua konfigurasi: 125).

| Konfigurasi | Rencana ditemukan | Berhenti karena batas node | Node diekspansi rata-rata | Node dibangkitkan rata-rata | Waktu rata-rata (ms) | Panjang rencana rata-rata (masalah bersama) | Optimal |
|---|---|---|---|---|---|---|---|
| Uniform cost (h = 0), tanpa pruning | 125/154 | 0 | 110.5 | 495.1 | 34.22 | 2.30 | 100.0 % |
| Uniform cost (h = 0) + pruning | 125/154 | 0 | 59.1 | 205.4 | 36.29 | 2.30 | 100.0 % |
| A* goal_count + pruning | 125/154 | 0 | 32.7 | 96.0 | 19.54 | 2.30 | 100.0 % |
| A* damage, tanpa pruning | 125/154 | 0 | 69.5 | 213.7 | 20.71 | 2.30 | 100.0 % |
| A* damage + pruning (default) | 125/154 | 0 | 29.3 | 87.7 | 18.36 | 2.30 | 100.0 % |

## 3. Pemilihan goal: skor gain_rate vs end_value

`decide()` dijalankan pada setiap posisi uji dengan dua cara menilai rencana. gain_rate = (V(akhir) - V(sekarang)) / panjang; end_value = V(akhir) - 3 x panjang. Kolom jenis goal = persentase posisi di mana goal jenis itu terpilih.

| Skor | Kill | Burn every hero | Fortify | Recover | Tidak ada goal | Panjang rencana rata-rata | Waktu decide (ms) |
|---|---|---|---|---|---|---|---|
| gain_rate (default) | 93.3 % | 0.0 % | 0.0 % | 6.7 % | 0.0 % | 2.10 | 94.4 |
| end_value | 100.0 % | 0.0 % | 0.0 % | 0.0 % | 0.0 % | 2.77 | 94.1 |

Kedua skor memilih goal dan panjang yang sama pada 14/30 posisi (46.7 %).


## 4. Eksekusi: replanning vs panjang rencana dan kekuatan player

Pertandingan penuh dengan otak planner. 'Replan basi' = rencana dibuang karena precondition gagal atau sisa langkah tidak lagi mencapai goal (akibat aksi player); 'lanjutan' = persentase langkah yang berasal dari rencana giliran sebelumnya.

| Konfigurasi | Win rate boss | Seri | Giliran rata-rata | Keputusan boss/game | Rencana/game | Replan basi/game | Fallback/game | Langkah lanjutan | Waktu/keputusan (ms) | Alasan replan (precondition / goal tak tercapai / selesai / goal tercapai) |
|---|---|---|---|---|---|---|---|---|---|---|
| maks. 2 langkah, player d2 | 20 % | 0 | 19.5 | 9.3 | 6.10 | 1.30 | 0.63 | 37 % | 8.4 | 0 / 39 / 95 / 0 |
| maks. 3 langkah, player d2 | 60 % | 0 | 22.0 | 10.8 | 4.97 | 0.87 | 0.00 | 45 % | 17.2 | 0 / 26 / 93 / 0 |
| maks. 4 langkah, player d2 (default) | 63 % | 0 | 22.0 | 10.8 | 4.93 | 0.87 | 0.00 | 46 % | 38.7 | 0 / 26 / 92 / 0 |
| maks. 5 langkah, player d2 | 63 % | 0 | 22.0 | 10.8 | 4.93 | 0.87 | 0.00 | 46 % | 63.6 | 0 / 26 / 92 / 0 |
| maks. 4 langkah, player d1 (greedy) | 50 % | 0 | 16.6 | 8.0 | 4.03 | 0.03 | 0.00 | 50 % | 49.2 | 0 / 1 / 90 / 0 |
| maks. 4 langkah, player d3 | 50 % | 0 | 22.0 | 10.8 | 5.03 | 0.93 | 0.03 | 44 % | 37.5 | 1 / 26 / 93 / 0 |

## 5. Otak boss: minimax vs greedy vs planner vs hybrid

Pertandingan penuh melawan player alpha-beta kedalaman 2. minimax = alpha-beta kedalaman 4 (kontrol), greedy = kedalaman 1, planner = default, hybrid = langkah pertama tiap rencana kandidat menjadi aksi akar alpha-beta kedalaman 4. Kolom skill = persentase aksi boss yang memakai skill tersebut.

| Otak | Win rate boss | Seri | Giliran rata-rata | Sisa HP boss rata-rata | Waktu/keputusan (ms) | Sap Surge | Bamboo Spear | Thorn Storm | Harden Bark | Regrow | Root Slam |
|---|---|---|---|---|---|---|---|---|---|---|---|
| minimax (alpha-beta d4) | 60 % | 0 | 23.1 | 17.7 | 29.9 | 21 % | 35 % | 0 % | 20 % | 4 % | 4 % |
| greedy (d1) | 13 % | 0 | 27.5 | 0.3 | 0.4 | 0 % | 48 % | 0 % | 12 % | 8 % | 17 % |
| planner (default) | 63 % | 0 | 22.0 | 6.3 | 36.8 | 28 % | 44 % | 0 % | 0 % | 1 % | 14 % |
| hybrid | 57 % | 0 | 20.4 | 16.3 | 72.2 | 28 % | 40 % | 0 % | 10 % | 1 % | 8 % |

## 6. Ablasi: boss tanpa prasyarat (skill datar)

Rantai setup -> payoff dihapus: Sap Surge dan Thorn Storm dibuang, Bamboo Spear selalu 10, tidak ada status enraged. Gerbang satu aksi (Harden Bark hanya saat tanpa shield, Regrow sekali di bawah 50 %) dipertahankan karena tidak membentuk struktur multi-langkah. Jika nilai planning berasal dari struktur aksi, planner pada boss datar seharusnya mendekati greedy.

Kesamaan aksi pertama planner dengan greedy pada posisi uji: boss berstruktur 7/30 (23.3 %), boss datar 10/30 (33.3 %).

| Otak | Win rate boss | Seri | Giliran rata-rata | Sisa HP boss rata-rata | Rencana/game | Langkah lanjutan | Waktu/keputusan (ms) |
|---|---|---|---|---|---|---|---|
| boss datar: greedy (d1) | 13 % | 0 | 27.5 | 0.3 | 0.00 | 0 % | 0.4 |
| boss datar: minimax (alpha-beta d4) | 50 % | 0 | 32.4 | 7.1 | 0.00 | 0 % | 21.0 |
| boss datar: planner | 33 % | 0 | 27.3 | 4.4 | 6.13 | 40 % | 5.8 |

_Total waktu eksperimen: 168.3 detik._
