extends CanvasLayer
class_name ItemPickupToast
## ItemPickupToast — a short "obtuviste tal cosa" banner in the bottom-left corner. Same
## fire-and-forget, non-blocking convention as AchievementToast: picking up a potion off the
## floor or out of a chest is incidental feedback, not a story beat, so it must never pause
## movement or wait for a keypress.

## Self-preload rather than referencing the bare class_name below — see the identical note in
## AchievementToast.gd. A global class isn't in the class cache until a project scan registers
## it, so a static factory referencing its own class_name fails the first time this script runs.
const _Self = preload("res://scripts/ui/ItemPickupToast.gd")

const DISPLAY_SECONDS := 1.8
const FADE_SECONDS := 0.4

var _panel: PanelContainer
var _name_label: Label

func _ready() -> void:
	layer = 96
	_build_ui()

func _build_ui() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.offset_left = 20
	root.offset_right = 420
	root.offset_top = -90
	root.offset_bottom = -20
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.06, 0.95)
	style.border_color = Color(0.55, 0.8, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	var header = Label.new()
	header.text = "Obtuviste"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.6, 0.75, 0.55))
	vbox.add_child(header)

	_name_label = Label.new()
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.8))
	vbox.add_child(_name_label)

## Call as `ItemPickupToast.show_at(some_node, "potion", 2)` — fire-and-forget, never awaited,
## so grabbing an item never holds up movement or the interaction that triggered it.
##
## Parented to the tree ROOT, not to `parent` — same rationale as AchievementToast: `parent`
## (the Pickup/floor-item node) may be hidden or freed well before this toast's ~2s lifetime is
## up, and freeing the parent would take this along with it mid-fade otherwise.
static func show_at(parent: Node, item_id: String, quantity: int) -> void:
	var toast = _Self.new()
	parent.get_tree().root.add_child(toast)
	var data = DataLoader.get_item(item_id)
	var item_name = str(data.get("name", item_id))
	toast._name_label.text = "%s x%d" % [item_name, quantity] if quantity > 1 else item_name

	var tree = toast.get_tree()
	var fade_in := toast.create_tween()
	fade_in.tween_property(toast._panel, "modulate:a", 1.0, 0.3)
	await tree.create_timer(DISPLAY_SECONDS).timeout
	var fade_out := toast.create_tween()
	fade_out.tween_property(toast._panel, "modulate:a", 0.0, FADE_SECONDS)
	await fade_out.finished
	toast.queue_free()
