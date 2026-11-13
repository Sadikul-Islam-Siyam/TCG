class_name ElementData
extends Resource
## Phase 0 (T0.2): Single-source-of-truth Resource definition for Elements,
## Omni dice, and Physical / Piercing damage channels.

@export var id: StringName = &""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var light_color: Color = Color.WHITE
@export var dark_color: Color = Color.BLACK
@export var icon_small: Texture2D = null     # 18x18 crisp element crest
@export var icon_large: Texture2D = null     # 48x48 crisp element crest
@export var icon: Texture2D = null           # Alias to icon_large (T0.2 schema compatibility)
@export var die_face: Texture2D = null       # Pre-rendered hexagonal beveled die token
@export var vfx: PackedScene = null          # Optional particle preset override
@export var hit_sound: AudioStream = null    # Hit SFX stream reference
@export var can_attach: bool = false         # Only Pyro, Hydro, Cryo, Electro attach cleanly
@export var shape_tag: String = "crest"      # Colorblind distinguishable geometry tag

