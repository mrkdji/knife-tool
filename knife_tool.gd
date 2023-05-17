@tool
extends EditorPlugin

# TODO:
# add snapping to vertexes, handle the case where intersection point a or b is a vertex of the polygon
# handle self intersecting cuts / holes
# handle lines and paths


signal cut_completed;

const POLYGON_EDITOR_CLASSES = [
"Polygon2DEditor",
"CollisionPolygon2DEditor",
"NavigationPolygonEditor",
#"Line2DEditor",
#"Path2DEditor"
];

const KNIFE_TOOL_BUTTON_SCENE = preload("res://addons/knife-tool/knife_tool_button.tscn");

const POINT_SIZE = 5;
const LINE_WIDTH = 3;

const CONSUME = true;
const DONT_CONSUME = false;

# used when comparing floats
const THRESHOLD = 1;

enum States {
	WAIT,
	READY,
	SLICE
}

var knife_tool_button = null;

var current_state;
var selected_polygon = null;
var points = [];
var mouse_position = Vector2.ZERO;


func _enter_tree():
	
	get_editor_interface().get_selection().selection_changed.connect(self.on_editor_selection_changed)
	
	knife_tool_button = KNIFE_TOOL_BUTTON_SCENE.instantiate();
	knife_tool_button.toggled.connect(on_knife_button_toggled);
	cut_completed.connect(knife_tool_button.set_pressed.bind(false));
	
	add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, knife_tool_button);
	knife_tool_button.hide();
	
	var editors = get_polygon_editors();
	for e in editors:
		for c in e.get_children():
			if c is Button:
				c.pressed.connect(user_changed_tool);
				knife_tool_button.pressed.connect(c.set_pressed_no_signal.bind(false));


func _exit_tree():
	get_editor_interface().get_selection().selection_changed.disconnect(on_editor_selection_changed);
	remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, knife_tool_button);


func user_changed_tool():
	knife_tool_button.set_pressed_no_signal(false);
	current_state = States.WAIT;
	points.clear();


func get_polygon_editors():
	var parent = knife_tool_button.get_parent();
	var editors = [];
		
	for c in parent.get_children():
		if is_node_class_one_of(c, POLYGON_EDITOR_CLASSES):
			editors.push_back(c);

	return editors;


func on_knife_button_toggled(new_state):

	if current_state == States.SLICE:
		confirm_slice();

	if new_state:
		current_state = States.READY;
	else:
		current_state = States.WAIT;


func on_editor_selection_changed():

	var nodes = get_editor_interface().get_selection().get_selected_nodes();
	knife_tool_button.button_pressed = false;

	if nodes.size() == 1 and _handles(nodes.front()):
		selected_polygon = nodes.front();
	else:
		selected_polygon = null;
		current_state = States.WAIT;
		

func _make_visible(visible):
	print("calling make visible")
	if visible:
		knife_tool_button.show();
	else:
		knife_tool_button.hide();


func is_valid_node_for_knife_tool(n):
	return (n is Polygon2D) or (n is NavigationRegion2D) or (n is CollisionPolygon2D);


func _handles(object):
	print("calling handles")
	if is_valid_node_for_knife_tool(object):
		print("We handle this object")
		selected_polygon = object;
		return true;
#	elif object.get_class() == "MultiNodeEdit":
#		var can_handle = true;
#		for node in get_editor_interface().get_selection().get_selected_nodes():
#			if not is_valid_node_for_knife_tool(node):
#				can_handle = false;
#				break;
#		return can_handle;
	else:
		print("we do not handle object of type " + str(object))
		selected_polygon = null;
		current_state = States.WAIT;
		return false;


func from_editor_to_2d_scene_coordinates( position ):
	return selected_polygon.get_viewport_transform().affine_inverse() * position;

func from_2d_scene_to_editor_coordinates( position ):
	return selected_polygon.get_viewport_transform() * position;


func _forward_canvas_gui_input(event) -> bool:

	if current_state == States.WAIT: 
		return DONT_CONSUME;
	
	if event is InputEventMouse:
		mouse_position = event.position;

	if current_state == States.SLICE:
		update_overlays();
		pass;
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			current_state = States.SLICE;

			var mouse_pos_in_scene = selected_polygon.get_global_mouse_position();
			points.push_back(event.position);
			return CONSUME;

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_slice();
			return CONSUME;
		

	if current_state == States.SLICE:

		if event is InputEventKey:
			
			if event.physical_keycode == KEY_ENTER and event.pressed:
				confirm_slice();
				return CONSUME;
			
			if event.physical_keycode == KEY_ESCAPE and event.pressed:
				return CONSUME;
				
	return DONT_CONSUME;


func _forward_canvas_draw_over_viewport(overlay):

	if not points.is_empty():
		for i in points.size() - 1:
			overlay.draw_circle(points[i], POINT_SIZE, Color.RED);
			overlay.draw_line(points[i], points[i+1], Color.RED, LINE_WIDTH);
		
		overlay.draw_circle(points.back(), POINT_SIZE, Color.RED);
		overlay.draw_line(points.back(), mouse_position, Color.RED, LINE_WIDTH);


func confirm_slice():
	
	if not is_instance_valid(selected_polygon):
		abort_slice("Selected polygon instance is invalid")
		return;

	var scene_points = points.duplicate();
	for i in scene_points.size():
		scene_points[i] = from_editor_to_2d_scene_coordinates(scene_points[i]);

	# transform
	var polygon = get_polygon_data(selected_polygon);
	for i in polygon.size():
		polygon[i] = selected_polygon.get_global_transform() * polygon[i];

	# Check if it is hole:
#	var are_all_points_inside_selected_polygon = true;
#	for p in scene_points:
#		if not Geometry.is_point_in_polygon(p, polygon):
#			are_all_points_inside_selected_polygon = false;
#			break;
#
#	# this only works for convex polygons
#	if are_all_points_inside_selected_polygon:
#		if scene_points.size() < 3:
#
#			abort_slice("Invalid input: hole must have at least 3 points");
#			return;
#
#			var hole_points = scene_points.duplicate();
#
#			var hole_orientation = get_polygon_orientation(scene_points);
#			var polygon_orientation = get_polygon_orientation(polygon);
#			var step = hole_orientation * polygon_orientation;
#
#			var hole = selected_polygon.duplicate(true);
#			set_polygon_data(hole, scene_points);
#
#			if step > 0:
#				hole_points.invert();

	if (Geometry2D.is_point_in_polygon(scene_points.front(), polygon) or 
		Geometry2D.is_point_in_polygon(scene_points.back(), polygon)):
			abort_slice("Invalid input: Both start and end point of the cut must lie outside the polygon");
			return;
	


	# returns an array of clipped polylines
	var intersections : Array = Geometry2D.intersect_polyline_with_polygon(scene_points, polygon);
	
	if intersections.is_empty():
		abort_slice("Cut didn't intersect the selected polygon");
		return;

	var polygons_to_check = [];
	var polygons_to_check_for_next_iteration = [selected_polygon];

	for intersection_index in intersections.size():
		polygons_to_check = polygons_to_check_for_next_iteration;
		polygons_to_check_for_next_iteration = [];

		for current_polygon in polygons_to_check:

			var intersection = intersections[intersection_index];
			
			if intersection_index > 0:
				polygon = get_polygon_data(current_polygon);
				for i in polygon.size():
					polygon[i] = current_polygon.get_global_transform() * polygon[i];
				intersection = Geometry2D.intersect_polyline_with_polygon(intersection, polygon);
				assert(intersection.size() < 2);

				if intersection.is_empty():
					print("Empty intersection, pushing polygon for next iteration")
					polygons_to_check_for_next_iteration.push_back(current_polygon);
					continue;

				elif intersection.size() == 1:
					intersection = intersection.front();

			# check if the polyline is self-intersecating
			# I assume that adjacent segments of the polyline don't intersecate (possible only if they are superimposed)
			# TODO: disallow superimposed segments.
			var self_intersect = false;
			for i in range(0, intersection.size() - 2, 1):
				for j in range(i + 2, intersection.size() - 1, 1):
					var res = Geometry2D.segment_intersects_segment(
						intersection[i], intersection[i+1],
						intersection[j], intersection[j+1]);
					
					if res != null:
						self_intersect = true;
		
			if self_intersect:
				abort_slice("Cut does self-intersect inside the polygon!");
				return;
	
			var intersection_point_a = intersection[0];
			var intersection_point_b = intersection[intersection.size() - 1];

			var does_intersect = false;
			for extreme in [intersection_point_a, intersection_point_b]:
				for i in polygon.size():
					var next_index = posmod(i + 1, polygon.size());

					var point_on_segment = Geometry2D.get_closest_point_to_segment(
						extreme,
						polygon[i], polygon[next_index]);

					# check if the cut pass through the polygon vertices
					if (polygon[i].distance_to(extreme) < THRESHOLD or
						polygon[next_index].distance_to(extreme) < THRESHOLD):
						does_intersect = true;

					elif point_on_segment.distance_to(extreme) < THRESHOLD:
						does_intersect = true;
						polygon.insert(next_index, point_on_segment);
						break;

			if not does_intersect:
				polygons_to_check_for_next_iteration.push_back(current_polygon);
				continue;

			var intersection_point_a_index = 0;
			while polygon[intersection_point_a_index].distance_to(intersection_point_a) > THRESHOLD:
				intersection_point_a_index += 1;

			for step in [1, -1]:
				var polyslice = [];

				var index = intersection_point_a_index;
				while polygon[index].distance_to(intersection_point_b) > THRESHOLD:
					polyslice.append(polygon[index]);
					index = posmod(index + step, polygon.size());
				
				polyslice.append(intersection_point_b);
				
				var internal_points_index = intersection.size() - 2;
				while internal_points_index > 0:
					polyslice.append( intersection[internal_points_index]);
					internal_points_index -= 1;
		
				for i in polyslice.size():
					polyslice[i] = current_polygon.get_global_transform().inverse() * polyslice[i];
				
				polygons_to_check_for_next_iteration.push_back(
					create_new_polygon(current_polygon, polyslice)
				);
			
			if current_polygon != selected_polygon:
				current_polygon.free();

	var polygons_added_by_knife_tool = polygons_to_check_for_next_iteration;
	var undo_redo = get_undo_redo();
	var parent = selected_polygon.get_parent();

	undo_redo.create_action("Sliced Polygon");
	
	undo_redo.add_undo_reference(selected_polygon);
	for p in polygons_added_by_knife_tool:
		undo_redo.add_do_reference(p);
		parent.remove_child(p);
	
	undo_redo.add_do_method(self, "do_split_polygon", selected_polygon, parent, polygons_added_by_knife_tool);
	undo_redo.add_undo_method(self, "undo_split_polygon", selected_polygon, parent, polygons_added_by_knife_tool);
	undo_redo.commit_action();


	update_overlays();
	
	points.clear();
	current_state = States.READY;

	emit_signal("cut_completed");
	

func do_split_polygon(former, parent, slices):
	var is_scene_instance = not former.scene_file_path.is_empty();
	for s in slices:
		parent.add_child(s);
		if is_scene_instance:
			s.owner = get_editor_interface().get_edited_scene_root();
		else:
			set_node_owner_recursively(s, get_editor_interface().get_edited_scene_root());
	
	parent.remove_child(former);


func undo_split_polygon(former, parent, slices):
	for s in slices:
		parent.remove_child(s);

	parent.add_child(former);
	former.owner = get_editor_interface().get_edited_scene_root();


func create_new_polygon(current_polygon, new_polygon_data):
	var centroid = origin_to_geometry(new_polygon_data);
	var parent = current_polygon.get_parent();
	var new_polygon;
	
	var is_scene_instance = not current_polygon.scene_file_path.is_empty();
	if is_scene_instance:
		new_polygon = load( current_polygon.scene_file_path ).instantiate();
		new_polygon.global_position = current_polygon.global_position;
	else:
		new_polygon = current_polygon.duplicate(true);

	set_polygon_data(new_polygon, new_polygon_data);

	parent.add_child(new_polygon);
	new_polygon.global_position += centroid;

	# this way we can successfully duplicate children nodes;
	if is_scene_instance:
		new_polygon.owner = get_editor_interface().get_edited_scene_root();
	else:
		set_node_owner_recursively(new_polygon, get_editor_interface().get_edited_scene_root());

	return new_polygon;


func abort_slice(error = ""):
	if not error.is_empty():
		printerr(error);
	cancel_slice();

func cancel_slice():
	points.clear();
	current_state = States.READY;


###########################################################################
############################### UTILS #####################################
###########################################################################

static func is_node_class_one_of(node, classes):
	for c in classes:
		if node.is_class(c):
			return true;
	return false;


static func set_polygon_data(node, polygon_data):
	if node is NavigationRegion2D:
		var navigation_polygon = NavigationPolygon.new();
		navigation_polygon.add_outline(polygon_data);
		navigation_polygon.make_polygons_from_outlines();
		node.navigation_polygon = navigation_polygon;
	else:
		node.polygon = polygon_data;


static func get_polygon_data(node):
	if node is NavigationRegion2D:
		assert(node.navigation_polygon.get_outline_count() == 1, "we can only handle connected navigation polygon instances");
		return node.navigation_polygon.get_outline(0);
	
	return node.polygon;


static func get_polygon_orientation(polygon):
	return 1 if Geometry2D.is_polygon_clockwise(polygon) else -1;


static func origin_to_geometry(polygon_data):
	# centering resulting polygons origin to their geometry
	var centroid = Vector2.ZERO;
	for i in polygon_data.size():
		centroid += polygon_data[i];

	centroid /= polygon_data.size();

	for i in polygon_data.size():
		polygon_data[i] -= centroid;
	
	return centroid;
	

static func set_node_owner_recursively(node, o):
	node.owner = o;
	for c in node.get_children():
		set_node_owner_recursively(c, o);

###########################################################################
###########################################################################
###########################################################################
