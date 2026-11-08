class_name ElementKnowledgeBase
extends RefCounted

# Daftar empat elemen yang digunakan dalam game
const ELEMENTS = [
	"Fire",
	"Water",
	"Electric",
	"Wind"
]

# Kategori hubungan elemen
const STRENGTH = "Strength"
const WEAKNESS = "Weakness"

# Tabel relasi elemen
# TRUE  = elemen penyerang tidak lemah terhadap target
# FALSE = elemen penyerang lemah terhadap target
const ELEMENT_TABLE = {
	"Fire": {
		"Fire": true,
		"Water": false,
		"Electric": true,
		"Wind": true
	},

	"Water": {
		"Fire": true,
		"Water": true,
		"Electric": false,
		"Wind": true
	},

	"Electric": {
		"Fire": true,
		"Water": true,
		"Electric": true,
		"Wind": false
	},

	"Wind": {
		"Fire": false,
		"Water": true,
		"Electric": true,
		"Wind": true
	}
}

# Mengambil hubungan antara elemen penyerang dan elemen target
static func get_relation(attacker_element: String, target_element: String) -> Variant:

	# Memeriksa apakah elemen penyerang tersedia
	if not ELEMENT_TABLE.has(attacker_element):
		push_error("Elemen penyerang tidak valid: " + attacker_element)
		return null

	# Memeriksa apakah elemen target tersedia
	if not ELEMENT_TABLE[attacker_element].has(target_element):
		push_error("Elemen target tidak valid: " + target_element)
		return null

	# Mengambil nilai TRUE atau FALSE dari tabel
	return ELEMENT_TABLE[attacker_element][target_element]

# Menentukan status elemen penyerang terhadap target
static func get_element_status(attacker_element: String, target_element: String) -> Variant:
	var relation = get_relation(attacker_element, target_element)

	# Jika elemen tidak valid
	if relation == null:
		return null

	# TRUE berarti Strength
	if relation:
		return STRENGTH

	# FALSE berarti Weakness
	return WEAKNESS
