extends Node2D
## 讓 main.gd 用函式直接畫在這一層上
var fn: Callable

func _draw() -> void:
	if fn.is_valid():
		fn.call(self)
