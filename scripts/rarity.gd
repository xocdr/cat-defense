class_name Rarity
extends RefCounted

## Cosmetic rarity tier derived from a cat's character index. Each tier
## spans 3 consecutive characters (C1-3, C4-6, ...); power already comes
## from the existing per-level damage growth, this is visual only.

enum Tier { COMMON, RARE, EPIC, LEGENDARY, DEMON_GOD }

const CHARACTERS_PER_TIER := 3
const AURA_SIZE := 160

static var _aura_cache: Dictionary = {}

static func tier_for_character(char_index: int) -> Tier:
	@warning_ignore("integer_division")
	return clampi((char_index - 1) / CHARACTERS_PER_TIER, 0, Tier.DEMON_GOD as int) as Tier

static func first_character_for_tier(tier: Tier) -> int:
	return tier * CHARACTERS_PER_TIER + 1

static func last_character_for_tier(tier: Tier) -> int:
	return first_character_for_tier(tier) + CHARACTERS_PER_TIER - 1

static func color_for_tier(tier: Tier) -> Color:
	match tier:
		Tier.COMMON:
			return Color(0.78, 0.78, 0.8)
		Tier.RARE:
			return Color(0.25, 0.85, 0.35)
		Tier.EPIC:
			return Color(0.25, 0.55, 1.0)
		Tier.LEGENDARY:
			return Color(0.65, 0.3, 0.95)
		Tier.DEMON_GOD:
			return Color(1.0, 0.82, 0.15)
	return Color.WHITE

static func name_for_tier(tier: Tier) -> String:
	match tier:
		Tier.COMMON:
			return "Common"
		Tier.RARE:
			return "Rare"
		Tier.EPIC:
			return "Epic"
		Tier.LEGENDARY:
			return "Legendary"
		Tier.DEMON_GOD:
			return "Demon God"
	return ""

static func aura_texture(tier: Tier) -> GradientTexture2D:
	if _aura_cache.has(tier):
		return _aura_cache[tier]
	var color := color_for_tier(tier)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.9),
		Color(color.r, color.g, color.b, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = AURA_SIZE
	tex.height = AURA_SIZE
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_aura_cache[tier] = tex
	return tex
