{
  "targets": [{
    "target_name": "ndi_addon",
    "sources": ["ndi_addon.cc"],
    "include_dirs": [
      "<!@(node -p \"require('node-addon-api').include\")",
      "<(ndi_include_dir)"
    ],
    "libraries": [
      "<(ndi_lib_dir)/Processing.NDI.Lib.x64.lib"
    ],
    "defines": ["NAPI_DISABLE_CPP_EXCEPTIONS"],
    "cflags!": ["-fno-exceptions"],
    "cflags_cc!": ["-fno-exceptions"],
    "conditions": [
      ["OS == 'win'", {
        "variables": {
          "ndi_include_dir%": "C:/Program Files/NDI/NDI 5 SDK/Include",
          "ndi_lib_dir%":     "C:/Program Files/NDI/NDI 5 SDK/Lib/x64"
        },
        "msvs_settings": {
          "VCCLCompilerTool": {
            "ExceptionHandling": 1,
            "AdditionalOptions": ["/std:c++17"]
          }
        },
        "copies": [{
          "destination": "<(PRODUCT_DIR)",
          "files": [
            "<(ndi_lib_dir)/../Bin/x64/Processing.NDI.Lib.x64.dll"
          ]
        }]
      }],
      ["OS == 'mac'", {
        "variables": {
          "ndi_include_dir%": "/Library/NDI SDK for Apple/include",
          "ndi_lib_dir%":     "/Library/NDI SDK for Apple/lib/macOS"
        },
        "libraries": [
          "<(ndi_lib_dir)/libndi.dylib"
        ],
        "xcode_settings": {
          "OTHER_CFLAGS": ["-std=c++17"]
        }
      }]
    ]
  }]
}
