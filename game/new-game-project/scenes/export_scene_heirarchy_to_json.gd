extends Node3D

func _ready():
	# This saves the file to your project folder
	# You can change "hierarchy.json" to whatever name you like
	var save_path = "res://hierarchy.json"
	
	export_hierarchy_to_json(self, save_path)
	
	# Print the absolute path so you can find it for your AI
	print("--- Hierarchy Exported! ---")
	print("File location: ", ProjectSettings.globalize_path(save_path))

func export_hierarchy_to_json(root_node: Node, path: String):
	var data = serialize_node(root_node)
	var json_string = JSON.stringify(data, "\t") # Tab-indented for AI readability
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	else:
		print("Error: Could not save file to ", path)

func serialize_node(node: Node) -> Dictionary:
	var node_info = {
		"name": node.name,
		"type": node.get_class(),
		"script": "",
		"children": []
	}
	
	# Check for attached script
	var script = node.get_script()
	if script:
		# This gives the AI the path to the .gd file (e.g., res://Player.gd)
		node_info["script"] = script.resource_path 
		
	# Recursively add children
	for child in node.get_children():
		node_info["children"].append(serialize_node(child))
		
	return node_info
