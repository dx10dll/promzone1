class_name WallKinds
extends RefCounted
## Вспомогательные проверки типов стен для отрисовки (1.12: бетон, сэндвич-панели, перегородки, стальные двери).


## Глухая стена: кирпич, бетон, сэндвич-панель, перегородка.
static func is_plain(v: int) -> bool:
	return v == World.W_BRICK or v == World.W_CONCRETE or v == World.W_SANDWICH or v == World.W_PARTITION or v == World.W_SILICATE or v == World.W_GASBLOCK


static func is_door(v: int) -> bool:
	return v == World.W_DOOR or v == World.W_METAL_DOOR or v == World.W_GLASS_DOOR or v == World.W_DOOR_BROWN or v == World.W_DOOR_GREEN


## Стена помещения (глухая, окно, дверь, ворота) — не забор.
static func is_room_wall(v: int) -> bool:
	return is_plain(v) or v == World.W_WINDOW or is_door(v) or is_gate(v)


static func is_gate(v: int) -> bool:
	return v == World.W_GATE or v == World.W_GATE_WARM


static func is_fence(v: int) -> bool:
	return v == World.W_FENCE or v == World.W_FENCE_GATE
