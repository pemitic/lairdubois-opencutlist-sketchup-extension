module Ladb::OpenCutList

  require_relative '../../lib/clippy/clippy'
  require_relative '../../lib/geometrix/geometrix'
  require_relative '../../model/drawing/drawing_def'
  require_relative '../../model/drawing/drawing_projection_def'

  class CommonDrawingProjectionWorker

    MINIMAL_PATH_AREA = 1e-6

    def initialize(drawing_def, settings = {})

      @drawing_def = drawing_def

      @option_merge_holes = settings.fetch('merge_holes', false)  # Passthrough holes are moved to bottom layer and all down layers holes are merged to up layer

    end

    # -----

    def run
      return { :errors => [ 'default.error' ] } unless @drawing_def.is_a?(DrawingDef)

      bounds_depth = @drawing_def.bounds.depth
      bounds_max = @drawing_def.bounds.max

      depth_top = 0.0
      depth_bottom = bounds_depth.round(6)

      z_max = bounds_max.z

      top_layer_def = PathsLayerDef.new(DrawingProjectionLayerDef::LAYER_POSITION_TOP, depth_top, [])
      bottom_layer_def = PathsLayerDef.new(DrawingProjectionLayerDef::LAYER_POSITION_BOTTOM, depth_bottom, [])

      layer_defs = {}
      layer_defs[depth_top] = top_layer_def
      layer_defs[depth_bottom] = bottom_layer_def if depth_bottom != depth_top   # Added after sort if same depth as top

      @drawing_def.face_manipulators.each do |face_manipulator|

        # Filter only exposed faces
        next unless !face_manipulator.perpendicular?(@drawing_def.input_normal) && face_manipulator.angle_between(@drawing_def.input_normal) < Math::PI / 2.0

        if face_manipulator.parallel?(@drawing_def.input_normal) && bounds_depth > 0
          f_depth = bounds_max.distance_to_plane(face_manipulator.plane).round(6)
        else
          if face_manipulator.surface_manipulator
            f_depth = (z_max - face_manipulator.surface_manipulator.z_max).round(6) # Faces sharing the same "surface" are considered as a unique "box"
          else
            f_depth = (z_max - face_manipulator.z_max).round(6)
          end
        end

        f_paths = face_manipulator.loop_manipulators.map { |loop_manipulator| loop_manipulator.points }.map { |points| Clippy.points_to_rpath(points) }

        layer_def = layer_defs[f_depth]
        if layer_def.nil?
          layer_def = PathsLayerDef.new(DrawingProjectionLayerDef::LAYER_POSITION_INSIDE, f_depth, f_paths)
          layer_defs[f_depth] = layer_def
        else
          layer_def.paths.concat(f_paths) # Just concat, union will be call later in one unique call
        end

      end

      # Sort on depth ASC
      ld = layer_defs.values.sort_by { |layer_def| layer_def.depth }

      # Append bottom layer if top and bottom share the same depth
      ld.push(bottom_layer_def) if depth_bottom == depth_top

      # Union paths on each layer
      ld.each do |layer_def|
        next if layer_def.paths.one?
        layer_def.paths = Clippy.execute_union(layer_def.paths)
      end

      # Up to Down difference
      ld.each_with_index do |layer_def, index|
        next if layer_def.paths.empty?
        ld[(index + 1)..-1].each do |lower_layer_def|
          next if lower_layer_def.nil? || lower_layer_def.paths.empty?
          lower_layer_def.paths = Clippy.execute_difference(lower_layer_def.paths, layer_def.paths)
        end
      end

      if @option_merge_holes

        # Copy top paths
        min_top_paths = top_layer_def.paths

        # Union top paths with lower paths
        mid_top_paths = Clippy.execute_union(min_top_paths + ld[1..-1].map { |layer_def| layer_def.paths }.flatten(1).compact)
        mid_top_polytree = Clippy.execute_polytree(mid_top_paths)

        # Extract top outer paths
        out_top_paths = mid_top_polytree.children.map { |polypath| polypath.path }

        # Extract passthrough paths and reverse them to plain paths
        passthrough_paths = Clippy.reverse_rpaths(Clippy.delete_rpaths_in(mid_top_paths, out_top_paths))

        # Replace bottom layer paths
        bottom_layer_def.paths = Clippy.execute_union(bottom_layer_def.paths + passthrough_paths)

        # Difference with out and min to extract holes to propagate
        mask_paths = Clippy.execute_difference(out_top_paths, min_top_paths)
        mask_polytree = Clippy.execute_polytree(mask_paths)
        mask_polyshapes = Clippy.polytree_to_polyshapes(mask_polytree)

        # _debug_polytree(mask_polytree)

        # Propagate down to up
        ldr = ld.reverse[0..-2] # Exclude top layer
        mask_polyshapes.each do |mask_polyshape|
          lower_paths = []
          ldr.each do |layer_def|
            next if layer_def.paths.empty?
            next if Clippy.execute_intersection(layer_def.paths, mask_polyshape.paths).empty?
            layer_def.paths = Clippy.execute_union(lower_paths + layer_def.paths) unless lower_paths.empty?
            lower_paths = Clippy.execute_intersection(layer_def.paths, mask_polyshape.paths)
          end
        end

        # Replace top layer paths
        top_layer_def.paths = out_top_paths

        # mask_polyshapes.map { |polyshape| polyshape.paths }.each_with_index { |paths, index| ld << PathsLayerDef.new(index.even? ? DrawingProjectionLayerDef::LAYER_POSITION_INSIDE : DrawingProjectionLayerDef::LAYER_POSITION_BOTTOM , z_max + 5 + 2 * index, paths) }

        # [
        #   # out_top_paths,
        #   # min_top_paths,
        #   mask_paths
        # ].each_with_index { |paths, index| ld << PathsLayerDef.new(DrawingProjectionLayerDef::LAYER_POSITION_INSIDE, z_max + 5 + 2 * index, paths) }

      end

      # Output

      projection_def = DrawingProjectionDef.new(bounds_depth)

      ld.each do |layer_def|
        next if layer_def.paths.empty?

        polygons = layer_def.paths.map { |path|
          next if Clippy.get_rpath_area(path).abs < MINIMAL_PATH_AREA # Ignore "artifact" paths generated by successive transformation / union / differences
          DrawingProjectionPolygonDef.new(Clippy.rpath_to_points(path, z_max - layer_def.depth), Clippy.is_rpath_positive?(path))
        }.compact

        unless polygons.empty?
          projection_def.layer_defs << DrawingProjectionLayerDef.new(layer_def.position, layer_def.depth, polygons)
        end

      end

      projection_def
    end

    def _debug_polytree(polytree)
      SKETCHUP_CONSOLE.clear
      puts "POLYTREE"
      polytree.children.each do |child|
        _debug_polypath(child)
      end
    end

    def _debug_polypath(polypath)
      puts "#{' '.rjust(polypath.level + 1)}POLYPATH #{polypath.hole? ? '▫︎' : '▪︎'}"
      polypath.children.each do |child|
        _debug_polypath(child)
      end
    end

    # -----

    PathsLayerDef = Struct.new(:position, :depth, :paths)


  end

end