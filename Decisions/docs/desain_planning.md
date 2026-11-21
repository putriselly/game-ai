# Desain Tahap 4: Automated Planning untuk Boss Battle

Status: **selesai diimplementasikan dan diuji, langkah 1-5** (19 Nov 2026). Hasil eksperimen: [experiments_planning.md](experiments_planning.md); analisis dan bab laporan: [laporan_tahap4.md](laporan_tahap4.md). Basis kode: branch `tahap4`
(= `origin/kbTahap1` folder `kb1/`, berisi Tahap 1-3: A*, minimax, CSP + local search, KB elemen).

## 0. Ringkasan keputusan

**Rekomendasi: planning dipakai sebagai otak *boss* pada boss battle baru, bukan menggantikan
minimax pada battle biasa.** Battle biasa tetap memakai pipeline Tahap 3
(CSP → local search → minimax). Alasannya dirangkum di bagian 1; intinya: battle biasa bersifat
adversarial dengan horizon pendek dan aksi musuh yang hampir tidak punya prasyarat, sehingga planner
klasik tidak punya struktur untuk dieksploitasi dan hanya mengulang pekerjaan minimax dengan model
lawan yang lebih lemah. Boss dengan skill ber-prasyarat (enrage → spear, enrage → thorn storm, harden
sekali, regrow sekali di bawah 50 % HP) memberi planner persoalan yang sesungguhnya: urutan aksi
multi-giliran menuju goal, eksekusi bertahap, pemantauan, dan *replanning* saat player mengacaukan
rencana.

## 1. Evaluasi: battle biasa vs boss battle

| Kriteria | Battle biasa (sekarang) | Boss battle (usulan) |
| --- | --- | --- |
| Sifat masalah | Adversarial: player bergerak di antara tiap aksi NPC. Ini domain minimax. | Tetap adversarial, tetapi boss butuh **rangkaian** aksi (setup → payoff) yang melampaui horizon minimax. |
| Struktur aksi | Tiap musuh punya 1 skill dasar + 1 ultimate otomatis. Tidak ada prasyarat selain "ult penuh". Planner apa pun menghasilkan "serang, serang, serang". | Skill boss punya *precondition/effect* eksplisit (status enraged, shielded, phase 2, regrow sekali). Ada ketergantungan antar aksi → plan nontrivial. |
| Branching & horizon | ≤ 4 aksi per giliran; alpha-beta kedalaman 4 sudah cukup (6 ms, Bab IV). Tidak ada ruang yang perlu "dipangkas" dengan planning. | Boss dengan 6 skill × 4 target ≈ 24 aksi akar; minimax kedalaman 6-8 ply (3-4 aksi boss) tidak terjangkau, planner yang mengabaikan lawan menjangkaunya dalam puluhan node. |
| Stabilitas rencana | Bab IV (plan stability): sebagian besar aksi rencana untuk NPC lain **tidak lagi legal** pada giliran berikutnya. Rencana multi-giliran langsung basi. | Rencana milik satu unit (boss), targetnya 4 hero; sebagian besar langkah tetap valid. Replanning jadi *kejadian yang bisa diukur*, bukan default. |
| Nilai untuk laporan | Hasil eksperimen akan datar (sama seperti MRV/LCV/AC-3 pada Bab IV yang tidak pernah aktif). | Ada yang bisa dibandingkan: BFS vs A* vs GraphPlan, heuristik, goal selection, frekuensi replanning, planner vs minimax vs hibrid. |
| Risiko / biaya | Rendah: tidak ada konten baru. | Perlu konten baru: 1 unit boss, 6 skill dengan field baru, 1 encounter overworld, mode otak NPC baru. Perkiraan 500-800 baris GDScript + tes. |
| Pemakaian ulang Tahap 1-3 | - | BattleSim jadi *model eksekusi*; minimax jadi pembanding dan fallback; CSP bisa mengatur minion (opsional); KB elemen dipakai pada pemilihan target goal. |

**Kesimpulan evaluasi.** Yang membuat planning menarik secara AI adalah ketergantungan antar aksi dan
horizon yang panjang; keduanya tidak ada pada musuh biasa dan ada pada boss. Boss battle juga tetap
"duel vs NPC", sehingga kemungkinan besar masih memenuhi bunyi soal (perlu dicek dengan brief Tahap 4).

Satu opsi tambahan yang murah jika brief menuntut planning *juga* tampil pada battle biasa: planner
hanya memilih **goal** (misalnya "habisi Monk"), dan goal itu masuk ke evaluasi minimax sebagai bonus
(`+k` bila target goal mati). Struktur battle biasa tidak berubah; ini bisa jadi eksperimen hibrid.

## 2. Pendekatan planning yang dipakai

Klasik ala AIMA bab Planning, dengan dua perluasan kecil yang dibutuhkan game:

1. **Representasi aksi STRIPS + fluent numerik.** Operator = (nama, parameter target, precondition,
   add-list, delete-list, efek numerik). Literal: `alive(u)`, `burning(u)`, `stunned(u)`,
   `enraged(boss)`, `shielded(boss)`, `phase2(boss)`, `regrow_used(boss)`. Numerik: `hp(u)`,
   `shield(boss)`. HP numerik diperlukan karena goal utama ("`hp(monk) <= 0`") tidak bisa
   dinyatakan secara proposisional tanpa kehilangan informasi.
2. **Forward state-space search** (progression) dari state abstrak saat ini ke goal, dengan tiga
   varian untuk eksperimen: BFS/uniform cost (h = 0), A* dengan *goal-count*, A* dengan heuristik
   domain `h_damage = ceil(sisa HP target / damage maksimum satu aksi)`. Opsional: **GraphPlan** pada
   proyeksi proposisional (HP didiskritkan ke bucket) sebagai pembanding klasik.
3. **Asumsi dunia saat merencanakan: player pasif** (relaxed adversary). Inilah yang membuat planner
   murah. Konsekuensinya ditangani di eksekusi:
4. **Execution monitoring + replanning.** Setiap giliran boss, langkah berikutnya dicek pada state
   *nyata* (precondition masih berlaku? goal masih relevan?). Jika ya, eksekusi; jika tidak, *plan
   repair* ringan (ganti target yang sama-skill) lalu *replan* penuh. Jumlah replan, panjang rencana,
   dan rasio "langkah dieksekusi sesuai rencana" menjadi metrik.
5. **Goal selection berbasis utilitas.** Kandidat goal (bagian 4.3) masing-masing direncanakan;
   rencana dinilai dengan `BattleEvaluator` pada state akhirnya. Skor default = **laju keuntungan per
   aksi boss**, `(V(akhir) − V(sekarang)) / panjang`: karena model relaxed mengabaikan player, setiap
   langkah tambahan adalah satu giliran gratis bagi player, sehingga rencana panjang harus membayarnya.
   (Mode `end_value`, `V(akhir) − λ·panjang`, dipertahankan untuk eksperimen; pada pengujian ia memilih
   "bunuh Ninja dalam 4 aksi" di atas "bunuh Monk dalam 2 aksi".) Ini menyambung ke evaluasi Tahap 2
   dan membuat boss memilih antara "bunuh healer", "setup AoE", atau "bertahan" secara terukur.

Fallback: jika tidak ada goal yang punya rencana ≤ `max_plan_length`, boss memakai minimax
(`MinimaxAI`) seperti NPC biasa. Dengan begitu boss tidak pernah macet.

## 3. Desain boss

Unit: **Giant Bamboo** (`giant_bamboo`, `is_boss = true`, elemen Wind, HP 120, sprite
`assets/Actor/Boss/GiantBamboo`). Field `is_boss` sudah ada di `UnitData` dan belum pernah dipakai.

| Skill | Target | Efek | Precondition | Catatan planning |
| --- | --- | --- | --- | --- |
| Root Slam | ENEMY | 6 dmg | - | aksi dasar, pengisi ult |
| Sap Surge | SELF | status `enraged` | ¬enraged | setup; tanpa damage |
| Bamboo Spear | ENEMY | 10 dmg; **24** bila enraged (menghabiskan enraged) | - | payoff tunggal; 24 > 2×10 sehingga setup terbayar |
| Thorn Storm | ALL_ENEMIES | 6 dmg + burn 2 ke semua (menghabiskan enraged) | enraged ∧ phase2 | payoff AoE, buka fase 2 |
| Harden Bark | SELF | shield 15 | shield = 0 | bertahan |
| Regrow | SELF | heal 25; memakai 1 potion NPC | hp < 50 % ∧ ¬regrow_used | sekali per battle; constraint potion CSP jadi aktif |

Fase: `phase2` menyala permanen saat HP boss < 50 % (ditandai di `begin_turn`). Ultimate boss
(bar penuh) = Thorn Storm versi 8 dmg tanpa prasyarat, agar mekanik ult yang ada tetap konsisten.

Rantai yang muncul: `Sap Surge → Bamboo Spear` (24) membunuh Ninja (22 HP) dalam 2 aksi, sedangkan dua
Spear biasa (20) tidak; Knight (32) jatuh dalam 3 aksi dengan rage (24+10) tetapi butuh 4 tanpa rage;
`Sap Surge → Thorn Storm` setelah fase 2 membakar semua hero; `Harden Bark` dulu bila Ninja ult penuh
(ancaman 30). Minimax kedalaman 4 melihat paling jauh 2 aksi boss; rangkaian 3 aksi hanya dilihat planner.
(Catatan implementasi: angka 20 pada draft awal membuat Surge+Spear = 2×Spear biasa, sehingga setup tidak
pernah terbayar; dinaikkan ke 24. HP boss 150 pada draft membuat semua otak, termasuk greedy, menang 100 %
melawan player alpha-beta kedalaman 2, sehingga tabel eksperimen datar; sweep HP 90/110/130 memilih 120.
Thorn Storm dinaikkan 4 → 6 karena goal "burn every hero" tidak pernah terpilih melawan goal kill.)

Encounter overworld: `WorldEnemy` baru `BambooKing` (`encounter_id = "bamboo_king"`, `enemy_party =
["giant_bamboo"]`), muncul setelah tiga encounter lain dikalahkan (`Game.defeated_encounters`), opsional.
Versi lanjutan: boss + 2 minion `evil_bamboo`; planner mengatur boss, CSP Tahap 3 mengatur minion.

## 4. Representasi planning

### 4.1 State abstrak (`PlanState`)

Dibangun dari `BattleSim` (`PlanState.from_sim`): himpunan literal + dictionary numerik untuk unit
hidup. Hanya atribut yang disentuh skill boss yang dimodelkan; sisanya diabaikan (abstraksi).
Burn tick (2 dmg ke hero terbakar pada awal giliran player) dimodelkan sebagai *efek kondisional*
yang menyertai setiap aksi boss, karena pasti terjadi di dunia relaxed.

### 4.2 Skema aksi dan grounding

`PlanOperator` (satu per skill boss) → `PlanAction` ter-grounding per target hidup. Precondition
disusun dari field skill baru (bagian 6) sehingga **planner dan BattleSim membaca sumber aturan yang
sama**; tes "model vs simulasi" memastikan prediksi HP planner sama dengan `BattleSim.apply` ketika
player pass (termasuk multiplier elemen dari `ElementKnowledgeBase`).

### 4.3 Kandidat goal

Diurutkan untuk tie-break, semuanya dicoba lalu dipilih berdasarkan utilitas (bagian 2.5):

1. `dead(h)` untuk setiap hero `h` yang bisa mati dalam ≤ `max_plan_length` aksi (prioritas healer
   Monk dan hero yang lemah terhadap Wind menurut KB elemen).
2. `∀h alive(h): burning(h)` (setup burn massal; hanya fase 2).
3. `shielded(boss) ∧ enraged(boss)` (bertahan sambil siap payoff; dipilih saat ada hero dengan ult
   penuh atau HP boss < 50 %).
4. `hp(boss) ≥ 50 %` via Regrow (hanya sekali).

### 4.4 Pencarian

A* forward; node = `PlanState`, biaya 1 per aksi, batas `max_plan_length` (default 4). Statistik yang
disimpan per keputusan (`PlanResult`): goal terpilih, rencana, node dibangkitkan/diekspansi, waktu,
heuristik, apakah fallback minimax dipakai. Semua tampil di debug overlay (F1) seperti `SearchResult`.

## 5. Eksekusi di dalam battle

`BossBrain` (per battle) menyimpan `current_plan`, `current_goal`, dan statistik eksekusi. Pada
`NpcTurn`, bila `Game.ai_config["boss_brain"] == "planner"` dan unit yang hidup adalah boss:

```
DECIDE(sim):
    if current_plan kosong or not STILL_VALID(current_plan, sim):
        replans += 1
        current_plan ← PLAN(sim)            # bagian 4; kosong → fallback minimax
    step ← pop_front(current_plan)
    steps_executed += 1
    return step.to_battle_action(sim)

STILL_VALID(plan, sim):                      # dua lapis pemantauan
    action monitoring: precondition(plan[0]) berlaku pada PlanState.from_sim(sim)
    plan monitoring:   memutar ulang seluruh sisa langkah pada state relaxed saat ini;
                       setiap langkah tetap applicable dan goal tercapai di akhirnya
                       (rencana yang "dibatalkan" player, mis. target di-heal, dibuang)
```

Alasan replan dicatat per keputusan: `no plan`, `plan finished`, `goal reached` (alami) atau
`precondition failed`, `goal unreachable by plan` (basi; dihitung sebagai *replans*). Penghitung per
battle: decisions, plans_made, replans, fallbacks, steps_executed, steps_continued (langkah yang berasal
dari rencana giliran sebelumnya; rasio ini mengukur seberapa banyak rencana selamat dari aksi player).

Dengan satu aksi per giliran (aturan Tahap 2 tidak diubah), rencana 3 langkah terbentang 3 giliran
boss + 3 giliran player, sehingga monitoring benar-benar diuji.

Mode otak boss (`Game.ai_config["boss_brain"]`, bisa diganti dari overlay F1): `minimax` (kontrol:
pipeline Tahap 3 CSP + minimax), `planner` (di atas), `hybrid` (langkah pertama dari setiap rencana
kandidat menjadi aksi akar minimax, yang memilih dengan memperhitungkan lawan; kelanjutan saran 5
Bab V). Pada uji autopilot melawan player naif, planner memenangkan boss battle dalam 20 giliran
dengan 10 langkah rencana, 60 % di antaranya lanjutan rencana giliran sebelumnya, tanpa replan basi.

## 6. Perubahan kode yang dibutuhkan

| File | Perubahan |
| --- | --- |
| `scripts/battle/skill_data.gd` | field baru: `requires: Array[String]`, `grants: Array[String]`, `consumes: Array[String]`, `power_if_user_enraged: int`, `once_per_battle: bool`, `only_if_user_hp_below: float`, `requires_phase2: bool` |
| `scripts/battle/unit_state.gd` | `flags: Dictionary` (enraged, phase2, used_<skill>) + clone |
| `scripts/battle/battle_sim.gd` | `usable_skills` memeriksa `requires/once/hp`; `apply_skill` menerapkan `grants/consumes/power_if_user_enraged`; `begin_turn` menyalakan `phase2`; event baru `status` untuk presentasi |
| `scripts/battle/roster.gd` | unit `giant_bamboo` + `all_ids` |
| `scripts/battle/plan_model.gd` (baru) | `PlanState`, `PlanOperator`, `PlanAction`, `from_sim`, `applicable`, `apply`, `holds_in_sim` |
| `scripts/battle/boss_planner.gd` (baru) | kandidat goal, A* (heuristik none = BFS / goal_count / damage), pruning batas bawah, skor `gain_rate`/`end_value`, `PlanResult` + statistik |
| `scripts/battle/boss_brain.gd` (baru) | mode minimax/planner/hybrid, eksekusi + action & plan monitoring + replanning + fallback minimax, `Decision` + penghitung |
| `scripts/battle/battle.gd` | `make_brain`, `has_boss`, cabang `NpcTurn._run_boss`; log "Boss plans: ..." |
| `scripts/battle/debug_overlay.gd` | panel PLANNING (goal, langkah dengan penanda, alasan replan, semua goal yang dicoba, statistik, totals), kontrol `boss_brain`, `plan_heuristic`, `plan_scoring`, `max_plan_length` |
| `scripts/game.gd` | `ai_config["boss_brain"]`, `["plan_heuristic"]`, `["plan_scoring"]`, `["max_plan_length"]` |
| `main.tscn`, `world.gd`, `world_enemy.gd` | encounter `BambooKing` (424, 328) dengan `requires_defeated` = tiga encounter lain; terkunci = tersembunyi dan nonaktif |
| `character_sprite.gd`, `battle_unit.gd` | dukungan sprite boss (strip horizontal 62 px, flip untuk menghadap kiri); label/bar mengikuti tinggi sprite; label status menampilkan flag |
| `tests/test_planning.gd` (dipanggil dari `test_battle.gd`) | model vs sim (acak, ~900 langkah), pencarian & heuristik, goal selection, rencana dapat dieksekusi, brain (lanjutan, plan monitoring, precondition, fallback, pass, hybrid) |
| `tests/test_battle.gd`, `tests/e2e_driver.gd` | aturan boss, boss battle autopilot lewat scene asli, gerbang encounter boss & sel walkable |
| `tests/experiments_planning.gd` + runner | bagian 7, menulis `docs/experiments_planning.md` |

## 7. Eksperimen (headless, seed tetap, lawan = alpha-beta kedalaman 2 seperti Tahap 2-3)

Dijalankan oleh `tests/experiments_planning.gd` (`godot --headless --path . res://tests/experiments_planning_runner.tscn`, ±3 menit; env `EXP_GAMES`, `EXP_POSITIONS`, `EXP_ONLY`, `EXP_BOSS_HP`). Hasil di `docs/experiments_planning.md`, analisis di `docs/laporan_tahap4.md`. Eksperimen 7 (hibrid pada battle biasa) tidak dikerjakan.

1. **Validitas model**: prediksi HP/status planner vs `BattleSim.apply` saat player pass, 40 posisi → target 100 % sama.
2. **Algoritma pencarian**: BFS vs A*(goal-count) vs A*(h_damage) [vs GraphPlan]: node, waktu, panjang rencana, optimalitas.
3. **Goal selection**: prioritas tetap vs utilitas; distribusi goal yang dipilih per fase.
4. **Eksekusi**: frekuensi replanning dan rasio langkah sesuai rencana vs `max_plan_length` 2/3/4/5 dan vs kekuatan player (kedalaman 1/2/3).
5. **Otak boss**: minimax d4 vs greedy vs planner vs hybrid: win rate, rata-rata giliran, sisa HP boss, waktu keputusan (30 pertandingan).
6. **Ablasi**: skill boss tanpa prasyarat (datar) → planner setara greedy; menunjukkan bahwa nilai planning datang dari struktur aksi.
7. **Hibrid pada battle biasa** (opsional): goal planner sebagai bonus evaluasi minimax; dibandingkan dengan pipeline Tahap 3.

## 8. Urutan implementasi

1. Aturan: field skill, flags, `BattleSim`, roster boss, tes aturan boss. (Hari 1)
2. `plan_model.gd` + tes model-vs-sim. (Hari 1-2)
3. `boss_planner.gd` BFS → A* → heuristik; tes rencana `Surge→Spear`. (Hari 2)
4. `boss_brain.gd` + integrasi `battle.gd` + overlay + encounter. (Hari 3)
5. Eksperimen + `docs/experiments_planning.md` + bab laporan. (Hari 4)
6. Opsional: GraphPlan, minion + CSP, hibrid battle biasa.

## 9. Pertanyaan terbuka

- Brief Tahap 4: apakah ada algoritma yang diwajibkan (GraphPlan? partial-order planning? HTN?).
  Desain ini memakai forward search + heuristik karena paling cocok dengan fluent numerik; GraphPlan
  bisa ditambah sebagai pembanding.
- Boss tunggal atau boss + minion pada versi pertama? (Rekomendasi: tunggal dulu.)
- Catatan: 10 tes aturan skill di `tests/test_battle.gd` sudah gagal di `origin/kbTahap1` karena
  multiplier elemen (Fire → Wind ×2, dll.) mengubah angka damage yang diharapkan tes; perlu diperbarui
  terpisah sebelum tes planning ditambahkan.
