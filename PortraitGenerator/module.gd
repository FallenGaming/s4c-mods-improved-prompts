extends Node

var path = get_script().get_path().get_base_dir()

func _init():
	pass

func extend_nodes():
	var slave_node = modding_core.get_spec_node(input_handler.NODE_SLAVEMODULE)
	modding_core.extend_node(slave_node, path + '/src/extended_CharInfoMainModuleVision.gd')

func load_tables():
    pass
