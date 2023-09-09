module Ladb::OpenCutList

  require_relative 'controller'
  require_relative '../model/attributes/material_attributes'
  require_relative '../model/attributes/definition_attributes'
  require_relative '../observer/app_observer'
  require_relative '../observer/selection_observer'
  require_relative '../observer/materials_observer'

  class CutlistController < Controller

    def initialize()
      super('cutlist')
    end

    def setup_commands()

      # Setup opencutlist dialog actions
      Plugin.instance.register_command("cutlist_generate") do |settings|
        generate_command(settings)
      end

      Plugin.instance.register_command("cutlist_export") do |settings|
        export_command(settings)
      end

      Plugin.instance.register_command("cutlist_report_start") do |settings|
        report_start_command(settings)
      end

      Plugin.instance.register_command("cutlist_report_advance") do |settings|
        report_advance_command
      end

      Plugin.instance.register_command("cutlist_numbers_save") do |settings|
        numbers_command(settings, false)
      end

      Plugin.instance.register_command("cutlist_numbers_reset") do |settings|
        numbers_command(settings, true)
      end

      Plugin.instance.register_command("cutlist_highlight_parts") do |settings|
        highlight_parts_command(settings)
      end

      Plugin.instance.register_command("cutlist_layout_parts") do |settings|
        layout_parts_command(settings)
      end

      Plugin.instance.register_command("cutlist_layout_to_layout") do |settings|
        layout_to_layout_command(settings)
      end

      Plugin.instance.register_command("cutlist_part_get_thumbnail") do |part_data|
        part_get_thumbnail_command(part_data)
      end

      Plugin.instance.register_command("cutlist_part_update") do |settings|
        part_update_command(settings)
      end

      Plugin.instance.register_command("cutlist_part_export_to_skp") do |settings|
        part_export_to_skp_command(settings)
      end

      Plugin.instance.register_command("cutlist_part_toggle_front") do |part_data|
        part_toggle_front_command(part_data)
      end

      Plugin.instance.register_command("cutlist_group_cuttingdiagram_1d_start") do |settings|
        group_cuttingdiagram_1d_start_command(settings)
      end

      Plugin.instance.register_command("cutlist_group_cuttingdiagram_1d_advance") do |settings|
        group_cuttingdiagram_1d_advance_command
      end

      Plugin.instance.register_command("cutlist_group_cuttingdiagram_2d_start") do |settings|
        group_cuttingdiagram_2d_start_command(settings)
      end

      Plugin.instance.register_command("cutlist_group_cuttingdiagram_2d_advance") do |settings|
        group_cuttingdiagram_2d_advance_command
      end

      Plugin.instance.register_command("cutlist_reset_prices") do |settings|
        reset_prices_command
      end

    end

    def setup_event_callbacks

      Plugin.instance.add_event_callback([
                                             AppObserver::ON_NEW_MODEL,
                                             AppObserver::ON_OPEN_MODEL,
                                             AppObserver::ON_ACTIVATE_MODEL,
                                             SelectionObserver::ON_SELECTION_BULK_CHANGE,
                                             SelectionObserver::ON_SELECTION_CLEARED,
                                             MaterialsObserver::ON_MATERIAL_CHANGE,
                                             MaterialsObserver::ON_MATERIAL_REMOVE,
                                         ]) do |params|

        # Invalidate Cutlist if if exists
        @cutlist.invalidate if @cutlist

      end

    end

    private

    # -- Commands --

    def generate_command(settings)
      require_relative '../worker/cutlist/cutlist_generate_worker'

      # Invalidate Cutlist if it exists
      @cutlist.invalidate if @cutlist

      # Setup worker
      worker = CutlistGenerateWorker.new(settings)

      # Run !
      @cutlist = worker.run

      @cutlist.to_hash
    end

    def export_command(settings)
      require_relative '../worker/cutlist/cutlist_export_worker'

      # Setup worker
      worker = CutlistExportWorker.new(settings, @cutlist)

      # Run !
      worker.run
    end

    def report_start_command(settings)
      require_relative '../worker/cutlist/cutlist_report_worker'

      # Setup worker
      @report_worker = CutlistReportWorker.new(settings, @cutlist)

      # Run !
      @report_worker.run
    end

    def report_advance_command
      return { :errors => [ 'default.error' ] } unless @report_worker

      # Run !
      @report_worker.run
    end

    def numbers_command(settings, reset)
      require_relative '../worker/cutlist/cutlist_numbers_worker'

      # Setup worker
      worker = CutlistNumbersWorker.new(settings, @cutlist, reset)

      # Run !
      worker.run
    end

    def highlight_parts_command(settings)
      require_relative '../worker/cutlist/cutlist_highlight_parts_worker'

      # Setup worker
      worker = CutlistHighlightPartsWorker.new(settings, @cutlist)

      # Run !
      worker.run
    end

    def layout_parts_command(settings)
      require_relative '../worker/cutlist/cutlist_layout_parts_worker'

      # Setup worker
      worker = CutlistLayoutPartsWorker.new(settings, @cutlist)

      # Run !
      worker.run
    end

    def layout_to_layout_command(settings)
      require_relative '../worker/cutlist/cutlist_layout_to_layout_worker'

      # Setup worker
      worker = CutlistLayoutToLayoutWorker.new(settings, @cutlist)

      # Run !
      worker.run
    end

    def part_get_thumbnail_command(part_data)
      require_relative '../worker/cutlist/cutlist_get_thumbnail_worker'

      # Setup worker
      worker = CutlistGetThumbnailWorker.new(part_data, @cutlist)

      # Run !
      worker.run
    end

    def part_update_command(settings)
      require_relative '../worker/cutlist/cutlist_part_update_worker'

      # Setup worker
      worker = CutlistPartUpdateWorker.new(settings, @cutlist)

      # Run !
      worker.run
    end

    def part_export_to_skp_command(settings)
      require_relative '../worker/cutlist/cutlist_part_export_to_skp_worker'

      # Setup worker
      worker = CutlistPartExportToSkpWorker.new(settings)

      # Run !
      worker.run
    end

    def group_cuttingdiagram_1d_start_command(settings)
      require_relative '../worker/cutlist/cutlist_cuttingdiagram_1d_worker'

      # Setup worker
      @cuttingdiagram1d_worker = CutlistCuttingdiagram1dWorker.new(settings, @cutlist)

      # Run !
      cuttingdiagram1d = @cuttingdiagram1d_worker.run(true)

      cuttingdiagram1d.to_hash
    end

    def group_cuttingdiagram_1d_advance_command
      return { :errors => [ 'default.error' ] } unless @cuttingdiagram1d_worker

      # Run !
      cuttingdiagram1d = @cuttingdiagram1d_worker.run(true)

      cuttingdiagram1d.to_hash
    end

    def group_cuttingdiagram_2d_start_command(settings)
      require_relative '../worker/cutlist/cutlist_cuttingdiagram_2d_worker'

      # Setup worker
      @cuttingdiagram2d_worker = CutlistCuttingdiagram2dWorker.new(settings, @cutlist)

      # Run !
      cuttingdiagram2d = @cuttingdiagram2d_worker.run(true)

      cuttingdiagram2d.to_hash
    end

    def group_cuttingdiagram_2d_advance_command
      return { :errors => [ 'default.error' ] } unless @cuttingdiagram2d_worker

      # Run !
      cuttingdiagram2d = @cuttingdiagram2d_worker.run(true)

      cuttingdiagram2d.to_hash
    end

    def reset_prices_command
      require_relative '../worker/cutlist/cutlist_reset_prices_worker'

      # Setup worker
      worker = CutlistResetPricesWorker.new

      # Run !
      worker.run
    end

  end

end