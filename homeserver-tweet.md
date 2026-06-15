THIS GUY REPLACED EVERY SUBSCRIPTION FOR OVER 30 SERVICES WITH A HOMELAB HE BUILT USING CLAUDE CODE

he built his own self hosted version of basically every service you pay for online and runs it all from a 27U server rack in his house

the goal was simple:

stop renting access to your own data, stop paying monthly subscriptions for things you can run yourself, and have one private dashboard that controls everything in your digital life

he opens one homepage on his browser and from there he can:

> stream his entire movie and TV collection through plex or jellyfin
> request a new movie through overseerr and watch it appear in his library automatically once it's downloaded and tagged
> back up every photo he takes through immich (his own google photos)
> store all his files through nextcloud (his own google drive)
> manage his audiobooks, ebooks, music, RSS feeds, recipes, and bookmarks from one place
> block ads across his entire network with adguard home
> see live grafana stats for every machine running in his house at any moment

and a lot more

the homepage dashboard even shows the current weather, his calendar, system stats, download queues, library counts, and shortcuts to every service he uses

the hardware list:

> netgate 1100 router running pfsense+ for firewall, DHCP, DNS, and VLANs
> tp-link 8 port managed switch
> tp-link archer C6 access point
> raspberry pi 4 dedicated to a full screen grafana dashboard
> HP laptop with i3 11th gen and 24GB RAM running proxmox VE as the main hypervisor
> compaq laptop with a core 2 duo and 4GB RAM running proxmox backup server
> tower PC with a core 2 duo running unraid for the NAS

the proxmox VE box runs every self hosted service inside a debian VM with docker compose. backups run on a schedule with chunk based deduplication. unraid handles all the storage with mixed drive sizes and a single parity drive

every device is on a tailscale tailnet so he can hit anything from anywhere in the world without poking holes in his firewall

then he built his own private streaming empire on top of it:

> plex and jellyfin pointing at the same library
> overseerr to request movies and shows
> radarr, sonarr, lidarr, readarr managing different media types
> prowlarr indexing everything
> sabnzbd and qbittorrent handling the downloads
> bazarr pulling subtitles automatically
> tautulli for plex stats
> trailarr for trailers

then the rest of the stack:

> nextcloud replaces google drive
> immich replaces google photos
> paperless-ngx for OCR document management
> adguard home blocks ads across the entire network
> miniflux for RSS, karakeep for bookmarks
> mealie for recipes, navidrome for music, audiobookshelf for audiobooks
> calibre for ebooks, code server for VS code in the browser
> stirling PDF, IT tools, microbin, searxng, pairdrop

every service surfaces through homepage, a self hosted dashboard he built tooling around to auto generate the YAML config (made with claude code)

this guy is paying $0 a month for what most people pay $200+ in subscriptions for and had an initial setup cost of ~1000 to 1500 USD

the homelab community is quietly the most overpowered and cracked group of builders on the internet
