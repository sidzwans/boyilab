module.exports = {
  // Prowlarr Indexers (Use Clean URLs without '=search')
  torznab: [
     "http://localhost:9696/2/api?apikey=YOUR_PROWLARR_API_KEY", // DigitalCore
     "http://localhost:9696/3/api?apikey=YOUR_PROWLARR_API_KEY", // DarkPeers
     "http://localhost:9696/4/api?apikey=YOUR_PROWLARR_API_KEY"  // Malayabits
  ],

  // Client Injection
  action: "inject",
  torrentClients: ["qbittorrent:http://admin:YOUR_QBIT_PASSWORD@localhost:8080"],
  
  // Paths (Matches qBittorrent & Media Stack)
  torrentDir: "/torrents", 
  outputDir: null, // Set to null to prevent v6 warnings

  // Logic
  includeSingleEpisodes: true, // Replaced "includeEpisodes" (v6 fix)
  includeNonVideos: true, 
  duplicateCategories: true,
  matchMode: "safe", 
  linkDirs: [],
  flatLinking: false,

  // Automation: Manual/Script Only (Safe Backup: 1 day)
  searchCadence: null,
  
  // Exclusions (Required: excludeOlder must be 2-5x recent)
  excludeRecentSearch: "2w",
  excludeOlder: "6w",

  // Security
  apiKey: "media_lab_secure_key_2025_forge"
};
