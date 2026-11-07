extends Node3D

const ROAD := 32.0
const LIMIT := 110.0
var rng := RandomNumberGenerator.new()
var player: CharacterBody3D
var shape: CollisionShape3D
var rig: XROrigin3D
var camera: XRCamera3D
var left: XRController3D
var right: XRController3D
var xr_active := false
var car: Node3D
var driving := false
var car_yaw := 0.0
var speed := 0.0
var snap_ready := true
var desktop_pitch := 0.0
var hud: Label3D
var hint: Label3D
var marker: Node3D
var target := Vector3(0, 0, 6)
var pickup := Vector3(0, 0, 6)
var job := 0
var carrying := false
var cash := 0
var health := 100.0
var heat := 0.0
var escape_time := 0.0
var elapsed := 0.0
var message := "Welcome to Neon Borough"
var message_until := 9.0
var police: Array[Dictionary] = []
var traffic: Array[Dictionary] = []
var deliveries: Array[Vector3] = [Vector3(-64,0,-64),Vector3(64,0,64),Vector3(-96,0,32),Vector3(32,0,-96)]
var destinations: Array[String] = ["NORTH DOCKS", "SUNSET EXCHANGE", "WEST WAREHOUSE", "SKYLINE GARAGE"]
var last_bust := -20.0
var last_sound := 0.0
var synth: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var tone_phase := 0.0
var tone_time := 0.0
var tone_frequency := 440.0
var smoke_test := false
var tick_count := 0
var material_cache: Dictionary = {}

func _ready() -> void:
	rng.seed = 5407
	smoke_test = "--smoke-test" in OS.get_cmdline_user_args()
	load_progress()
	create_world()
	batch_boxes(self)
	batch_boxes(car)
	for item in traffic:
		batch_boxes(item.node)
	for item in police:
		batch_boxes(item.node)
	create_player()
	create_hud()
	create_audio()
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		xr_active = true
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 72
	else:
		camera.position.y = 1.65
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	update_marker()
	if smoke_test:
		call_deferred("run_smoke_test")

func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := color.to_html()+str(glow)
	if material_cache.has(key):
		return material_cache[key]
	var m := StandardMaterial3D.new()
	material_cache[key] = m
	m.albedo_color = color
	m.roughness = 0.85
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, solid: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		var coll := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = size
		coll.shape = s
		body.position = pos
		body.add_child(coll)
		parent.add_child(body)
	return mesh

func label3(parent: Node3D, text_value: String, pos: Vector3, size: int = 40, tint: Color = Color.WHITE) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.position = pos
	label.font_size = size
	label.pixel_size = 0.008
	label.modulate = tint
	label.outline_size = 7
	parent.add_child(label)
	return label

func create_world() -> void:
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("172b45")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("abc8ed")
	settings.ambient_light_energy = 0.7
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = settings
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35,-28,0)
	sun.light_color = Color("ffd8ad")
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	add_child(sun)
	var asphalt := material(Color("293747"))
	var pavement := material(Color("576477"))
	var paint := material(Color("d6bb7d"),0.2)
	var turquoise := material(Color("26d7c4"),1.3)
	var pink := material(Color("f572a8"),1.3)
	var window_mat := material(Color("84c4da"),0.4)
	box(self,Vector3(0,-0.3,0),Vector3(224,0.6,224),asphalt,true)
	for i in range(-3,4):
		for j in range(-13,14):
			box(self,Vector3(i*ROAD,0.015,j*8),Vector3(0.18,0.03,3.5),paint)
			box(self,Vector3(j*8,0.018,i*ROAD),Vector3(3.5,0.03,0.18),paint)
	for x in range(-3,3):
		for z in range(-3,3):
			var center := Vector3(x*ROAD+16,0,z*ROAD+16)
			box(self,center+Vector3(0,0.08,0),Vector3(22,0.16,22),pavement)
			for dx in [-5.5,5.5]:
				for dz in [-5.5,5.5]:
					var height := rng.randf_range(7.0,29.0)
					var pos := center+Vector3(dx,height/2.0,dz)
					var palette: Array[Color] = [Color("33415e"),Color("3a5368"),Color("4a4262"),Color("4b606e"),Color("344d5b"),Color("524f69")]
					var color: Color = palette[rng.randi_range(0,5)]
					box(self,pos,Vector3(9,height,9),material(color),true)
					box(self,pos+Vector3(0,height/2.0,0),Vector3(9.25,0.22,9.25),turquoise if (x+z)%2==0 else pink)
					# One mesh per facade stripe keeps the city light enough for mobile VR.
					for floor_y in range(3,int(height)-1,4):
						box(self,Vector3(pos.x,floor_y,pos.z-4.52),Vector3(6.5,0.7,0.04),window_mat)
						box(self,Vector3(pos.x-4.52,floor_y,pos.z),Vector3(0.04,0.7,6.5),window_mat)
	for x in [-112,112]:
		box(self,Vector3(x,2,0),Vector3(1,4,224),pavement,true)
	for z in [-112,112]:
		box(self,Vector3(0,2,z),Vector3(224,4,1),pavement,true)
	# Parked player car, contract terminal and a physical instruction board.
	car = create_car(Color("ebad54"))
	car.position = Vector3(3.8,0,0)
	var kiosk := Node3D.new()
	add_child(kiosk)
	kiosk.position = pickup
	box(kiosk,Vector3(0,0.85,0),Vector3(1.3,1.7,0.55),material(Color("123944")),true)
	box(kiosk,Vector3(0,1.3,0.3),Vector3(1.1,0.5,0.03),turquoise)
	label3(kiosk,"COURIER TERMINAL",Vector3(0,2.3,0),25,Color("51ffdf"))
	var board := Node3D.new()
	add_child(board)
	board.position = Vector3(0,0,13)
	board.rotation.y = PI
	box(board,Vector3(0,2.7,0),Vector3(9,4.7,0.15),material(Color("101e30")))
	label3(board,"NEON BOROUGH",Vector3(0,4.3,0.1),65,Color("45f3d2"))
	label3(board,"V R   /   S T R E E T   C O U R I E R",Vector3(0,3.55,0.1),25,Color("ffbd64"))
	label3(board,"LEFT STICK  Move / steer & reverse\nRIGHT TRIGGER  Accelerate    GRIP  Brake\nA  Enter car / exit / collect / deliver\nRIGHT STICK  Snap turn    B  Return to hub\nFollow the cyan beacon. Lose the police to deliver.\nCash is saved automatically.",Vector3(0,2.1,0.1),25)
	for i in range(6):
		var taxi := create_car(Color.from_hsv(float(i)/6.0,0.55,0.85))
		var lane := -64.0+float(i%5)*32.0
		taxi.position = Vector3(-90+i*26,0,lane+3.0)
		taxi.rotation.y = -PI/2
		traffic.append({"node":taxi,"lane":lane,"dir":1.0 if i%2==0 else -1.0})
	for i in range(2):
		var cop := create_car(Color("e6edf5"),true)
		cop.position = Vector3(-96+i*192,0,-96)
		police.append({"node":cop,"waypoint":cop.position,"light":cop.get_node("Siren")})
	marker = Node3D.new()
	add_child(marker)
	box(marker,Vector3(0,8,0),Vector3(0.18,16,0.18),turquoise)
	for sx in [-1,1]:
		box(marker,Vector3(sx*2,0.08,0),Vector3(0.14,0.1,4),turquoise)
		box(marker,Vector3(0,0.08,sx*2),Vector3(4,0.1,0.14),turquoise)
	label3(marker,"CONTRACT",Vector3(0,3.5,0),30,Color("5cffdd"))

func create_car(color: Color, cop: bool = false) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var bodymat := material(color)
	var black := material(Color("111b2a"))
	box(node,Vector3(0,0.55,0),Vector3(1.85,0.55,3.8),bodymat)
	box(node,Vector3(0,0.91,1.1),Vector3(1.7,0.23,1.15),bodymat)
	box(node,Vector3(0,0.89,-1.28),Vector3(1.7,0.25,1.1),bodymat)
	box(node,Vector3(0,1.77,0.05),Vector3(1.8,0.12,1.95),bodymat)
	for side in [-0.82,0.82]:
		for end in [-0.85,0.95]:
			box(node,Vector3(side,1.36,end),Vector3(0.09,0.8,0.1),bodymat)
	for side in [-0.96,0.96]:
		for end in [-1.15,1.15]:
			box(node,Vector3(side,0.37,end),Vector3(0.22,0.62,0.62),black)
	for side in [-0.63,0.63]:
		box(node,Vector3(side,0.65,-1.92),Vector3(0.38,0.18,0.03),material(Color("ffeca8"),1.2))
		box(node,Vector3(side,0.65,1.92),Vector3(0.38,0.18,0.03),material(Color("fa526b"),1.0))
	box(node,Vector3(0,0.97,-0.7),Vector3(1.6,0.13,0.3),black)
	if cop:
		box(node,Vector3(0,0.75,0),Vector3(1.9,0.18,2),black)
		var siren := box(node,Vector3(0,1.93,0),Vector3(1.1,0.18,0.3),material(Color("407aff"),2.0))
		siren.name = "Siren"
	return node

func create_player() -> void:
	player = CharacterBody3D.new()
	add_child(player)
	player.position = Vector3(3.8,0.1,6)
	shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	player.add_child(shape)
	rig = XROrigin3D.new()
	player.add_child(rig)
	camera = XRCamera3D.new()
	camera.near = 0.08
	camera.far = 240.0
	rig.add_child(camera)
	left = XRController3D.new()
	left.tracker = &"left_hand"
	rig.add_child(left)
	right = XRController3D.new()
	right.tracker = &"right_hand"
	rig.add_child(right)
	right.button_pressed.connect(_right_button)
	left.button_pressed.connect(_left_button)
	for controller in [left,right]:
		box(controller,Vector3(0,-0.025,0),Vector3(0.065,0.065,0.15),material(Color("3ef4d4"),0.4))

func create_hud() -> void:
	hud = Label3D.new()
	hud.font_size = 30
	hud.pixel_size = 0.0014
	hud.position = Vector3(0,-0.31,-1.5)
	hud.no_depth_test = true
	hud.outline_size = 9
	camera.add_child(hud)
	hint = Label3D.new()
	hint.font_size = 26
	hint.pixel_size = 0.0015
	hint.position = Vector3(0,0.32,-1.6)
	hint.modulate = Color("74ffe0")
	hint.no_depth_test = true
	hint.outline_size = 8
	camera.add_child(hint)

func create_audio() -> void:
	synth = AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.12
	synth.stream = generator
	synth.volume_db = -23.0
	add_child(synth)
	synth.play()
	playback = synth.get_stream_playback()

func beep(freq: float, duration: float = 0.13) -> void:
	tone_frequency = freq
	tone_time = duration

func _right_button(action: String) -> void:
	if action == "ax_button":
		interact()
	elif action == "by_button":
		return_hub()

func _left_button(action: String) -> void:
	if action == "ax_button":
		interact()

func notify(text_value: String, seconds: float = 4.0) -> void:
	message = text_value
	message_until = elapsed+seconds

func interact() -> void:
	if driving:
		if absf(speed) > 1.5:
			notify("Brake to a stop before exiting")
			return
		var exit_pos := car.position+car.basis.x*2.3
		var clearance := PhysicsShapeQueryParameters3D.new()
		clearance.shape = SphereShape3D.new()
		clearance.shape.radius = 0.45
		clearance.transform = Transform3D(Basis(),exit_pos+Vector3.UP)
		clearance.exclude = [player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(clearance).is_empty():
			notify("Exit blocked. Move into the road.")
			return
		set_driving(false)
		player.position = exit_pos+Vector3.UP*0.1
		notify("On foot / A to enter your gold car")
		return
	if player.position.distance_to(target) < 4.2:
		if carrying:
			if heat > 0.0:
				notify("Lose the police first! Keep your distance.")
			else:
				cash += 500+job*100
				job += 1
				carrying = false
				target = pickup
				health = 100.0
				save_progress()
				beep(880.0,0.5)
				notify("DELIVERED! Cash banked. Return to the terminal.",6.0)
		else:
			carrying = true
			target = deliveries[job%deliveries.size()]
			heat = 2.0
			escape_time = 0.0
			beep(650.0)
			notify("Package collected. Police alerted! Get to your car.",6.0)
		update_marker()
	elif player.position.distance_to(car.position) < 4.2:
		set_driving(true)
		notify("Drive: left stick / right trigger. Grip to brake.",6.0)
	else:
		notify("Get closer to the beacon or your gold car")

func set_driving(value: bool) -> void:
	driving = value
	speed = 0.0
	if driving:
		player.position = car.position+Vector3(0,0.08,0)
		player.rotation.y = car_yaw
		rig.rotation.y = 0.0
		rig.position.y = -0.48
		var drive_shape := BoxShape3D.new()
		drive_shape.size = Vector3(1.8,1.2,3.6)
		shape.shape = drive_shape
		shape.position.y = 0.65
	else:
		var foot := CapsuleShape3D.new()
		foot.radius = 0.32
		foot.height = 1.7
		shape.shape = foot
		shape.position.y = 0.85
		rig.position.y = 0.0

func return_hub() -> void:
	set_driving(false)
	player.position = Vector3(3.8,0.1,6)
	player.rotation = Vector3.ZERO
	rig.rotation = Vector3.ZERO
	car.position = Vector3(3.8,0,0)
	car.rotation = Vector3.ZERO
	car_yaw = 0.0
	carrying = false
	heat = 0.0
	health = 100.0
	target = pickup
	update_marker()
	notify("Returned to hub. Your banked cash is safe.")

func update_marker() -> void:
	marker.position = target
	var title := marker.get_child(marker.get_child_count()-1) as Label3D
	title.text = destinations[job%4] if carrying else "COURIER TERMINAL"

func _unhandled_input(event: InputEvent) -> void:
	if xr_active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if not driving:
			player.rotation.y -= event.relative.x*0.002
		else:
			rig.rotation.y -= event.relative.x*0.002
		desktop_pitch = clampf(desktop_pitch-event.relative.y*0.002,-1.2,1.2)
		camera.rotation.x = desktop_pitch
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			interact()
		if event.keycode == KEY_R:
			return_hub()
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	elapsed += delta
	tick_count += 1
	var stick := Vector2.ZERO
	var turn := 0.0
	var throttle := 0.0
	var brake := false
	if xr_active:
		stick = left.get_vector2("primary")
		# OpenXR thumbstick +Y is forward; desktop below uses the same convention.
		turn = right.get_vector2("primary").x
		throttle = right.get_float("trigger")
		brake = right.get_float("grip") > 0.4
	else:
		stick = Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S)))
		brake = Input.is_physical_key_pressed(KEY_SPACE)
	if stick.length() < 0.15:
		stick = Vector2.ZERO
	if driving:
		var acceleration := maxf(stick.y,throttle) if stick.y >= 0.0 else stick.y
		speed = move_toward(speed,acceleration*18.0,(22.0 if brake else 6.0)*delta)
		if brake:
			speed = move_toward(speed,0.0,30.0*delta)
		car_yaw -= stick.x*delta*1.4*clampf(speed/5.0,-1.0,1.0)
		player.rotation.y = car_yaw
		var forward := -player.basis.z
		player.velocity = forward*speed
		player.velocity.y = -2.0
		player.move_and_slide()
		if player.get_slide_collision_count() > 0 and absf(speed) > 3.0:
			for idx in player.get_slide_collision_count():
				if absf(player.get_slide_collision(idx).get_normal().y) < 0.5:
					health -= absf(speed)*delta*2.0
					speed *= 0.8
		car.position = Vector3(player.position.x,0,player.position.z)
		car.rotation.y = car_yaw
	else:
		if absf(turn) < 0.25:
			snap_ready = true
		if absf(turn) > 0.7 and snap_ready:
			player.rotation.y -= signf(turn)*PI/6.0
			snap_ready = false
		var forward := -camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var across := camera.global_basis.x
		across.y = 0.0
		var movement := (forward*stick.y+across.normalized()*stick.x).limit_length(1.0)
		player.velocity = movement*3.3
		player.velocity.y = -3.0
		player.move_and_slide()
	if player.position.y < -5.0:
		return_hub()
	update_traffic(delta)
	update_police(delta)
	if health <= 0.0:
		cash = maxi(0,cash-200)
		save_progress()
		return_hub()
		notify("BUSTED / $200 fine. Your car is back at the hub.",6.0)
	if tick_count%8 == 0:
		update_hud()
	update_audio(delta)

func update_traffic(delta: float) -> void:
	for item in traffic:
		var node: Node3D = item.node
		node.position.x += item.dir*delta*6.0
		node.position.z = item.lane+item.dir*3.0
		node.rotation.y = -item.dir*PI/2
		if absf(node.position.x) > 106.0:
			node.position.x = -signf(node.position.x)*105.0
		if heat > 0.0 and node.position.distance_to(player.position) < 2.2 and driving:
			health -= delta*14.0

func update_police(delta: float) -> void:
	var nearest := 999.0
	for i in police.size():
		var node: Node3D = police[i].node
		var destination: Vector3 = police[i].waypoint
		var dist := node.position.distance_to(player.position)
		nearest = minf(nearest,dist)
		if heat > 0.0:
			if node.position.distance_to(destination) < 1.0:
				# Follow connected road-grid intersections, then close in along a road.
				var junction := Vector3(roundf(node.position.x/ROAD)*ROAD,0,roundf(node.position.z/ROAD)*ROAD)
				var goal := Vector3(roundf(player.position.x/ROAD)*ROAD,0,roundf(player.position.z/ROAD)*ROAD)
				if node.position.distance_to(junction) > 1.5:
					destination = junction
				elif absf(goal.x-junction.x) > 1.0:
					destination = junction+Vector3(signf(goal.x-junction.x)*ROAD,0,0)
				elif absf(goal.z-junction.z) > 1.0:
					destination = junction+Vector3(0,0,signf(goal.z-junction.z)*ROAD)
				elif absf(player.position.x-junction.x) < 5.0:
					destination = Vector3(junction.x,0,player.position.z)
				else:
					destination = Vector3(player.position.x,0,junction.z)
				police[i].waypoint = destination
			var direction := destination-node.position
			if direction.length() > 0.15:
				node.position += direction.normalized()*minf(delta*(8.5+i),direction.length())
				node.rotation.y = atan2(-direction.x,-direction.z)
			if dist < 3.0:
				health -= delta*15.0
			if dist < 28.0 and elapsed-last_sound > 1.2:
				beep(650.0 if int(elapsed)%2==0 else 850.0,0.22)
				last_sound = elapsed
		police[i].light.visible = heat > 0.0 and int(elapsed*7.0+i)%2 == 0
	if heat > 0.0:
		if nearest > 38.0:
			escape_time += delta
		else:
			escape_time = maxf(0.0,escape_time-delta*0.6)
		if escape_time > 9.0:
			heat = 0.0
			beep(1000.0,0.3)
			notify("POLICE LOST / Park by the beacon, exit, then A to deliver.",7.0)

func update_hud() -> void:
	var distance := int(Vector2(player.position.x-target.x,player.position.z-target.z).length())
	var alert := "WANTED  **  / ESCAPE %ds" % maxi(0,int(9.0-escape_time)) if heat > 0.0 else "CLEAR"
	var objective := destinations[job%4] if carrying else "COLLECT A CONTRACT"
	var heading := -camera.global_basis.z
	var to_target := (target-camera.global_position).normalized()
	var angle := atan2(heading.cross(to_target).y,heading.dot(to_target))
	var arrow := "AHEAD" if absf(angle) < 0.4 else ("LEFT" if angle > 0 else "RIGHT")
	if absf(angle) > 2.4:
		arrow = "BEHIND"
	hud.text = "$%d    HULL %d%%    %s\n%s  /  %dm  /  %s%s" % [cash,int(health),alert,objective,distance,arrow,"  /  %d km/h" % int(absf(speed)*3.6) if driving else ""]
	if elapsed < message_until:
		hint.text = message
	elif driving:
		hint.text = "A  Exit car (stop first)   |   GRIP  Brake"
	elif player.position.distance_to(target) < 4.2:
		hint.text = "A  Deliver package" if carrying else "A  Collect contract"
	elif player.position.distance_to(car.position) < 4.2:
		hint.text = "A  Enter gold car"
	else:
		hint.text = "Follow the cyan beacon   |   B  Return to hub"

func update_audio(delta: float) -> void:
	tone_time = maxf(0.0,tone_time-delta)
	if not playback:
		return
	var frames := playback.get_frames_available()
	var frequency := tone_frequency if tone_time > 0.0 else (45.0+absf(speed)*5.0)
	var volume := 0.3 if tone_time > 0.0 else (0.045 if driving else 0.0)
	for i in frames:
		tone_phase = fmod(tone_phase+frequency/22050.0,1.0)
		var sample := sin(tone_phase*TAU)*volume
		playback.push_frame(Vector2(sample,sample))

func save_progress() -> void:
	var file := FileAccess.open("user://progress.json",FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"cash":cash,"job":job}))

func load_progress() -> void:
	if FileAccess.file_exists("user://progress.json"):
		var progress = JSON.parse_string(FileAccess.get_file_as_string("user://progress.json"))
		if progress is Dictionary:
			cash = maxi(0,int(progress.get("cash",0)))
			job = maxi(0,int(progress.get("job",0)))

func run_smoke_test() -> void:
	await get_tree().physics_frame
	var original_cash := cash
	var original_job := job
	player.position = pickup+Vector3.UP*0.1
	interact()
	assert(carrying and heat > 0.0,"Contract pickup must start pursuit")
	player.position = car.position+Vector3(2,0.1,0)
	interact()
	assert(driving,"Enter car")
	speed = 8.0
	interact()
	assert(driving,"Cannot exit moving car")
	speed = 0.0
	interact()
	assert(not driving,"Exit stopped car")
	player.position = target+Vector3.UP*0.1
	interact()
	assert(carrying,"Cannot deliver while wanted")
	heat = 0.0
	interact()
	assert(not carrying and cash > original_cash and job == original_job+1,"Delivery rewards")
	cash = original_cash
	job = original_job
	save_progress()
	return_hub()
	assert(target == pickup and health == 100.0 and not driving,"Hub recovery")
	for i in range(120):
		await get_tree().physics_frame
	print("SMOKE_TEST_PASS: pickup, pursuit, enter/exit, delivery gate, reward, save, recovery, 120 physics frames")
	get_tree().quit()

# Render repeated boxes in shared GPU instance batches; collisions remain independent.
func batch_boxes(parent: Node3D) -> void:
	var groups: Dictionary = {}
	for child in parent.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and child.name != "Siren":
			var key: int = child.material_override.get_instance_id()
			if not groups.has(key):
				groups[key] = []
			groups[key].append(child)
	for key in groups:
		var instances: Array = groups[key]
		var batch := MultiMeshInstance3D.new()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		multimesh.mesh = cube
		multimesh.instance_count = instances.size()
		batch.multimesh = multimesh
		batch.material_override = instances[0].material_override
		parent.add_child(batch)
		for idx in instances.size():
			var source: MeshInstance3D = instances[idx]
			var t := source.transform
			t.basis = t.basis.scaled(source.mesh.size)
			multimesh.set_instance_transform(idx,t)
			source.free()
