 toolbar = UI::Toolbar.new "WFB"
     cmd = UI::Command.new("WFB") {
       Sketchup.active_model.select_tool BeamTool.new
     }
     cmd.small_icon = "beam2.png"
     cmd.large_icon = "beam2.png"
     cmd.tooltip = "Draw Wide Flange Beam"
     cmd.status_bar_text = "Draw Beam"
     cmd.menu_text = "Wide Flange Beam"
     toolbar = toolbar.add_item cmd
     toolbar.show
      # Right click on anything to see a Beams item.
    # UI.add_context_menu_handler do |context_menu|
    #  context_menu.add_item("Beams") {
    #  UI.messagebox("This is a success")
    # }
    # end
#-----------------------------------------------------------------------------

cursor_id = nil
 cursor_path = Sketchup.find_support_file("Pointer.png", "Plugins/")
 if cursor_path
   cursor_id = UI.create_cursor(cursor_path, 0, 0)
 end

 def onSetCursor
   UI.set_cursor(cursor_id)
 end

require "ea_beam_tool/beam_library.rb"
SKETCHUP_CONSOLE.show

# To create a new tool in Ruby, you must define a new class that implements
# the methods for the events that you want to respond to.  You do not have
# to implement methods for every possible event that a Tool can respond to.

# Once you have defined a tool class, you select that tool by creating an
# instance of it and passing it to Sketchup.active_model.select_tool

# This implementation of a tool tries to be pretty complete to show all
# of the kinds of things that you can do in a tool.  This makes it a little
# complicated.  You should also look at the TrackMouseTool defined in
# utilities.rb for an example of a simpler tool.

class BeamTool

  include BeamLibrary

  # The activate method is called by SketchUp when the tool is first selected.
  # it is a good place to put most of your initialization
  def activate
    # The Sketchup::InputPoint class is used to get 3D points from screen
    # positions.  It uses the SketchUp inferencing code.
    # In this tool, we will have two points for the end points of the beam.
    @ip1 = Sketchup::InputPoint.new
    @ip2 = Sketchup::InputPoint.new
    @ip = Sketchup::InputPoint.new
    @drawn = false

    # This sets the label for the VCB
    Sketchup::set_status_text $exStrings.GetString("Length"), SB_VCB_LABEL

    self.reset(nil)
  end

  # deactivate is called when the tool is deactivated because
  # a different tool was selected
  def deactivate(view)
    view.invalidate if @drawn
  end

  # The onMouseMove method is called whenever the user moves the mouse.
  # because it is called so often, it is important to try to make it efficient.
  # In a lot of tools, your main interaction will occur in this method.
  def onMouseMove(flags, x, y, view)
    if( @state == 0 )
      # We are getting the first end of the line.  Call the pick method
      # on the InputPoint to get a 3D position from the 2D screen position
      # that is passed as an argument to this method.
      @ip.pick view, x, y
      if( @ip != @ip1 )
        # if the point has changed from the last one we got, then
        # see if we need to display the point.  We need to display it
        # if it has a display representation or if the previous point
        # was displayed.  The invalidate method on the view is used
        # to tell the view that something has changed so that you need
        # to refresh the view.
        view.invalidate if( @ip.display? or @ip1.display? )
        @ip1.copy! @ip

        # set the tooltip that should be displayed to this point
        view.tooltip = @ip1.tooltip
      end
    else
      # Getting the second end of the line
      # If you pass in another InputPoint on the pick method of InputPoint
      # it uses that second point to do additional inferencing such as
      # parallel to an axis.
      @ip2.pick view, x, y, @ip1
      view.tooltip = @ip2.tooltip if( @ip2.valid? )
      view.invalidate

      # Update the length displayed in the VCB
      if( @ip2.valid? )
        length = @ip1.position.distance(@ip2.position)
        Sketchup::set_status_text length.to_s, SB_VCB_VALUE
      end

      # Check to see if the mouse was moved far enough to create a line.
      # This is used so that you can create a line by either dragging
      # or doing click-move-click
      if( (x-@xdown).abs > 10 || (y-@ydown).abs > 10 )
        @dragging = true
      end
    end
  end

  # The onLButtonDOwn method is called when the user presses the left mouse button.
  def onLButtonDown(flags, x, y, view)
    # When the user clicks the first time, we switch to getting the
    # second point.  When they click a second time we create the line
    if( @state == 0 )
      @ip1.pick view, x, y
      if( @ip1.valid? )
        @state = 1
        Sketchup::set_status_text $exStrings.GetString("Select second end"), SB_PROMPT
        @xdown = x
        @ydown = y
      end
    else
      # create the line on the second click
      if( @ip2.valid? )
        self.create_geometry(@ip1.position, @ip2.position,view)
        self.reset(view)
      end
    end

    # Clear any inference lock
    view.lock_inference
  end

  # The onLButtonUp method is called when the user releases the left mouse button.
  def onLButtonUp(flags, x, y, view)
    # If we are doing a drag, then create the line on the mouse up event
    if( @dragging && @ip2.valid? )
      self.create_geometry(@ip1.position, @ip2.position,view)
      self.reset(view)
    end
  end

  # onKeyDown is called when the user presses a key on the keyboard.
  # We are checking it here to see if the user pressed the shift key
  # so that we can do inference locking
  def onKeyDown(key, repeat, flags, view)
    if( key == CONSTRAIN_MODIFIER_KEY && repeat == 1 )
      @shift_down_time = Time.now

      # if we already have an inference lock, then unlock it
      if( view.inference_locked? )
        # calling lock_inference with no arguments actually unlocks
        view.lock_inference
      elsif( @state == 0 && @ip1.valid? )
        view.lock_inference @ip1
      elsif( @state == 1 && @ip2.valid? )
        view.lock_inference @ip2, @ip1
      end
    end
  end

  # onKeyUp is called when the user releases the key
  # We use this to unlock the inference
  # If the user holds down the shift key for more than 1/2 second, then we
  # unlock the inference on the release.  Otherwise, the user presses shift
  # once to lock and a second time to unlock.
  def onKeyUp(key, repeat, flags, view)
    if( key == CONSTRAIN_MODIFIER_KEY &&
      view.inference_locked? &&
      (Time.now - @shift_down_time) > 0.5 )
      view.lock_inference
    end
  end

  # onUserText is called when the user enters something into the VCB
  # In this implementation, we create a line of the entered length if
  # the user types a length while selecting the second point
  def onUserText(text, view)
    # We only accept input when the state is 1 (i.e. getting the second point)
    # This could be enhanced to also modify the last line created if a length
    # is entered after creating a line.
    # return if not @state == 1
    # return if not @ip2.valid?
    UI.messagebox("#{@state}")

    # The user may type in something that we can't parse as a length
    # so we set up some exception handling to trap that
    begin
      value = text.to_l
    rescue
      # Error parsing the text
      UI.beep
      puts "Cannot convert #{text} to a Length"
      value = nil
      Sketchup::set_status_text "", SB_VCB_VALUE
    end
    return if !value

    # Compute the direction and the second point
    pt1 = @ip1.position
    vec = @ip2.position - pt1
    if( vec.length == 0.0 )
      UI.beep
      return
    end
    vec.length = value
    pt2 = pt1 + vec

    # Create a line
    self.create_geometry(pt1, pt2, view)
  end

  # The draw method is called whenever the view is refreshed.  It lets the
  # tool draw any temporary geometry that it needs to.
  def draw(view)
    if( @ip1.valid? )
      if( @ip1.display? )
        @ip1.draw(view)
        @drawn = true
      end

      if( @ip2.valid? )
        @ip2.draw(view) if( @ip2.display? )

        # The set_color_from_line method determines what color
        # to use to draw a line based on its direction.  For example
        # red, green or blue.
        view.set_color_from_line(@ip1, @ip2)
        self.draw_geometry(@ip1.position, @ip2.position, view)
        @drawn = true
      end
    end
  end

  # onCancel is called when the user hits the escape key
  def onCancel(flag, view)
    self.reset(view)
  end


  # The following methods are not directly called from SketchUp.  They are
  # internal methods that are used to support the other methods in this class.

  # Reset the tool back to its initial state
  def reset(view)
    # This variable keeps track of which point we are currently getting
    @state = 0

    # Display a prompt on the status bar
    Sketchup::set_status_text($exStrings.GetString("Select first end"), SB_PROMPT)

    # clear the InputPoints
    @ip1.clear
    @ip2.clear

    if( view )
      view.tooltip = nil
      view.invalidate if @drawn
    end

    @drawn = false
    @dragging = false
  end


  def find_beam(beam)
    beam = beam.upcase
    if /(W\d+X+\d)\w+/.match("#{beam}")
      @beam_name = beam
      @height_class = beam.split("X").first.to_s
      input = BeamLibrary::BEAMS["#{@height_class}"]["#{beam}"]
      return input
    else
      return nil
    end
  end

  def all_beams
    beams = ""
    BeamLibrary::BEAMS.each do |k, v|
      v.each_key do |key|
        beams << "#{key}|"
      end
    end
    return beams
  end


  # This is the standard Ruby initialize method that is called when you create
  # a new object.
  def initialize()
    @ip1 = nil
    @ip2 = nil
    @xdown = 0
    @ydown = 0

    prompts = ["Beam Size", "Select Beam Size"]
    defaults = ["W10X30", ""]
    list = ["", all_beams]
    a = UI.inputbox(prompts, defaults, list, "All Beams")
    a.first.empty? ? a = a.last : a = a.first
    input = a
    return if not input
    @beam_size = find_beam("#{input}")
    if @beam_size.nil?
      UI.messagebox("Invalid Beam Size")
      return
    else
      @beam_size
    end
  end

  def draw_beam(beam, length)
    entities = Sketchup.active_model.entities
    # temporarily groups the face so other geom wont interere with operations
    temp_group = entities.add_group
    beam_ents = temp_group.entities

    #set variable for the Name, Height Class, Height, Width, flange thickness, web thickness and radius for the beams
    beam_name = @beam_name
    @hc = @height_class.split("W").last.to_f
    @h = beam[:d].to_f
    @w = beam[:bf].to_f
    @tf = beam[:tf].to_f
    @tw = beam[:tw].to_f
    r = beam[:r].to_f
    @wc = beam[:width_class].to_f
    segs = 3

    #the thirteen points on a beam
    points = [
      pt1 = [0,0,0],
      pt2 = [@w,0,0],
      pt3 = [@w,0,@tf],
      pt4 = [(0.5*@w)+(0.5*@tw)+r, 0, @tf],
      pt5 = [(0.5*@w)+(0.5*@tw), 0, (@tf+r)],
      pt6 = [(0.5*@w)+(0.5*@tw), 0, (@h-@tf)-r],
      pt7 = [(0.5*@w)+(0.5*@tw)+r, 0, @h-@tf],
      pt8 = [@w,0,@h-@tf],
      pt9 = [@w,0,@h],
      pt10= [0,0,@h],
      pt11= [0,0,@h-@tf],
      pt12= [(0.5*@w)-(0.5*@tw)-r, 0, @h-@tf],
      pt13= [(0.5*@w)-(0.5*@tw), 0, (@h-@tf)-r],
      pt14= [(0.5*@w)-(0.5*@tw), 0, @tf+r],
      pt15= [(0.5*@w)-(0.5*@tw)-r, 0, @tf],
      pt16= [0,0,@tf]
    ]

    #sets the working guage width for the beam
    case @wc
    when 4
      @guage_width = 2.25
    when 5, 5.25, 5.75
      @guage_width = 2.75
    when 5.5 .. 7.5
      @guage_width = 3.5
    when 8 .. 10.5
      @guage_width = 5.5
    when 12 .. 16.5
      if @hc == 36 .. 40
        @guage_width = 7.5
      else
        @guage_width = 5.5
      end
    end

    @point_one = Geom::Point3d.new [8, 0.5*@tw, (0.5*@h)+(0.25*@hc)]
    @point_two = Geom::Point3d.new [24, 0.5*@tw, (0.5*@h)-(0.25*@hc)]

    #sets the center of the radius for each beam radius
    arc_radius_points = [
      [(@w*0.5)+(@tw*0.5)+r, 0, @tf+r], [(@w*0.5)+(@tw*0.5)+r, 0, (@h-@tf)-r], [(@w*0.5)-(@tw*0.5)-r, 0, (@h-@tf)-r], [(@w*0.5)-(@tw*0.5)-r, 0, @tf+r]
    ]

    #sets the information for creating the radius points
    normal = [0,1,0]
    zero_vec = [0,0,1]
    @radius = []
    turn = 180

    #draws the arcs and rotates them into position
    arc_radius_points.each do |center|
      a = temp_group.entities.add_arc center, zero_vec, normal, r, 0, 90.degrees, segs
      rotate = Geom::Transformation.rotation center, [0,1,0], turn.degrees
      entities.transform_entities rotate, a
      @radius << a
      turn += 90
    end

    #draws the wire frame outline of the beam to create a face
    @segments = []
    count = 1
    beam_outline = points.each do |pt|
       a = temp_group.entities.add_line pt, points[count.to_i]
        count < 15 ? count += 1 : count = 0
        @segments << a
    end

    #erases the unncesary lines created in the outline
    @segments.each_with_index do |line, i|
      if i == 3 || i == 5 || i == 11 || i == 13
        @segments.slice(i)
        line.erase!
      end
    end

    #adds the radius arcs into the array of outline @segments
    @radius.each do |r|
      @segments << r
    end

    @control_segment = temp_group.entities.add_line pt1, pt2

    #sets all of the connected @segments of the outline into a variable
    segs = @segments.first.all_connected

    #move the beam outline to center on the axes
    m = Geom::Transformation.new [-0.5*@w, 0, 0]
    entities.transform_entities m, segs

    #rotate the beam 90° to align with the red axes before grouping
    r = Geom::Transformation.rotation [0,0,0], [0,0,1], 90.degrees
    entities.transform_entities r, segs

    #adds the face to the beam outline
    face = temp_group.entities.add_face segs

    #extrudes the profile the length od the points
    face.pushpull length

    #Soften the radius lines
    beam_ents.each_with_index do |e, i|
      if e.typename == "Edge" && e.length == length && !e.soft?
        @radius.each do |arc|
          a = arc[0].start.position
          b = arc[2].end.position
          if e.start.position == a || e.start.position == b
            e.soft = true
            e.smooth = true
          end
        end
      end
    end

    #returns the face result of the method
    return temp_group
  end

  # Draw the geometry
  def draw_geometry(pt1, pt2, view)
    # returns a view
    view.draw_points [pt1, pt2], 40, 3, "blue"
  end

  def add_holes(length)
    dl = Sketchup.active_model.definitions
    ent = Sketchup.active_model.entities
    #this code makes so the holes cannot be less than 8" from the beams edge
    #and if the beam is smaller than 26" then the holes do not stagger
    if length >= 26
      if (length % 16) >= 16
        fhpX = (length % 16) / 2
        shpX = ((length % 16) / 2) + 16
      else
        fbl = length - (length % 16)
        fhpX = ((fbl % 16) / 2) + ((length % 16) / 2) + 8
        shpX = ((fbl % 16) / 2) + ((length % 16) / 2) + 24
      end
    else
      fhpX = length / 2
      shpX = length / 2
    end

    file_path1 = Sketchup.find_support_file "ea_beam_tool/Holes Collection/9_16_ Hole Set.skp", "Plugins/"
    nine_sixteenths_hole = dl.load file_path1

    file_path2 = Sketchup.find_support_file "ea_beam_tool/Holes Collection/13_16_ Hole Set.skp", "Plugins/"
    thirteen_sixteenths_hole = dl.load file_path2

    #adds in the top flange 9/16" holes if the flange thickness is less than 3/4"
    #and 1/2" studs if the flange is thicker than 3/4"
    if @w < 6.75
      stagger = true
      y = 0.5*@guage_width
    else
      y = (0.5*@w) - 1.625
    end

    all_holes = []
    count = 0

    scale_web = @tw/2
    scale_flange = @tf/2

    while fhpX < length
      tran1 = Geom::Transformation.scaling [fhpX, (0.5*@tw), (0.5*@h)+(0.25*@hc)], 1, scale_web, 1
      tran2 = Geom::Transformation.scaling [fhpX, 0.5*@guage_width, @h], 1, 1, scale_flange
      tran3 = Geom::Transformation.scaling [fhpX, 0.5*@guage_width, @tf], 1, 1, scale_flange

      #insert 4 13/16" holes in the top and bottom flange close to each end of the beam
      if count == 0 || shpX > length
        count == 0 ? x = 6.5 : x = (length - 6.5)
        holes = [
          #adds in 13/16" holes in the top flange
          (inst1 = ent.add_instance thirteen_sixteenths_hole, [x, (0.5*@guage_width), @h]),
          #adds a 13/16" Hole in the bottom flange
          (inst3 = ent.add_instance thirteen_sixteenths_hole, [x, (0.5*@guage_width), @tf]),
          #adds in 13/16" holes in the top flange
          (inst2 = ent.add_instance thirteen_sixteenths_hole, [x, (-0.5*@guage_width), @h]),
          #adds a 13/16" Hole in the bottom flange
          (inst4 = ent.add_instance thirteen_sixteenths_hole, [x, (-0.5*@guage_width), @tf])
        ]

        holes.each_with_index do |hole, i|
          i.even? ? (hole.transform! tran2) : (hole.transform! tran3)
        end

        all_holes.push inst1, inst2, inst3, inst4
      end

      # inserts 9/16" holes in the flanges if the flange thickness is less than 3/4"
      # and inserts 1/2" studs on the top flange if it is thicker than 3/4"
      if @tf <= 0.75
        holes = [
          #adds the first row of 9/16" holes in the top flange
          (inst1 = ent.add_instance nine_sixteenths_hole, [fhpX, y, @h] unless stagger && count.odd?),
          #adds the first row of holes in the bottom flange
          (inst3 = ent.add_instance nine_sixteenths_hole, [fhpX, y, @tf] unless stagger && count.odd?),
          #adds the second row of 9/26" holes in the top flange
          (inst2 = ent.add_instance nine_sixteenths_hole, [fhpX, -y, @h] unless stagger && count.even?),
          #adds the second row of holes in the bottom flange
          (inst4 = ent.add_instance nine_sixteenths_hole, [fhpX, -y, @tf] unless stagger && count.even?)
        ]

        holes.compact! if stagger
        holes.each_with_index do |hole, i|
          i.even? ? (hole.transform! tran2) : (hole.transform! tran3)
          all_holes.push hole
        end
      else
        #puts studs on the beam(incomplete)
      end

      if count.even? && @tw <= 0.75
        #Adds in the top row of web holes
        placement1 = [fhpX, (0.5*@tw), @hc >= 18 ? @h-(@tf+3) : (0.5*@h)+(0.25*@hc)]
        inst = ent.add_instance nine_sixteenths_hole, placement1
        t = Geom::Transformation.rotation placement1, [1,0,0], 270.degrees
        inst.transform! t
        inst.transform! tran1
        all_holes << inst

        break if shpX > length

        #Adds in the bottom row of web holes
        placement2 = [shpX, (0.5*@tw), @hc >= 18 ? @h-(@tf+9) : (0.5*@h)-(0.25*@hc)]
        inst = ent.add_instance nine_sixteenths_hole, placement2
        t = Geom::Transformation.rotation placement2, [1,0,0], 270.degrees
        inst.transform! t
        inst.transform! tran1
        all_holes << inst
      end

      fhpX += 16
      shpX += 16
      count += 1
    end

    all_holes
  end

  def add_labels(vec, length)
    all_labels = []
    north = Geom::Vector3d.new [0,1,0]
    dl = Sketchup.active_model.definitions
    entities = Sketchup.active_model.entities
    beam_direction = vec
    angle = beam_direction.angle_between north

    if vec[0] >= 0
      case angle
      when (0.degrees)..(22.5.degrees)
        direction1 = 'N'
        direction2 = 'S'
      when (22.5.degrees)..(67.5.degrees)
        direction1 = 'NE'
        direction2 = 'SW'
      when (67.5.degrees)..(112.5.degrees)
        direction1 = 'E'
        direction2 = 'W'
      when (112.5.degrees)..(157.5.degrees)
        direction1 = 'SE'
        direction2 = 'NW'
      when (157.5.degrees)..(180.degrees)
        direction1 = 'S'
        direction2 = 'N'
      end
    else
      case angle
      when (0.degrees)..(22.5.degrees)
        direction1 = 'N'
        direction2 = 'S'
      when (22.5.degrees)..(67.5.degrees)
        direction1 = 'NW'
        direction2 = 'SE'
      when (67.5.degrees)..(112.5.degrees)
        direction1 = 'W'
        direction2 = 'E'
      when (112.5.degrees)..(157.5.degrees)
        direction1 = 'SW'
        direction2 = 'NE'
      when (157.5.degrees)..(180.degrees)
        direction1 = 'S'
        direction2 = 'N'
      end
    end

    file_path1 = Sketchup.find_support_file "ea_beam_tool/Labels Collection/#{direction1}.skp", "Plugins/"
    end_direction = dl.load file_path1
    file_path2 = Sketchup.find_support_file "ea_beam_tool/Labels Collection/#{direction2}.skp", "Plugins/"
    start_direction = dl.load file_path2
    # file_path3 = Sketchup.find_support_file "ea_beam_tool/Labels Collection/#{up}.skp", "Plugins/"

    for n in 1..2
      n == 1 ? a = -(0.5*@tw) : a = (0.5*@tw)

      placement1 = [8, a, 0.5*@h]
      placement2 = [length-8, a, 0.5*@h]

      #add the first direction marker to the start of the beam
      # inst = ent.add_instance nine_sixteenths_hole, placement2
      inst = entities.add_instance start_direction, placement1
      r = Geom::Transformation.rotation placement1, [0,0,1], 180.degrees
      entities.transform_entities r, inst if n == 2
      all_labels << inst

      inst = entities.add_instance end_direction, placement2
      r = Geom::Transformation.rotation placement2, [0,0,1], 180.degrees
      entities.transform_entities r, inst if n == 2
      all_labels << inst
    end

    for n in 1..2
      n == 1 ? a = @h : a = 0

      placement1 = [8, 0, a]
      placement2 = [length-8, 0, a]

      r1 = Geom::Transformation.rotation placement1, [1,0,0], 270.degrees
      r2 = Geom::Transformation.rotation placement2, [1,0,0], 90.degrees
      #add the first direction marker to the start of the beam
      # inst = ent.add_instance nine_sixteenths_hole, placement2
      inst = entities.add_instance start_direction, placement1
      entities.transform_entities (n == 1 ? r1 : r2), inst
      all_labels << inst

      inst = entities.add_instance end_direction, placement2
      entities.transform_entities (n == 1 ? r1 : r2), inst
      all_labels << inst
    end

    all_labels
  end

  def add_plates(pt1, pt2, vec, length)

  end

  def align_beam(pt1, pt2, vec, group)
    entities = Sketchup.active_model.entities

    #move the center of the bottom flange to the first point
    tr = Geom::Transformation.translation pt1
    entities.transform_entities tr, group

    #getrs both vectors to compare angle difference
    temp_vec = Geom::Vector3d.new [vec[0], vec[1], 0]
    beam_profile_vec = Geom::Vector3d.new [1,0,0]

    #gets the horizontal angle to rotate the face
    hz_angle = beam_profile_vec.angle_between temp_vec

    #checks if the vec is negative-X
    if vec[1] < 0
      hz_angle += (hz_angle * -2)
    end


    #rotates the profile to align with the vec horizontally
    rotation1 = Geom::Transformation.rotation pt1, [0,0,1], hz_angle
    entities.transform_entities rotation1, group

    temp_vec = Geom::Vector3d.new [vec[0], vec[1], 0]
    vt_angle = temp_vec.angle_between vec

    #checks to see if the vec is negative-Z
    if vec[2] > 0
      vt_angle += (vt_angle * -2.0)
    end

    rotation2 = Geom::Transformation.rotation pt1, [(-1.0*vec[1]), (vec[0]), 0], vt_angle
    entities.transform_entities rotation2, group
  end


  def create_geometry(pt1, pt2, view)
    model = view.model
    model.start_operation("Create Beam")
    entities = Sketchup.active_model.entities

    # First create a circle
    vec = pt2 - pt1
    length = vec.length
    if( length == 0.0 )
      UI.beep
      UI.messagebox("Cannot create a zero length Beam")
      return
    end

    #draw the bare beam
    beam = draw_beam(@beam_size, length)

    #add holes to the beam
    all_holes = add_holes(length)

    #insert all labels in the beam
    all_labels = add_labels(vec, length)

    #group the beam and name the group and add the steel layer
    inner_group = entities.add_group beam, all_holes, all_labels
    inner_group.name = "#{@beam_name}"
    steel_layer = model.layers.add "Steel"

    beam.explode

    ### Uncomment this if you want the holes to cut ###
    all_holes.each do |hole|
      hole.explode
    end

    #insert stiffener plates in the beam
    #---Future Method Goes Here ----#

    #group the inner_grouped beam with the plates to create the outer group
    #---Future Method Goes here

    #align the beam with the input points
    align_beam(pt1, pt2, vec, inner_group)

    model.commit_operation
  end

end #end beam tool
