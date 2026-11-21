# Hasil Eksperimen AI Battle

Dihasilkan oleh `tests/experiments.gd`. Lawan (pihak player) selalu dikendalikan oleh kebijakan tetap: alpha-beta kedalaman 2 dengan evaluasi `tactical` (pemain yang cukup kompeten). Setiap konfigurasi dimainkan pada 30 pertandingan (3 encounter, HP awal party diacak 70-100% dengan seed tetap).

Posisi uji: 40 state tengah-permainan (giliran NPC) yang diambil merata dari 6 pertandingan alpha-beta (depth 3) vs kebijakan player.

## 1. Minimax vs Alpha-Beta vs Early Stop (kedalaman 4)

| Algoritma | Node/keputusan | Evaluasi/keputusan | Cabang dipangkas | Waktu (ms) | Aksi sama dgn minimax | Nilai sama | Budget tercapai |
| --- | --- | --- | --- | --- | --- | --- | --- |
| minimax | 61 | 41 | 0 | 5.0 | 40/40 | 40/40 | 0 |
| alpha-beta (tanpa ordering) | 29 | 15 | 9 | 2.33 | 40/40 | 40/40 | 0 |
| alpha-beta + heuristic ordering | 25 | 43 | 10 | 4.34 | 40/40 | 40/40 | 0 |
| alpha-beta + ordering, budget 150 node | 25 | 43 | 10 | 4.34 | 40/40 | 40/40 | 0 |
| alpha-beta + ordering, budget 60 node | 24 | 41 | 9 | 4.08 | 38/40 | 36/40 | 4 |

## 3. Urutan aksi pada alpha-beta (kedalaman 4)

| Ordering | Node/keputusan | Cabang dipangkas | Waktu (ms) |
| --- | --- | --- | --- |
| none | 29 | 9 | 2.31 |
| heuristic | 25 | 10 | 4.29 |
| random | 36 | 9 | 2.98 |
| worst | 60 | 1 | 8.99 |

## 4. Kedalaman pencarian (alpha-beta + ordering; win rate diukur dengan full targeting agar pilihan target ikut dicari)

| Depth | Node/keputusan | Waktu (ms) | Win rate NPC | Rata-rata giliran | Sisa HP NPC |
| --- | --- | --- | --- | --- | --- |
| 1 | 3 | 0.28 | 70% | 32.4 | 56.2 |
| 2 | 6 | 0.85 | 67% | 32.7 | 57.8 |
| 3 | 13 | 1.95 | 67% | 30.4 | 54.8 |
| 4 | 25 | 4.42 | 70% | 32.3 | 61.4 |
| 5 | 46 | 8.41 | 67% | 28.0 | 61.3 |
| 6 | 86 | 19.6 | - | - | - |

## 2. Fungsi evaluasi (alpha-beta, kedalaman 4, full targeting)

| Evaluasi | Win rate NPC | Seri | Rata-rata giliran | Sisa HP NPC | Sisa HP player | Aksi beda dari tactical | Damage langsung rata-rata | Serangan ke hero paling berbahaya |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hp_diff | 67% | 0 | 30.6 | 68.1 | 3.8 | 11/40 | 4.8 | 19/32 |
| hp_ratio | 73% | 0 | 32.5 | 63.3 | 4.1 | 2/40 | 4.2 | 19/36 |
| tactical | 70% | 0 | 32.3 | 61.4 | 4.1 | 0/40 | 4.2 | 20/36 |
| threat | 67% | 0 | 31.5 | 56.5 | 4.7 | 7/40 | 4.2 | 22/36 |

## 5. Tingkah laku NPC: personality (evaluasi tactical, kedalaman 4, full targeting)

| Personality | Win rate NPC | Rata-rata giliran | Damage ke player | Sisa HP NPC | Sisa HP player | Aksi beda dari balanced | Damage langsung rata-rata | Aksi AoE |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| balanced | 70% | 32.3 | 75.9 | 61.4 | 4.1 | 0/40 | 4.2 | 4/40 |
| aggressive | 67% | 28.1 | 75.4 | 56.4 | 4.6 | 7/40 | 4.5 | 7/40 |
| defensive | 70% | 35.4 | 75.9 | 60.9 | 4.1 | 1/40 | 4.4 | 5/40 |

## 6. Expectimax pada permainan stokastik (peluang serangan kena = 0.75, kedalaman 3, full targeting)

| Algoritma | Win rate NPC | Rata-rata giliran | Sisa HP NPC | Node/keputusan | Waktu (ms) | Aksi beda dari alpha-beta |
| --- | --- | --- | --- | --- | --- | --- |
| alpha-beta (mengasumsikan selalu kena) | 70% | 40.2 | 53.7 | 71 | 17.5 | 0/40 |
| expectimax | 70% | 39.8 | 52.7 | 3746 | 419.33 | 2/40 |

## 7. Fitur sendiri: mode ultimate AUTO vs CHOICE (alpha-beta, kedalaman 4)

| Mode | Branching rata-rata (akar) | Node/keputusan | Win rate NPC | Rata-rata giliran |
| --- | --- | --- | --- | --- |
| auto | 2.0 | 25 | 67% | 32.3 |
| choice | 2.42 | 31 | 67% | 30.5 |

## 8. Fitur sendiri: target berdasarkan aturan vs full targeting (alpha-beta, kedalaman 4)

| Targeting | Branching rata-rata (akar) | Node/keputusan | Waktu (ms) | Win rate NPC | Seri | Rata-rata giliran |
| --- | --- | --- | --- | --- | --- | --- |
| rule | 2.0 | 25 | 4.43 | 67% | 0 | 32.3 |
| full | 5.15 | 225 | 76.95 | 70% | 0 | 32.3 |

## 9. Fitur sendiri: aturan target WEAKEST / THREAT / TOUGHEST / PER_UNIT (alpha-beta, kedalaman 4, rule targeting)

Aturan target menentukan siapa yang diserang saat pilihan target tidak dicari. THREAT memakai model ancaman `threat_of`; TOUGHEST menyerang HP tertinggi; PER_UNIT memberi tiap musuh preferensinya sendiri (Bamboo/Bomber: weakest, Bear/Thunder Mage: threat, Fire Mage: toughest). Kill yang tersedia selalu diambil lebih dulu. Kolom terakhir kedua mengukur seberapa sering serangan jatuh ke hero paling berbahaya.

| Konfigurasi | Win rate NPC | Rata-rata giliran | Sisa HP NPC | Sisa HP player | Serangan ke hero paling berbahaya | Aksi beda dari weakest+tactical |
| --- | --- | --- | --- | --- | --- | --- |
| weakest + tactical | 67% | 32.3 | 47.3 | 8.4 | 24/36 | 0/40 |
| threat + tactical | 67% | 30.5 | 45.6 | 12.3 | 31/34 | 0/40 |
| threat + threat | 67% | 30.3 | 42.8 | 13.1 | 31/34 | 1/40 |
| toughest + tactical | 67% | 21.1 | 53.2 | 12.8 | 12/33 | 0/40 |
| per_unit + tactical | 67% | 30.6 | 48.1 | 9.5 | 28/33 | 0/40 |


_Total waktu eksperimen: 818.7 detik._
