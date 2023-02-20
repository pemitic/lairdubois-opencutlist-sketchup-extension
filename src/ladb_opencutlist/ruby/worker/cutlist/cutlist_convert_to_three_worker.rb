module Ladb::OpenCutList

  require_relative '../../helper/layer_visibility_helper'
  require_relative '../../helper/hashable_helper'
  require_relative '../../utils/axis_utils'
  require_relative '../../model/attributes/material_attributes'

  class CutlistConvertToThreeWorker

    include LayerVisibilityHelper

    def initialize(parts, all_instances = false, pins_use_names = false, pins_colored = false)

      @parts = parts
      @all_instances = all_instances
      @pins_use_names = pins_use_names
      @pins_colored = pins_colored

    end

    # -----

    def run

      model = Sketchup.active_model
      return nil unless model

      materials = model.materials

      three_model_def = ThreeModelDef.new

      group_cache = {}  # key = serialized_path, value = group - Only for all instances

      @parts.each do |part|

        if @all_instances

          part.def.instance_infos.each { |serialized_path, instance_info|

            # Create the three part def
            three_part_def = ThreePartDef.new
            three_part_def.matrix = _to_three_matrix(instance_info.entity.transformation)
            three_part_def.face_vertices,
              three_part_def.face_colors,
              three_part_def.hard_edge_vertices,
              three_part_def.soft_edge_vertices,
              three_part_def.soft_edge_controls0,
              three_part_def.soft_edge_controls1,
              three_part_def.soft_edge_directions = _grab_entities_vertices_and_colors(instance_info.entity.definition.entities, materials[part.material_name])

            three_part_def.pin_text = @pins_use_names ? part.name : part.number
            three_part_def.pin_class = @pins_use_names ? 'square' : nil
            three_part_def.pin_color = @pins_colored ? _to_three_color(materials[part.material_name]) : nil

            # Add to hierarchy
            parent_three_group_def = _parent_hierarchy(instance_info.path.slice(0, instance_info.path.length - 1), group_cache, three_model_def)
            parent_three_group_def.add(three_part_def)

          }

        else

          if part.auto_oriented && part.group.material_type != MaterialAttributes::TYPE_HARDWARE

            # Set transformation matrix to correspond to axes orientation
            axes_order = part.def.size.normals.clone
            if AxisUtils::flipped?(axes_order[0], axes_order[1], axes_order[2])
              # axes_order[0] = axes_order[0].reverse
              axes_order[1] = axes_order[1].reverse
              # axes_order[2] = axes_order[2].reverse
            end
            transformation = Geom::Transformation.axes(ORIGIN, axes_order[0], axes_order[1], axes_order[2]).inverse
            three_model_def.matrix = _to_three_matrix(transformation)

          end

          # Extract first instance
          instance_info = part.def.instance_infos.values.first

          # Create the three part def
          three_part_def = ThreePartDef.new
          three_part_def.matrix = _to_three_matrix(Geom::Transformation.scaling(part.def.scale.x * (part.def.flipped ? -1 : 1), part.def.scale.y, part.def.scale.z))
          three_part_def.face_vertices,
            three_part_def.face_colors,
            three_part_def.hard_edge_vertices,
            three_part_def.soft_edge_vertices,
            three_part_def.soft_edge_controls0,
            three_part_def.soft_edge_controls1,
            three_part_def.soft_edge_directions = _grab_entities_vertices_and_colors(instance_info.entity.definition.entities, materials[part.material_name])

          # Add to hierarchy
          three_model_def.add(three_part_def)

        end

      end

      # _dump(three_model_def)

      three_model_def
    end

    # -----

    def _grab_entities_vertices_and_colors(entities, material, transformation = nil)
      face_vertices = []
      face_colors = []
      hard_edge_vertices = []
      soft_edge_vertices = []
      soft_edge_controls0 = []
      soft_edge_controls1 = []
      soft_edge_directions = []
      entities.each do |entity|

        next unless entity.visible? && _layer_visible?(entity.layer)

        if entity.is_a?(Sketchup::Face)
          fv, fc = _grab_face_vertices_and_colors(entity, material, transformation)
          face_vertices.concat(fv)
          face_colors.concat(fc)
        elsif entity.is_a?(Sketchup::Edge)
          hev, sev, sec0, sec1, dir = _grab_edge_vertices_and_controls(entity, transformation)
          hard_edge_vertices.concat(hev)
          soft_edge_vertices.concat(sev)
          soft_edge_controls0.concat(sec0)
          soft_edge_controls1.concat(sec1)
          soft_edge_directions.concat(dir)
        elsif entity.is_a?(Sketchup::Group)
          fv, fc, hev, sev, sec0, sec1, dir = _grab_entities_vertices_and_colors(entity.entities, entity.material.nil? ? material : entity.material, TransformationUtils::multiply(transformation, entity.transformation))
          face_vertices.concat(fv)
          face_colors.concat(fc)
          hard_edge_vertices.concat(hev)
          soft_edge_vertices.concat(sev)
          soft_edge_controls0.concat(sec0)
          soft_edge_controls1.concat(sec1)
          soft_edge_directions.concat(dir)
        elsif entity.is_a?(Sketchup::ComponentInstance) && entity.definition.behavior.cuts_opening?
          fv, fc, hev, sev, sec0, sec1, dir = _grab_entities_vertices_and_colors(entity.definition.entities, entity.material.nil? ? material : entity.material, TransformationUtils::multiply(transformation, entity.transformation))
          face_vertices.concat(fv)
          face_colors.concat(fc)
          hard_edge_vertices.concat(hev)
          soft_edge_vertices.concat(sev)
          soft_edge_controls0.concat(sec0)
          soft_edge_controls1.concat(sec1)
          soft_edge_directions.concat(dir)
        elsif entity.is_a?(Sketchup::ComponentDefinition)
          fv, fc, hev, sev, sec0, sec1, dir = _grab_entities_vertices_and_colors(entity.entities, material, transformation)
          face_vertices.concat(fv)
          face_colors.concat(fc)
          hard_edge_vertices.concat(hev)
          soft_edge_vertices.concat(sev)
          soft_edge_controls0.concat(sec0)
          soft_edge_controls1.concat(sec1)
          soft_edge_directions.concat(dir)
        end

      end

      [ face_vertices, face_colors, hard_edge_vertices, soft_edge_vertices, soft_edge_controls0, soft_edge_controls1, soft_edge_directions ]
    end

    def _grab_face_vertices_and_colors(face, material, transformation = nil)

      mesh = face.mesh(0) # POLYGON_MESH_POINTS
      points = mesh.points

      red, green, blue = _to_three_vertex_color(face.material.nil? ? material : face.material)

      Point3dUtils::transform_points(points, transformation)

      vertices = []
      colors = []
      mesh.polygons.each { |polygon|
        polygon.each { |index|

          point = points[index.abs - 1]
          vertices << point.x.to_f
          vertices << point.y.to_f
          vertices << point.z.to_f

          colors << red
          colors << green
          colors << blue

        }
      }

      [ vertices, colors ]
    end

    def _grab_edge_vertices_and_controls(edge, transformation = nil)
      hard_vertices = []
      soft_vertices = []
      soft_controls0 = []
      soft_controls1 = []
      soft_directions = []

      # Soft controls
      if edge.soft?

        edge.faces.each do |face|

          vertex = face.vertices.find { |v| !edge.used_by?(v) }
          if vertex.is_a?(Sketchup::Vertex)

            point = vertex.position
            point.transform!(transformation) unless transformation.nil?

            controls = soft_controls0.empty? ? soft_controls0 : soft_controls1
            2.times do
              controls << point.x.to_f
              controls << point.y.to_f
              controls << point.z.to_f
            end

          end

          unless soft_controls0.empty? || soft_controls1.empty?
            break
          end

        end

        # Check if there's enough controls
        if soft_controls0.empty? || soft_controls1.empty?
          soft_controls0.clear
          soft_controls1.clear
        end

      end

      # Vertices
      edge.vertices.each do |vertex|

        point = vertex.position
        point.transform!(transformation) unless transformation.nil?

        vertices = soft_controls0.empty? ? hard_vertices : soft_vertices
        vertices << point.x.to_f
        vertices << point.y.to_f
        vertices << point.z.to_f

      end

      # Soft directions
      unless soft_controls0.empty?
        2.times do
          soft_directions << soft_vertices[3] - soft_vertices[0]
          soft_directions << soft_vertices[4] - soft_vertices[1]
          soft_directions << soft_vertices[5] - soft_vertices[2]
        end
      end

      [ hard_vertices, soft_vertices, soft_controls0, soft_controls1, soft_directions ]
    end

    def _parent_hierarchy(path, cache, three_model_def)
      return three_model_def if path.nil? || path.empty?

      serialized_path = PathUtils.serialize_path(path)

      # Pop last path entity
      entity = path.pop

      # Try to fetch three group def from cache
      three_group_def = cache.fetch(serialized_path, nil)
      unless three_group_def

        # Create a new three group def
        three_group_def = ThreeGroupDef.new
        three_group_def.name = entity.name
        three_group_def.matrix = _to_three_matrix(entity.transformation)

        # Keep it in the cache
        cache.store(serialized_path, three_group_def)

        # Try to retrieve parent
        parent_three_group_def = _parent_hierarchy(path, cache, three_model_def)
        if parent_three_group_def
          # Parent found, add current group as child
          parent_three_group_def.add(three_group_def)
        else
          # No more parent, add current group to model
          three_model_def.add(three_group_def)
        end

      end

      three_group_def
    end

    def _to_three_matrix(tranformation)
      return nil unless tranformation.is_a?(Geom::Transformation)
      return nil if tranformation.identity?
      tranformation.to_a.flatten
    end

    def _to_three_color(material)
      return nil unless material.is_a?(Sketchup::Material)
      (material.color.red << 16) + (material.color.green << 8) + material.color.blue
    end

    def _to_three_vertex_color(material)
      return [ 1, 1, 1 ] unless material.is_a?(Sketchup::Material)
      [ material.color.red / 255.0, material.color.green / 255.0, material.color.blue / 255.0 ]
    end

    def _dump(three_object_def, level = 1)
      puts '+'.rjust(level, '-') + three_object_def.class.to_s + ' ' + three_object_def.name + ' ' + (three_object_def.is_a?(ThreePartDef) ? three_object_def.pin_text.to_s : '')
      if three_object_def.is_a?(ThreeGroupDef)
        three_object_def.children.each do |child_three_object_def|
          _dump(child_three_object_def, level + 1)
        end
      end
    end

  end

  # -----

  class ThreeObjectDef

    include HashableHelper

    TYPE_UNDEFINED = 0
    TYPE_MODEL = 1
    TYPE_PART = 2
    TYPE_GROUP = 3

    attr_accessor :name

    def initialize(type = TYPE_UNDEFINED)
      @type = type
      @name = ''
    end

    def type
      @type
    end

  end

  class ThreeGroupDef < ThreeObjectDef

    attr_accessor :matrix
    attr_reader :children

    def initialize(type = ThreeObjectDef::TYPE_GROUP)
      super(type)
      @matrix = nil
      @children = []
    end

    def add(three_object)
      @children.push(three_object)
    end

  end

  class ThreeModelDef < ThreeGroupDef

    attr_accessor :up

    def initialize
      super(ThreeObjectDef::TYPE_MODEL)
      @up = [ 0, 0, 1 ]
    end

  end

  class ThreePartDef < ThreeGroupDef

    attr_accessor :face_vertices, :face_colors, :hard_edge_vertices, :soft_edge_vertices, :soft_edge_controls0, :soft_edge_controls1, :soft_edge_directions, :pin_text, :pin_class, :pin_color

    def initialize
      super(ThreeObjectDef::TYPE_PART)
      @face_vertices = []
      @face_colors = []
      @hard_edge_vertices = []
      @soft_edge_vertices = []
      @soft_edge_controls0 = []
      @soft_edge_controls1 = []
      @soft_edge_directions = []
      @pin_text = nil
      @pin_class = nil
      @pin_color = nil
    end

  end

end