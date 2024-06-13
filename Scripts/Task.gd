extends Object

var func_ref

func _init(func_ref):
	self.func_ref = func_ref

func execute():
	func_ref.call()
