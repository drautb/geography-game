extends RefCounted
class_name Pack
## A loaded map pack: its manifest plus resolved paths and parsed values. The engine
## drives the whole game from a Pack, so adding a region of the world is authoring a
## pack (see docs/PACK_FORMAT.md), not changing engine code.

const DEFAULT_FILL := Color(0.42, 0.55, 0.68)

var id := ""  # pack folder id, e.g. "us-states"
var dir := ""  # res:// path to the pack folder
var name := "Map"
var area_noun := "Area"
var point_noun := "Capital"
var group_noun := "Groups"
var left_inset := 0.0
var areas_path := ""
var points_path := ""  # "" when the pack has no points layer
var group_colors := {}  # group id -> Color
var group_order := []  # [{id, name}] in manifest order
var callouts := {}  # area code -> Vector2 label position


func has_points() -> bool:
    return points_path != ""


func has_groups() -> bool:
    return not group_order.is_empty()


## Base fill for a group, dimmed (desaturated + darkened) when disabled.
func group_color(group: String, enabled := true) -> Color:
    var c: Color = group_colors.get(group, DEFAULT_FILL)
    if enabled:
        return c
    var dim := c.lerp(Color(0.16, 0.19, 0.24), 0.68)
    return Color(dim.r, dim.g, dim.b, 1.0)


## Read the registry packs/index.json into an ordered list of {id, name}.
static func list_packs() -> Array:
    var out: Array = []
    var text := FileAccess.get_file_as_string("res://packs/index.json")
    if text.is_empty():
        push_error("Pack: could not read packs/index.json")
        return out
    var data = JSON.parse_string(text)
    if typeof(data) != TYPE_DICTIONARY or not data.has("packs"):
        return out
    for p in data["packs"]:
        out.append({"id": String(p.get("id", "")), "name": String(p.get("name", ""))})
    return out


## Load a pack from packs/<pack_id>/pack.json. Returns a Pack, or null on error.
static func load_pack(pack_id: String):
    var base := "res://packs/%s" % pack_id
    var manifest_path := "%s/pack.json" % base
    var text := FileAccess.get_file_as_string(manifest_path)
    if text.is_empty():
        push_error("Pack: could not read %s" % manifest_path)
        return null
    var m = JSON.parse_string(text)
    if typeof(m) != TYPE_DICTIONARY:
        push_error("Pack: invalid manifest %s" % manifest_path)
        return null

    var pack = load("res://scripts/pack.gd").new()
    pack.id = pack_id
    pack.dir = base
    pack.name = String(m.get("name", pack_id))
    pack.area_noun = String(m.get("area_noun", "Area"))
    pack.point_noun = String(m.get("point_noun", "Capital"))
    pack.group_noun = String(m.get("group_noun", "Groups"))
    pack.left_inset = float(m.get("left_inset", 0))
    pack.areas_path = "%s/%s" % [base, String(m.get("areas", "areas.geojson"))]
    if m.has("points"):
        pack.points_path = "%s/%s" % [base, String(m["points"])]

    for g in m.get("groups", []):
        var gid := String(g.get("id", ""))
        pack.group_order.append({"id": gid, "name": String(g.get("name", gid))})
        pack.group_colors[gid] = Color(String(g.get("color", "#6b8cb8")))

    for code in m.get("callouts", {}):
        var xy: Array = m["callouts"][code]
        pack.callouts[String(code)] = Vector2(float(xy[0]), float(xy[1]))

    return pack
