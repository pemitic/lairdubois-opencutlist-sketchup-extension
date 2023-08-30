module Ladb::OpenCutList

  require_relative '../../constants'
  require_relative '../../helper/face_triangles_helper'
  require_relative '../../helper/dxf_writer_helper'
  require_relative '../../helper/svg_writer_helper'
  require_relative '../../helper/sanitizer_helper'

  class CommonExportFacesToFileWorker

    include FaceTrianglesHelper
    include DxfWriterHelper
    include SvgWriterHelper
    include SanitizerHelper

    SUPPORTED_FILE_FORMATS = [ FILE_FORMAT_DXF, FILE_FORMAT_SVG ]

    def initialize(face_infos, edge_infos, settings)

      @face_infos = face_infos
      @edge_infos = edge_infos

      @file_name = _sanitize_filename(settings.fetch('file_name', 'FACE'))
      @file_format = settings.fetch('file_format', nil)
      @unit = settings.fetch('unit', nil)
      @anchor_origin = settings.fetch('anchor_origin', Geom::Point3d.new)
      @max_depth = settings.fetch('max_depth', 0)

    end

    # -----

    def run
      return { :errors => [ 'default.error' ] } unless SUPPORTED_FILE_FORMATS.include?(@file_format)
      return { :errors => [ 'default.error' ] } unless @face_infos.is_a?(Array)

      # Open save panel
      path = UI.savepanel(Plugin.instance.get_i18n_string('tab.cutlist.export_to_3d.title', { :file_format => @file_format }), '', "#{@file_name}.#{@file_format}")
      if path

        # Force "file_format" file extension
        unless path.end_with?(".#{@file_format}")
          path = "#{path}.#{@file_format}"
        end

        begin

          case @unit
          when DimensionUtils::INCHES
            unit_converter = 1.0
          when DimensionUtils::FEET
            unit_converter = 1.0.to_l.to_feet
          when DimensionUtils::YARD
            unit_converter = 1.0.to_l.to_yard
          when DimensionUtils::MILLIMETER
            unit_converter = 1.0.to_l.to_mm
          when DimensionUtils::CENTIMETER
            unit_converter = 1.0.to_l.to_cm
          when DimensionUtils::METER
            unit_converter = 1.0.to_l.to_m
          else
            unit_converter = DimensionUtils.instance.length_to_model_unit_float(1.0.to_l)
          end

          success = _write_faces(path, @face_infos, @edge_infos, unit_converter) && File.exist?(path)

          return { :errors => [ [ 'tab.cutlist.error.failed_export_to_3d_file', { :file_format => @file_format, :error => e.message } ] ] } unless success
          return { :export_path => path }
        rescue => e
          puts e.inspect
          puts e.backtrace
          return { :errors => [ [ 'tab.cutlist.error.failed_export_to_3d_file', { :file_format => @file_format, :error => e.message } ] ] }
        end
      end

      { :cancelled => true }
    end

    # -----

    private

    def _write_faces(path, face_infos, edge_infos, unit_converter)

      # Open output file
      file = File.new(path , 'w')

      case @file_format
      when FILE_FORMAT_DXF

        _dxf_write(file, 0, 'SECTION')
        _dxf_write(file, 2, 'ENTITIES')

        face_infos.each do |face_info|

          face = face_info.face
          transformation = face_info.transformation

          face.loops.each do |loop|

            _dxf_write(file, 0, 'POLYLINE')
            _dxf_write(file, 8, 0)
            _dxf_write(file, 66, 1)
            _dxf_write(file, 70, 1) # 1 = This is a closed polyline (or a polygon mesh closed in the M direction)
            _dxf_write(file, 10, 0.0)
            _dxf_write(file, 20, 0.0)
            _dxf_write(file, 30, 0.0)

            loop.vertices.each do |vertex|
              point = vertex.position.transform(transformation)
              _dxf_write(file, 0, 'VERTEX')
              _dxf_write(file, 8, 0)
              _dxf_write(file, 10, _convert(point.x, unit_converter))
              _dxf_write(file, 20, _convert(point.y, unit_converter))
              _dxf_write(file, 30, 0.0)
              _dxf_write(file, 70, 32) # 32 = 3D polyline vertex
            end

            _dxf_write(file, 0, 'SEQEND')

          end

        end

        edge_infos.each do |edge_info|

          edge = edge_info.edge
          transformation = edge_info.transformation

          point1 = edge.start.position.transform(transformation)
          point2 = edge.end.position.transform(transformation)

          x1 = _convert(point1.x, unit_converter)
          y1 = _convert(point1.y, unit_converter)
          x2 = _convert(point2.x, unit_converter)
          y2 = _convert(point2.y, unit_converter)

          _dxf_write_line(file, x1, y1, x2, y2, 'guide')

        end

        _dxf_write(file, 0, 'ENDSEC')
        _dxf_write(file, 0, 'EOF')

      when FILE_FORMAT_SVG

        bounds = Geom::BoundingBox.new
        bounds.add(@anchor_origin)
        face_infos.each do |face_info|
          bounds.add(_compute_children_faces_triangles([ face_info.face ], face_info.transformation))
        end
        edge_infos.each do |edge_info|
          bounds.add(edge_info.edge.start.position.transform(edge_info.transformation))
          bounds.add(edge_info.edge.end.position.transform(edge_info.transformation))
        end

        # Tweak unit converter to restrict to SVG compatible units (in, mm, cm)
        case @unit
        when DimensionUtils::INCHES
          unit_sign = 'in'
        when DimensionUtils::CENTIMETER
          unit_sign = 'cm'
        else
          unit_converter = 1.0.to_mm
          unit_sign = 'mm'
        end

        x = _convert(bounds.min.x, unit_converter)
        y = _convert(bounds.min.y, unit_converter)
        width = _convert(bounds.width, unit_converter)
        height = _convert(bounds.height, unit_converter)

        y_offset = height + y

        puts y_offset

        _svg_write_start(file, 0, 0, width, height, unit_sign)

        face_infos.sort_by { |face_info| face_info.data[:depth] }.each do |face_info|

          face = face_info.face
          transformation = face_info.transformation
          depth = face_info.data[:depth].to_f

          face.loops.each do |loop|
            coords = []
            loop.vertices.each do |vertex|
              point = vertex.position.transform(transformation)
              coords << "#{_convert(point.x, unit_converter)},#{y_offset - _convert(point.y, unit_converter)}"
            end
            data = "M#{coords.join('L')}Z"
            if loop.outer?
              if depth.round(6) == 0
                # Outside
                _svg_write_path(file, data, '#000000', '#000000', 'shaper:cutType': 'outside')
              else
                # Pocket
                _svg_write_path(file, data, '#7F7F7F', nil, 'shaper:cutType': 'pocket', 'shaper:cutDepth': "#{_convert(depth, unit_converter)}#{unit_sign}")
              end
            else
              # Inside
              _svg_write_path(file, data, '#FFFFFF', '#000000', 'shaper:cutType': 'inside', 'shaper:cutDepth': @max_depth)
            end
          end

        end

        unless edge_infos.empty?
          data = ''
          edge_infos.each do |edge_info|

            edge = edge_info.edge
            transformation = edge_info.transformation

            coords = []
            edge.vertices.each do |vertex|
              point = vertex.position.transform(transformation)
              coords << "#{_convert(point.x, unit_converter)},#{y_offset - _convert(point.y, unit_converter)}"
            end
            data += "M#{coords.join('L')}"

          end
          _svg_write_path(file, data, nil,'#2272F6', 'stroke-width': 0.1, 'shaper:cutType': 'guide')
        end

        if @anchor_origin != ORIGIN

          x1 = _convert(@anchor_origin.x, unit_converter)
          y1 = y_offset - _convert(@anchor_origin.y, unit_converter)
          x2 = _convert(@anchor_origin.x, unit_converter)
          y2 = y_offset - _convert(@anchor_origin.y + 10.mm, unit_converter)
          x3 = _convert(@anchor_origin.x + 5.mm, unit_converter)
          y3 = y_offset - _convert(@anchor_origin.y, unit_converter)

          _svg_write_polygon(file, "#{x1},#{y1} #{x2},#{y2} #{x3},#{y3}", nil, '#FF0000')

        end

        _svg_write_end(file)

      end

      # Close output file
      file.close

      true
    end

    def _convert(value, unit_converter, precision = 6)
      (value.to_f * unit_converter).round(precision)
    end

  end

end