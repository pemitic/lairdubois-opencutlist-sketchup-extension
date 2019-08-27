+function ($) {
    'use strict';

    var SETTING_KEY_LOAD_OPTION_COL_SEP = 'importer.load.option.col_sep';
    var SETTING_KEY_LOAD_OPTION_WITH_HEADERS = 'importer.load.option.with_headers';
    var SETTING_KEY_LOAD_OPTION_COLUMN_MAPPGING = 'importer.load.option.column_mapping';

    // Options defaults

    var OPTION_DEFAULT_COL_SEP = 1;     // ,
    var OPTION_DEFAULT_WITH_HEADERS = true;
    var OPTION_DEFAULT_COLUMN_MAPPGING = {};

    // Select picker options

    var SELECT_PICKER_OPTIONS = {
        size: 10,
        iconBase: 'ladb-opencutlist-icon',
        tickIcon: 'ladb-opencutlist-icon-tick',
        showTick: true,
        noneSelectedText: 'Non utilisé'
    };

    // CLASS DEFINITION
    // ======================

    var LadbTabImporter = function (element, options, opencutlist) {
        LadbAbstractTab.call(this, element, options, opencutlist);

        this.importablePartCount = 0;

        this.$header = $('.ladb-header', this.$element);
        this.$fileTabs = $('.ladb-file-tabs', this.$header);
        this.$btnOpen = $('#ladb_btn_open', this.$header);
        this.$btnImport = $('#ladb_btn_import', this.$header);

        this.$panelHelp = $('.ladb-panel-help', this.$element);
        this.$page = $('.ladb-page', this.$element);

    };
    LadbTabImporter.prototype = new LadbAbstractTab;

    LadbTabImporter.DEFAULTS = {};

    LadbTabImporter.prototype.openCSV = function () {
        var that = this;

        rubyCallCommand('importer_open', null, function (response) {

            var i;

            if (response.errors) {
                for (i = 0; i < response.errors.length; i++) {
                    that.opencutlist.notify('<i class="ladb-opencutlist-icon-warning"></i> ' + i18next.t(response.errors[i]), 'error');
                }
            }
            if (response.path) {

                var lengthUnit = response.length_unit;

                // Retrieve load option options
                that.opencutlist.pullSettings([

                        SETTING_KEY_LOAD_OPTION_COL_SEP,
                        SETTING_KEY_LOAD_OPTION_WITH_HEADERS,
                        SETTING_KEY_LOAD_OPTION_COLUMN_MAPPGING

                    ],
                    3 /* SETTINGS_RW_STRATEGY_MODEL_GLOBAL */,
                    function () {

                        var loadOptions = {
                            path: response.path,
                            filename: response.filename,
                            col_sep: that.opencutlist.getSetting(SETTING_KEY_LOAD_OPTION_COL_SEP, OPTION_DEFAULT_COL_SEP),
                            with_headers: that.opencutlist.getSetting(SETTING_KEY_LOAD_OPTION_WITH_HEADERS, OPTION_DEFAULT_WITH_HEADERS),
                            column_mapping: that.opencutlist.getSetting(SETTING_KEY_LOAD_OPTION_COLUMN_MAPPGING, OPTION_DEFAULT_COLUMN_MAPPGING)
                        };

                        var $modal = that.appendModalInside('ladb_importer_modal_load', 'tabs/importer/_modal-load.twig', $.extend(loadOptions, {
                            lengthUnit: lengthUnit
                        }));

                        // Fetch UI elements
                        var $selectColSep = $('#ladb_importer_load_select_col_sep', $modal);
                        var $inputWithHeader = $('#ladb_importer_load_input_with_headers', $modal);
                        var $btnLoad = $('#ladb_importer_load', $modal);

                        // Bind select
                        $selectColSep.val(loadOptions.col_sep);
                        $selectColSep.selectpicker(SELECT_PICKER_OPTIONS);
                        $inputWithHeader.prop('checked', loadOptions.with_headers);

                        // Bind buttons
                        $btnLoad.on('click', function () {

                            // Fetch options

                            loadOptions.col_sep = $selectColSep.val();
                            loadOptions.with_headers = $inputWithHeader.prop('checked');

                            // Store options
                            that.opencutlist.setSettings([
                                { key:SETTING_KEY_LOAD_OPTION_COL_SEP, value:loadOptions.col_sep },
                                { key:SETTING_KEY_LOAD_OPTION_WITH_HEADERS, value:loadOptions.with_headers }
                            ], 0 /* SETTINGS_RW_STRATEGY_GLOBAL */);

                            that.loadCSV(loadOptions);

                            // Hide modal
                            $modal.modal('hide');

                        });

                        // Show modal
                        $modal.modal('show');

                    });

            }

        });
    };

    LadbTabImporter.prototype.loadCSV = function (loadOptions) {
        var that = this;

        // Store options
        that.opencutlist.setSettings([
            { key:SETTING_KEY_LOAD_OPTION_COLUMN_MAPPGING, value:loadOptions.column_mapping }
        ], 0 /* SETTINGS_RW_STRATEGY_GLOBAL */);

        rubyCallCommand('importer_load', loadOptions, function (response) {

            var i;

            if (response.errors && !response.path) {
                for (i = 0; i < response.errors.length; i++) {
                    that.opencutlist.notify('<i class="ladb-opencutlist-icon-warning"></i> ' + i18next.t(response.errors[i]), 'error');
                }
            }
            if (response.path) {

                var errors = response.errors;
                var warnings = response.warnings;
                var filename = response.filename;
                var columns = response.columns;
                var parts = response.parts;
                var importablePartCount = response.importable_part_count;
                var lengthUnit = response.length_unit;

                // Keep usefull data
                that.importablePartCount = importablePartCount;

                // Update filename
                that.$fileTabs.empty();
                that.$fileTabs.append(Twig.twig({ ref: "tabs/importer/_file-tab.twig" }).render({
                    filename: filename,
                    importablePartCount: importablePartCount,
                    lengthUnit: lengthUnit
                }));

                // Hide help panel
                that.$panelHelp.hide();

                // Update page
                that.$page.empty();
                that.$page.append(Twig.twig({ ref: "tabs/importer/_list.twig" }).render({
                    errors: errors,
                    warnings: warnings,
                    filename: filename,
                    columns: columns,
                    parts: parts,
                    importablePartCount: importablePartCount
                }));

                // Setup tooltips
                that.opencutlist.setupTooltips();

                // Apply column mapping
                for (i = 0; i < columns.length; i++) {
                    var $select = $('#ladb_select_column_' + i, that.$page);
                    $select
                        .val(columns[i].mapping)
                        .on('changed.bs.select', function(e, clickedIndex, isSelected, previousValue) {
                            var column = $(e.currentTarget).data('column');
                            var mapping = $(e.currentTarget).selectpicker('val');
                            for (var k in loadOptions.column_mapping) {
                                if (loadOptions.column_mapping[k] === column) {
                                    delete loadOptions.column_mapping[k];
                                }
                            }
                            if (mapping) {
                                loadOptions.column_mapping[mapping] = column;
                            }
                            that.loadCSV(loadOptions)
                        })
                        .selectpicker(SELECT_PICKER_OPTIONS);
                }

                // Manage buttons
                that.$btnOpen.removeClass('btn-primary');
                that.$btnOpen.addClass('btn-default');
                that.$btnImport.show();
                that.$btnImport.prop( "disabled", importablePartCount === 0);

                // Stick header
                that.stickSlideHeader(that.$rootSlide);

            }

        });

    };

    LadbTabImporter.prototype.importParts = function () {
        var that = this;

        var $modal = that.appendModalInside('ladb_importer_modal_import', 'tabs/importer/_modal-import.twig', {
            importablePartCount: that.importablePartCount
        });

        // Fetch UI elements
        var $btnImport = $('#ladb_importer_import', $modal);

        // Bind buttons
        $btnImport.on('click', function () {

            rubyCallCommand('importer_import', null, function (response) {

                var i;

                if (response.errors) {
                    for (i = 0; i < response.errors.length; i++) {
                        that.opencutlist.notify('<i class="ladb-opencutlist-icon-warning"></i> ' + i18next.t(response.errors[i]), 'error');
                    }
                }
                if (response.imported_part_count) {

                    // Update filename
                    that.$fileTabs.empty();

                    // Unstick header
                    that.unstickSlideHeader(that.$rootSlide);

                    // Show help panel
                    that.$panelHelp.show();

                    // Update page
                    that.$page.empty();

                    // Manage buttons
                    that.$btnOpen.removeClass('btn-default');
                    that.$btnOpen.addClass('btn-primary');
                    that.$btnImport.hide();

                    // Success notification
                    that.opencutlist.notify(i18next.t('tab.importer.success.imported', { count: response.imported_part_count }), 'success', [
                        Noty.button(i18next.t('default.see'), 'btn btn-default', function () {
                            that.opencutlist.minimize();
                        })
                    ]);

                }

            });

            // Hide modal
            $modal.modal('hide');

        });

        // Show modal
        $modal.modal('show');

    };

    LadbTabImporter.prototype.bind = function () {
        var that = this;

        this.$btnOpen.on('click', function () {
            that.openCSV();
            this.blur();
        });
        this.$btnImport.on('click', function () {
            that.importParts();
            this.blur();
        });

    };

    LadbTabImporter.prototype.init = function (initializedCallback) {
        var that = this;

        this.bind();

        // Callback
        if (initializedCallback && typeof(initializedCallback) == 'function') {
            initializedCallback(that.$element);
        }

    };


    // PLUGIN DEFINITION
    // =======================

    function Plugin(option, params) {
        return this.each(function () {
            var $this = $(this);
            var data = $this.data('ladb.tabSettings');
            var options = $.extend({}, LadbTabImporter.DEFAULTS, $this.data(), typeof option == 'object' && option);

            if (!data) {
                if (undefined === options.opencutlist) {
                    throw 'opencutlist option is mandatory.';
                }
                $this.data('ladb.tabSettings', (data = new LadbTabImporter(this, options, options.opencutlist)));
            }
            if (typeof option == 'string') {
                data[option].apply(data, Array.isArray(params) ? params : [ params ])
            } else {
                data.init(option.initializedCallback);
            }
        })
    }

    var old = $.fn.ladbTabImporter;

    $.fn.ladbTabImporter = Plugin;
    $.fn.ladbTabImporter.Constructor = LadbTabImporter;


    // NO CONFLICT
    // =================

    $.fn.ladbTabImporter.noConflict = function () {
        $.fn.ladbTabImporter = old;
        return this;
    }

}(jQuery);