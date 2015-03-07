require 'sketchup.rb'

# delete this after debugging
Sketchup.send_action "showRubyPanel:"


		
module SH_SKRATCHED

# global variables
	@projectDirectory = "C:\\"

#Add menu items
	submenu = UI.menu("PlugIns").add_submenu("Skratched")
	submenu_setup = submenu.add_submenu("Model Setup")
	submenu_view = submenu.add_submenu("Render View")
	submenu_grid = submenu.add_submenu("Render Grid")
	
	submenu_setup.add_item("1A. Set project directory") {
		self.setProjectDirectory
	}
	submenu_setup.add_item("1B. Assign generic material") {
		self.assignGenericMaterial
		}
	submenu_setup.add_item("1C. Check normals") {
		self.checkNormals
		}
	submenu_setup.add_item("1D. Export Materials") {
		self.radmats
	}
	submenu_setup.add_item("1E. Export Geometry") {
		self.radgeo
		}
	submenu_setup.add_item("1F. Export Sky") {
		self.genSkyFromShadows
		}
	submenu_view.add_item("2A. Export View") {
		self.exportView
		}
	submenu_view.add_item("2B. Make RIF File") {
		self.makeRIFfile
		}
		
	def self.setProjectDirectory
		@projectDirectory = UI.select_directory(title: "Select Project Directory")
	end
	
#this method will find all faces without any assigned material and assign a default gray of 60% reflectance
#this is necessary to prevent errors - you can't create Radiance geometry without assigning a material
#should make this run automatically on export as error handling
	def self.assignGenericMaterial
		model = Sketchup.active_model
		entities = model.entities
		
		for entity in entities
			if entity.typename == "Face"
				if entity.material == nil
					entity.material = 0x808080
				end
			end
		end
	end

	def self.checkNormals
		model = Sketchup.active_model
			entities = model.entities
			materials = model.materials
			backface = materials.add('backface')
			backface.color = 'red'
			
			for entity in entities
				if entity.typename == "Face"
					if entity.material.alpha < 1
						entity.back_material = backface
					end
				end
			end
	end
	
	
#this method will find all materials currently used by model geometry and export them as a .mat file
#it's probably best to go into the materials file directly to edit materials, but this can serve as a starting point
	def self.radmats
		model = Sketchup.active_model
		entities = model.entities
	# edit this line to indicate where you want the .rad file to go
		matsfile = UI.savepanel "Save Materials File", @projectDirectory, "materials.rad"
		out_file = File.new(matsfile, 'w')
	
	# get materials - can't get materials from Materials class directly because you get a lot of junk materials
		materials_in_use = []
		for entity in entities
			if entity.typename == "Face"
				unless materials_in_use.include? entity.material
					materials_in_use << entity.material
				end
			end
		end

		for material in materials_in_use
			material_name = material.name
			material_color = material.color
			material_color_red = material_color.red.to_f / 255
			material_color_green = material_color.green.to_f / 255
			material_color_blue = material_color.blue.to_f / 255
			tm = 1 - material.alpha #transmittance - 1 is transparent, 0 is opaque (inverted from Sketchup alpha)
	
		#calculate transmissivity based on transmittance 
		# see http://radsite.lbl.gov/radiance/refer/ray.html#Materials
			if tm > 0
				#tn = ((0.8402528435+(0.0072522239*(tm**2))-0.9166530661)**(0.5))/0.0036261119/tm  need to implement this
				out_file.print("void ")
				out_file.print("glass ")
				out_file.print("#{material_name}\n")
				out_file.print("0\n")
				out_file.print("0\n")
				out_file.print("3 ")
				out_file.print("#{tm} ") # just using transmittance for now
				out_file.print("#{tm} ")
				out_file.print("#{tm}\n")
				out_file.print("\n")
			else 
				out_file.print("void ")
				out_file.print("plastic ")
				out_file.print("#{material_name}\n")
				out_file.print("0\n")
				out_file.print("0\n")
				out_file.print("5 ")
				out_file.print("#{material_color_red} ")
				out_file.print("#{material_color_green} ")
				out_file.print("#{material_color_blue} ")
				out_file.print("0 ") #assuming specularity 0
				out_file.print("0\n") #assuming roughness 0
				out_file.print("\n")
			end
		end
		out_file.close
	end

#this method will convert all faces to polygons and export them, along with material assignments, to a .rad file
#should be able to export any shape. downside is it breaks up all faces into triangles
#utilizes right-hand rule (same as Radiance) and converts any units to meters, Radiance base units
	def self.radgeo
		model = Sketchup.active_model
		entities = model.entities
		
	# edit this line to indicate where you want the .rad file to go
		geofile = UI.savepanel "Save Geometry", @projectDirectory, "geometry.rad"
		out_file = File.new(geofile, 'w')
	
		f = 0
	
		for entity in entities
			if entity.typename == "Face"
				n = 1
				thisMesh = entity.mesh(0)
				polygonCount = thisMesh.count_polygons
							
				while n <= polygonCount do
					f += 1
					material = entity.material
					material_name = material.name
					out_file.print("#{material_name} ") # put material name
					out_file.print("polygon ") # put type polygon
					out_file.print("face#{f}\n") # put unique object name
					
					thisPolygonPoints = thisMesh.polygon_points_at(n)
					out_file.print("0\n")
					out_file.print("0\n")
					out_file.print("9\n")
					for i in 0..2
						x = thisPolygonPoints[i].x.to_m
						y = thisPolygonPoints[i].y.to_m
						z = thisPolygonPoints[i].z.to_m
						out_file.print("#{x} ")
						out_file.print("#{y} ")
						out_file.print("#{z}")
						out_file.print("\n")
					end
					out_file.print("\n")
					n += 1
				end
			end
			out_file.print("\n") # put newline at end of face definition
		end
		out_file.close
	end

#this method will find lat and lon from shadow settings
#utilizes scripts on the .html page
	def self.genSkyFromShadows
		model = Sketchup.active_model
		shadowinfo = model.shadow_info
		latitude = shadowinfo["Latitude"]
		longitude = shadowinfo["Longitude"] * - 1 #default to Western hemisphere
		day_of_year = shadowinfo["DayOfYear"]
		timearray = shadowinfo["ShadowTime"].utc.to_s.split(" ")
		if (Sketchup.version.to_f < 14)
			time = timearray[3]
		elsif (Sketchup.version.to_f >= 14)
			time = timearray[1]
		end
		time = time[0..-4]
			
	#probably a better way to implement this...
		if day_of_year <= 31
			month = 1
			day = day_of_year
		elsif day_of_year <= 59
			month = 2
			day = day_of_year - 31
		elsif day_of_year <= 90
			month = 3
			day = day_of_year - 59
		elsif day_of_year <= 120
			month = 4
			day = day_of_year - 90
		elsif day_of_year <= 151
			month = 5
			day = day_of_year - 120
		elsif day_of_year <= 181
			month = 6
			day = day_of_year - 151
		elsif day_of_year <= 212
			month = 7
			day = day_of_year - 181
		elsif day_of_year <= 243
			month = 8
			day = day_of_year - 212
		elsif day_of_year <= 273
			month = 9
			day = day_of_year - 243
		elsif day_of_year <= 304
			month = 10
			day = day_of_year - 273
		elsif day_of_year <= 334
			month = 11
			day = day_of_year - 304
		elsif day_of_year <= 365
			month = 12
			day = day_of_year - 334
		end
	
	# create WebDialog instance
		dialog = UI::WebDialog.new("GenSky", true, "",200, 200, 200,200, true)
	
	# add action callbacks
		dialog.add_action_callback("sendGeoInfo") do |dlg, param| 
			if param == "refresh"
				puts "Got refresh call"
				to_wdialog = "updateLocation('#{latitude}','#{longitude}','#{month}','#{day}','#{time}')"
				dlg.execute_script(to_wdialog)
			end
	
		dialog.add_action_callback("outputGenSky") do |dlg, skyType|
				puts "gensky " + month.to_s + " " + day.to_s + " " + time + " " + skyType + " -a " + latitude.to_s + " -o " + longitude.to_s
				skyfile = UI.savepanel "Save Sky File", @projectDirectory, "sky.rad"
				out_file = File.new(skyfile, 'w')
				out_file.print("!gensky " + month.to_s + " " + day.to_s + " " + time + " " + skyType + " -a " + latitude.to_s + " -o " + longitude.to_s + "\n\n")
				out_file.print("skyfunc glow sky_glow\n")
				out_file.print("0\n")
				out_file.print("0\n")
				out_file.print("4 1 1 1 0\n\n")
				out_file.print("sky_glow source sky\n")
				out_file.print("0\n")
				out_file.print("0\n")
				out_file.print("4 0 0 1 180\n\n")			
				out_file.close
		end

	end
	
	# find and show dialog
		html_path = Sketchup.find_support_file "genSky.html" , "Plugins\\skratched\\"
		dialog.set_file(html_path)
		dialog.show
		
	end
	
	def self.exportView
		currentView = Sketchup.active_model.active_view
		currentCamera = currentView.camera
		viewDirectionVector = currentCamera.direction
		viewPoint = currentCamera.eye
		viewDirectionX = viewDirectionVector.x.to_m
		viewDirectionY = viewDirectionVector.y.to_m
		viewDirectionZ = viewDirectionVector.z.to_m
		viewPointX = viewPoint.x.to_m
		viewPointY = viewPoint.y.to_m
		viewPointZ = viewPoint.z.to_m
		puts viewDirectionX
		puts viewDirectionY
		puts viewDirectionZ
		puts viewPointX
		puts viewPointY
		puts viewPointZ
	
		viewfile = UI.savepanel "Save View File", @projectDirectory, "view.vp"
		out_file = File.new(viewfile, 'w')
		out_file.print("rvu -vtv -vp #{viewPointX} #{viewPointY} #{viewPointZ} -vd #{viewDirectionX} #{viewDirectionY} #{viewDirectionZ} -vu 0 0 1 -vh 60 -vv 60 -vo 0 -va 0 -vs 0 -vl 0")
		out_file.close
	end
	
	def self.makeRIFfile
	# create WebDialog instance
		dialog = UI::WebDialog.new("Make RIF File", true, "",200, 200, 200,200, true)
	
	# add action callbacks
		dialog.add_action_callback("sendingRIFInfo") do |dlg, param| 
				riffile = UI.savepanel "Save RIF File", @projectDirectory,"render.rif"
				out_file = File.new(riffile, 'w')
				final = param.gsub("*","\n")
				out_file.print(final)
				out_file.close
		end
	
		dialog.add_action_callback("getBoundingBox") do |dlg, param|
				if param == "refresh"
					model = Sketchup.active_model
					model_bb = model.bounds
					xmin = model_bb.corner(0).x.to_m
					ymin = model_bb.corner(0).y.to_m
					zmin = model_bb.corner(0).z.to_m
					xmax = model_bb.corner(7).x.to_m
					ymax = model_bb.corner(7).y.to_m
					zmax = model_bb.corner(7).z.to_m
					to_wdialog = "updateBoundingBox('#{xmin}','#{xmax}','#{ymin}','#{ymax}','#{zmin}','#{zmax}')"
					dlg.execute_script(to_wdialog)
				end
		end
			
	
	# find and show dialog
		html_path = Sketchup.find_support_file "makerif.html" , "Plugins\\skratched\\"
		dialog.set_file(html_path)
		dialog.show
	
	end

end #end module
