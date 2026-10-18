/// The profiles file example from docs/12-data-formats.md, as written by hand and as the store writes it.
enum ProfilesFileFixture {
    static let handWritten = """
        {
          "schemaVersion": 1,
          "profiles": [
            {
              "id": "6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21",
              "name": "Screen share",
              "autoExitSeconds": 1800,
              "steps": [
                { "type": "hideDesktopIcons" },
                { "type": "hideDock" },
                { "type": "hideMenuBar" },
                { "type": "hideApps", "exclusions": ["com.apple.Safari"] },
                { "type": "wallpaper",
                  "choice": { "type": "solidColor", "red": 21, "green": 21, "blue": 21 },
                  "displays": { "type": "allDisplays" } }
              ]
            }
          ]
        }
        """

    static let written = """
        {
          "profiles" : [
            {
              "autoExitSeconds" : 1800,
              "id" : "6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21",
              "name" : "Screen share",
              "steps" : [
                {
                  "type" : "hideDesktopIcons"
                },
                {
                  "type" : "hideDock"
                },
                {
                  "type" : "hideMenuBar"
                },
                {
                  "exclusions" : [
                    "com.apple.Safari"
                  ],
                  "type" : "hideApps"
                },
                {
                  "choice" : {
                    "blue" : 21,
                    "green" : 21,
                    "red" : 21,
                    "type" : "solidColor"
                  },
                  "displays" : {
                    "type" : "allDisplays"
                  },
                  "type" : "wallpaper"
                }
              ]
            }
          ],
          "schemaVersion" : 1
        }
        """
}
