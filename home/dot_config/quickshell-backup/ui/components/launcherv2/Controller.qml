pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Scorer.js" as Scorer
import "ControllerUtils.js" as Utils
import "NavigationHelpers.js" as Nav
import "ItemTransformers.js" as Transform

Item {
    id: root

    property string searchQuery: ""
    property string searchMode: "all"
    property string previousSearchMode: "all"
    property bool autoSwitchedToFiles: false
    property bool isFileSearching: false
    property var sections: []
    property var flatModel: []
    property int selectedFlatIndex: 0
    property var selectedItem: null
    property bool isSearching: false
    property string activePluginId: ""
    property var collapsedSections: ({})
    property bool keyboardNavigationActive: false
    property bool active: false
    property var _modeSectionsCache: ({})
    property bool _queryDrivenSearch: false
    property var sectionViewModes: ({})
    property int gridColumns: SettingsData.appLauncherGridColumns
    property int viewModeVersion: 0
    property string viewModeContext: "spotlight"

    signal itemExecuted
    signal searchCompleted
    signal modeChanged(string mode)
    signal viewModeChanged(string sectionId, string mode)
    signal searchQueryRequested(string query)

    // Plugin stubs (kept as properties so UI code that references them doesn't crash)
    property string pluginFilter: ""
    property string activePluginName: ""
    property var activePluginCategories: []
    property string activePluginCategory: ""
    property string appCategory: ""
    property var appCategories: []

    property string fileSearchType: "all"
    property string fileSearchExt: ""
    property string fileSearchFolder: ""
    property string fileSearchSort: "score"

    onActiveChanged: {
        if (!active) {
            sections = [];
            flatModel = [];
            selectedItem = null;
            _clearModeCache();
        }
    }

    onSearchModeChanged: {
        if (searchMode === "apps") {
            _loadAppCategories();
        } else {
            appCategory = "";
            appCategories = [];
        }
    }

    readonly property var sectionDefinitions: [
        { id: "favorites", title: I18n.tr("Pinned"), icon: "push_pin", priority: 1, defaultViewMode: "list" },
        { id: "apps", title: I18n.tr("Applications"), icon: "apps", priority: 2, defaultViewMode: "list" },
        { id: "files", title: I18n.tr("Files"), icon: "folder", priority: 4, defaultViewMode: "list" },
        { id: "fallback", title: I18n.tr("Commands"), icon: "terminal", priority: 5, defaultViewMode: "list" }
    ]

    property int _searchVersion: 0

    Timer {
        id: searchDebounce
        interval: 60
        onTriggered: root.performSearch()
    }

    Timer {
        id: fileSearchDebounce
        interval: 200
        onTriggered: root.performFileSearch()
    }

    function getSectionViewMode(sectionId) {
        if (sectionViewModes[sectionId]) return sectionViewModes[sectionId];
        var savedModes = SettingsData.spotlightSectionViewModes || {};
        if (savedModes[sectionId]) return savedModes[sectionId];
        for (var i = 0; i < sectionDefinitions.length; i++) {
            if (sectionDefinitions[i].id === sectionId)
                return sectionDefinitions[i].defaultViewMode || "list";
        }
        return "list";
    }

    function setSectionViewMode(sectionId, mode) {
        sectionViewModes = Object.assign({}, sectionViewModes, { [sectionId]: mode });
        viewModeVersion++;
        var savedModes = Object.assign({}, SettingsData.spotlightSectionViewModes || {}, { [sectionId]: mode });
        SettingsData.spotlightSectionViewModes = savedModes;
        viewModeChanged(sectionId, mode);
    }

    function canChangeSectionViewMode(sectionId) { return true; }
    function canCollapseSection(sectionId) { return searchMode === "all"; }

    function getGridColumns(sectionId) { return gridColumns; }
    function getCurrentSectionViewMode() {
        if (!selectedItem) return "list";
        var entry = flatModel[selectedFlatIndex];
        if (!entry) return "list";
        return getSectionViewMode(entry.sectionId);
    }

    function setSearchQuery(query) {
        _searchVersion++;
        _queryDrivenSearch = true;
        searchQuery = query;
        searchDebounce.restart();
        if (searchMode === "files" || query.startsWith("/")) {
            if (query.length > 0) fileSearchDebounce.restart();
        }
    }

    function setMode(mode, isAutoSwitch) {
        if (searchMode === mode) return;
        if (isAutoSwitch) {
            previousSearchMode = searchMode;
            autoSwitchedToFiles = true;
        } else {
            autoSwitchedToFiles = false;
        }
        searchMode = mode;
        modeChanged(mode);
        performSearch();
        if (mode === "files") fileSearchDebounce.restart();
    }

    function restorePreviousMode() {
        if (!autoSwitchedToFiles) return;
        autoSwitchedToFiles = false;
        searchMode = previousSearchMode;
        modeChanged(previousSearchMode);
        performSearch();
    }

    function clearPluginFilter() { return false; }

    function toggleSection(sectionId) {
        var c = Object.assign({}, collapsedSections);
        c[sectionId] = !c[sectionId];
        collapsedSections = c;
        // Rebuild
        for (var i = 0; i < sections.length; i++) {
            if (sections[i].id === sectionId) {
                sections[i].collapsed = c[sectionId];
            }
        }
        flatModel = Scorer.flattenSections(sections);
        sections = sections.slice(); // trigger change
        selectedFlatIndex = getFirstItemIndex();
        updateSelectedItem();
    }

    function _clearModeCache() { _modeSectionsCache = {}; }
    function _getCachedModeData(mode) { return _modeSectionsCache[mode] || null; }
    function _setCachedModeData(mode, sections, flatModel) {
        _modeSectionsCache[mode] = { sections: sections, flatModel: flatModel };
    }

    function getFirstItemIndex() { return Nav.getFirstItemIndex(flatModel); }

    function updateSelectedItem() {
        if (selectedFlatIndex >= 0 && selectedFlatIndex < flatModel.length && !flatModel[selectedFlatIndex].isHeader) {
            selectedItem = flatModel[selectedFlatIndex].item;
        } else {
            selectedItem = null;
        }
    }

    function selectNext() {
        keyboardNavigationActive = true;
        selectedFlatIndex = Nav.calculateNextIndex(flatModel, selectedFlatIndex, null, null, gridColumns, getSectionViewMode);
        updateSelectedItem();
    }

    function selectPrevious() {
        keyboardNavigationActive = true;
        selectedFlatIndex = Nav.calculatePrevIndex(flatModel, selectedFlatIndex, null, null, gridColumns, getSectionViewMode);
        updateSelectedItem();
    }

    function selectRight() {
        keyboardNavigationActive = true;
        selectedFlatIndex = Nav.calculateRightIndex(flatModel, selectedFlatIndex, getSectionViewMode);
        updateSelectedItem();
    }

    function selectLeft() {
        keyboardNavigationActive = true;
        selectedFlatIndex = Nav.calculateLeftIndex(flatModel, selectedFlatIndex, getSectionViewMode);
        updateSelectedItem();
    }

    function selectNextSection() {
        keyboardNavigationActive = true;
        selectedFlatIndex = Nav.calculateNextSectionIndex(flatModel, selectedFlatIndex);
        updateSelectedItem();
    }

    function selectPreviousSection() {
        keyboardNavigationActive = true;
        selectedFlatIndex = Nav.calculatePrevSectionIndex(flatModel, selectedFlatIndex);
        updateSelectedItem();
    }

    function selectPageDown(count) {
        keyboardNavigationActive = true;
        selectedFlatIndex = Nav.calculatePageDownIndex(flatModel, selectedFlatIndex, count);
        updateSelectedItem();
    }

    function selectPageUp(count) {
        keyboardNavigationActive = true;
        selectedFlatIndex = Nav.calculatePageUpIndex(flatModel, selectedFlatIndex, count);
        updateSelectedItem();
    }

    function executeSelected() {
        if (!selectedItem) return;
        executeItem(selectedItem);
    }

    function executeItem(item) {
        if (!item) return;
        switch (item.type) {
        case "app":
            if (item.data) {
                SessionService.launchDesktopEntry(item.data);
                AppUsageHistoryData.addAppUsage(item.data);
            }
            break;
        case "file":
            if (item.data?.path) {
                Quickshell.execDetached(["xdg-open", item.data.path]);
            }
            break;
        }
        itemExecuted();
    }

    function executeAction(item, action) {
        if (!item || !action) return;
        switch (action.action) {
        case "launch":
            executeItem(item);
            return;
        case "launch_dgpu":
            if (item.data) {
                SessionService.launchDesktopEntry(item.data, true);
                AppUsageHistoryData.addAppUsage(item.data);
            }
            itemExecuted();
            return;
        case "open":
            if (item.data?.path) Quickshell.execDetached(["xdg-open", item.data.path]);
            itemExecuted();
            return;
        case "open_folder":
            if (item.data?.path) {
                var dir = item.data.path.substring(0, item.data.path.lastIndexOf("/"));
                Quickshell.execDetached(["xdg-open", dir]);
            }
            itemExecuted();
            return;
        case "copy_path":
            if (item.data?.path) Quickshell.execDetached(["wl-copy", item.data.path]);
            itemExecuted();
            return;
        case "open_terminal":
            if (item.data?.path) Quickshell.execDetached(["kitty", "--working-directory", item.data.path]);
            itemExecuted();
            return;
        }
        // Desktop action
        if (action.actionData && item.data) {
            SessionService.launchDesktopAction(item.data, action.actionData);
            AppUsageHistoryData.addAppUsage(item.data);
            itemExecuted();
        }
    }

    function pasteSelected() {}

    function getFrecencyForItem(item) {
        if (!item || !item.id) return null;
        return AppUsageHistoryData.getAppUsage(item.id);
    }

    function _applyHighlights(sections, query) {
        if (!query || query.length === 0) {
            for (var s = 0; s < sections.length; s++) {
                var items = sections[s].items;
                for (var i = 0; i < items.length; i++) {
                    items[i]._hName = "";
                    items[i]._hSub = "";
                    items[i]._hRich = false;
                }
            }
            return;
        }
        var q = query.toLowerCase();
        for (var s = 0; s < sections.length; s++) {
            var items = sections[s].items;
            for (var i = 0; i < items.length; i++) {
                var item = items[i];
                var name = item.name || "";
                var nameL = name.toLowerCase();
                var idx = nameL.indexOf(q);
                if (idx >= 0) {
                    item._hName = name.substring(0, idx) + "<b>" + name.substring(idx, idx + query.length) + "</b>" + name.substring(idx + query.length);
                    item._hRich = true;
                } else {
                    item._hName = "";
                    item._hRich = false;
                }
                item._hSub = "";
            }
        }
    }

    function preserveSelectionAfterUpdate(forceFirst) {
        if (forceFirst) return function() { return getFirstItemIndex(); };
        var previousSelectedId = selectedItem?.id || "";
        return function(newFlatModel) {
            if (!previousSelectedId) return Nav.getFirstItemIndex(newFlatModel);
            for (var i = 0; i < newFlatModel.length; i++) {
                if (!newFlatModel[i].isHeader && newFlatModel[i].item?.id === previousSelectedId) return i;
            }
            return Nav.getFirstItemIndex(newFlatModel);
        };
    }

    function getOrTransformApp(app) {
        return AppSearchService.getOrTransformApp(app, transformApp);
    }

    function transformApp(app) {
        var appId = app.id || app.execString || app.exec || "";
        var override = SessionData.getAppOverride(appId);
        return Transform.transformApp(app, override, [], I18n.tr("Launch"));
    }

    function transformFileResult(file) {
        return Transform.transformFileResult(file, I18n.tr("Open"), I18n.tr("Open folder"), I18n.tr("Copy path"), I18n.tr("Open in terminal"));
    }

    function _loadAppCategories() {
        appCategories = AppSearchService.getAllCategories();
    }

    function setAppCategory(category) {
        if (appCategory === category) return;
        appCategory = category;
        _queryDrivenSearch = true;
        _clearModeCache();
        performSearch();
    }

    function setFileSearchType(type) {
        if (fileSearchType === type) return;
        fileSearchType = type;
        performFileSearch();
    }

    function setFileSearchExt(ext) {
        if (fileSearchExt === ext) return;
        fileSearchExt = ext;
        performFileSearch();
    }

    function setFileSearchSort(sort) {
        if (fileSearchSort === sort) return;
        fileSearchSort = sort;
        performFileSearch();
    }

    function setActivePluginCategory(categoryId) {}

    function performSearch() {
        var currentVersion = _searchVersion;
        isSearching = true;
        var shouldResetSelection = _queryDrivenSearch;
        _queryDrivenSearch = false;
        var restoreSelection = preserveSelectionAfterUpdate(shouldResetSelection);

        if (searchMode === "files") {
            var fileQuery = searchQuery.startsWith("/") ? searchQuery.substring(1).trim() : searchQuery.trim();
            isFileSearching = fileQuery.length >= 2 && DSearchService.dsearchAvailable;
            sections = [];
            flatModel = [];
            selectedFlatIndex = 0;
            selectedItem = null;
            isSearching = false;
            searchCompleted();
            return;
        }

        var allItems = [];

        if (searchMode === "apps") {
            var isCategoryFiltered = appCategory && appCategory !== I18n.tr("All");
            if (isCategoryFiltered) {
                var rawApps = AppSearchService.getAppsInCategory(appCategory);
                for (var i = 0; i < rawApps.length; i++) {
                    allItems.push(getOrTransformApp(rawApps[i]));
                }
            } else {
                var apps = searchApps(searchQuery);
                for (var i = 0; i < apps.length; i++) allItems.push(apps[i]);
            }
        } else {
            // "all" mode
            var apps = searchApps(searchQuery);
            for (var i = 0; i < apps.length; i++) allItems.push(apps[i]);
        }

        // Add pinned apps as favorites section
        var pinnedItems = [];
        for (var i = 0; i < allItems.length; i++) {
            if (SessionData.isPinnedApp(allItems[i].id)) {
                var pinned = Object.assign({}, allItems[i], { section: "favorites" });
                pinnedItems.push(pinned);
            }
        }
        allItems = pinnedItems.concat(allItems);

        var scoredItems = Scorer.scoreItems(allItems, searchQuery, getFrecencyForItem);
        var sortAlpha = !searchQuery && SettingsData.sortAppsAlphabetically;
        var newSections = Scorer.groupBySection(scoredItems, sectionDefinitions, sortAlpha, searchQuery ? 50 : 500);

        for (var i = 0; i < newSections.length; i++) {
            var sid = newSections[i].id;
            if (collapsedSections[sid] !== undefined) {
                newSections[i].collapsed = collapsedSections[sid];
            }
        }

        _applyHighlights(newSections, searchQuery);
        flatModel = Scorer.flattenSections(newSections);
        sections = newSections;

        selectedFlatIndex = restoreSelection(flatModel);
        updateSelectedItem();
        isSearching = false;
        searchCompleted();
    }

    function searchApps(query) {
        var apps = AppSearchService.searchApplications(query);
        var items = [];
        for (var i = 0; i < apps.length; i++) {
            items.push(getOrTransformApp(apps[i]));
        }
        return items;
    }

    function performFileSearch() {
        if (!DSearchService.dsearchAvailable) return;
        var fileQuery = "";
        if (searchQuery.startsWith("/")) {
            fileQuery = searchQuery.substring(1).trim();
        } else if (searchMode === "files") {
            fileQuery = searchQuery.trim();
        } else {
            return;
        }
        if (fileQuery.length < 2) {
            isFileSearching = false;
            return;
        }
        isFileSearching = true;
        var params = { limit: 20, fuzzy: true, sort: fileSearchSort || "score", desc: true };
        if (DSearchService.supportsTypeFilter) {
            params.type = (fileSearchType && fileSearchType !== "all") ? fileSearchType : "all";
        }
        if (fileSearchExt) params.ext = fileSearchExt;

        DSearchService.search(fileQuery, params, function(response) {
            isFileSearching = false;
            if (response.error) return;
            var fileItems = [];
            var hits = response.result?.hits || [];
            for (var i = 0; i < hits.length; i++) {
                var hit = hits[i];
                var docTypes = hit.locations?.doc_type;
                var isDir = docTypes ? !!docTypes["dir"] : false;
                fileItems.push(transformFileResult({
                    path: hit.id || "", score: hit.score || 0, is_dir: isDir
                }));
            }

            var fileSections = [];
            if (fileItems.length > 0) {
                fileSections.push({
                    id: "files", title: I18n.tr("Files"), icon: "folder",
                    priority: 4, items: fileItems,
                    collapsed: collapsedSections["files"] || false, flatStartIndex: 0
                });
            }

            var newSections;
            if (searchMode === "files") {
                newSections = fileSections;
            } else {
                var existingNonFile = sections.filter(function(s) {
                    return s.id !== "files" && s.id !== "folders";
                });
                newSections = existingNonFile.concat(fileSections);
            }
            newSections.sort(function(a, b) { return a.priority - b.priority; });
            _applyHighlights(newSections, searchQuery);
            flatModel = Scorer.flattenSections(newSections);
            sections = newSections;
            selectedFlatIndex = getFirstItemIndex();
            updateSelectedItem();
        });
    }

    function _loadDiskCache() { return null; }
    function _saveDiskCache(sections) {}
}
