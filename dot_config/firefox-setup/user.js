// Firefox User Preferences - Consolidated Configuration
// Enable userChrome.css and userContent.css
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Graphics and Rendering
user_pref("layers.acceleration.force-enabled", true);
user_pref("gfx.webrender.all", true);
user_pref("svg.context-properties.content.enabled", true);
user_pref("layout.css.backdrop-filter.enabled", true);
user_pref("layout.css.has-selector.enabled", true);

// UI Customization
user_pref("browser.uidensity", 0); // 0=normal, 1=compact, 2=touch
user_pref("browser.tabs.inTitlebar", 1);
user_pref("browser.proton.enabled", true);

// Privacy and Performance
user_pref("browser.newtabpage.activity-stream.feeds.section.highlights", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.showSearch", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);

// Sidebar Configuration
user_pref("sidebar.revamp", true);
user_pref("sidebar.verticalTabs", false); // Using one-line layout instead

// Enable Container Tabs
user_pref("privacy.userContext.enabled", true);
user_pref("privacy.userContext.ui.enabled", true);

// Startup and New Tab Page - Clock Configuration
// Path will be updated by setup script to actual location
user_pref("browser.startup.homepage", "file:///home/.config/firefox-setup/clock.html");
user_pref("browser.startup.page", 1); // 0=blank, 1=home, 2=last visited page, 3=resume previous session

// Disable Firefox Home Content (force blank new tabs)
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtabpage.activity-stream.enabled", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.feeds.snippets", false);
user_pref("browser.newtabpage.activity-stream.section.highlights.includePocket", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.feeds.discoverystreamfeed", false);
user_pref("browser.newtabpage.activity-stream.default.sites", "");

// URL Bar Behavior
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.urlbar.suggest.history", true);
user_pref("browser.urlbar.suggest.bookmark", true);
user_pref("browser.urlbar.suggest.openpage", true);
user_pref("browser.urlbar.suggest.topsites", false);
user_pref("browser.urlbar.suggest.engines", false);
user_pref("browser.urlbar.maxRichResults", 5);

// Remove Pocket
user_pref("extensions.pocket.enabled", false);
user_pref("extensions.pocket.api", "");
user_pref("extensions.pocket.site", "");

// DevTools Theme
user_pref("devtools.theme", "dark");

// Hardware Video Acceleration
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);

// Chrome-like Scrolling Experience
user_pref("general.smoothScroll", true);
user_pref("general.smoothScroll.lines", true);
user_pref("general.smoothScroll.pages", true);
user_pref("general.smoothScroll.other", true);
user_pref("general.smoothScroll.pixels", true);

// Scroll Physics
user_pref("mousewheel.min_line_scroll_amount", 0);
user_pref("mousewheel.default.delta_multiplier_y", 120);
user_pref("apz.gtk.kinetic_scroll.enabled", true);
user_pref("apz.overscroll.enabled", false); // No bounce
user_pref("apz.fling_friction", 0.1);

// Smooth scroll physics parameters
user_pref("general.smoothScroll.msdPhysics.enabled", true);
user_pref("general.smoothScroll.msdPhysics.motionBeginSpringConstant", 1000);
user_pref("general.smoothScroll.msdPhysics.regularSpringConstant", 1000);
user_pref("general.smoothScroll.msdPhysics.slowdownMinDeltaMS", 50);
user_pref("general.smoothScroll.msdPhysics.slowdownSpringConstant", 2000);

// Tab behavior
user_pref("browser.ctrlTab.recentlyUsedOrder", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.closeWindowWithLastTab", true);
user_pref("browser.tabs.loadBookmarksInTabs", true);

// Disable Telemetry
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("browser.discovery.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.ping-centre.telemetry", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.server", "data:,");
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.coverage.opt-out", true);

// Privacy focused private mode (Ctrl+Shift+N behavior)
user_pref("browser.privatebrowsing.autostart", false);



// Profile-specific notes
// Default profile: Standard browsing with one-line UI and minimal clock startpage
// Webapp profile: Browser UI completely hidden for native app experience
