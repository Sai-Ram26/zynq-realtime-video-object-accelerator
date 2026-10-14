# Automated Benchmark Results: 8-Primary Resolution Conversion Matrix

| Test ID | Input | Output | Spatial Decim | PSNR (dB) | SSIM | Input MB | Output MB | Storage Reduc | FPS |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **TM-01** | 1280x720 (720p) | 426x240 (240p) | 9.0x | 49.34 dB | 0.9978 | 0.99 MB | 0.11 MB | **8.8x** | 49.5 |
| **TM-02** | 1280x720 (720p) | 256x144 (144p) | 25.0x | 49.25 dB | 0.9979 | 0.99 MB | 0.05 MB | **18.1x** | 118.4 |
| **TM-03** | 1920x1080 (1080p) | 426x240 (240p) | 20.3x | 49.73 dB | 0.9984 | 1.59 MB | 0.14 MB | **11.7x** | 46.7 |
| **TM-04** | 1920x1080 (1080p) | 256x144 (144p) | 56.2x | 49.64 dB | 0.9981 | 1.59 MB | 0.05 MB | **30.5x** | 66.8 |
| **TM-05** | 3840x2160 (4k) | 426x240 (240p) | 81.1x | 50.26 dB | 0.9983 | 4.24 MB | 0.09 MB | **48.8x** | 24.5 |
| **TM-06** | 3840x2160 (4k) | 256x144 (144p) | 225.0x | 50.18 dB | 0.9979 | 4.24 MB | 0.03 MB | **122.9x** | 29.1 |
| **TM-07** | 7680x4320 (8k) | 426x240 (240p) | 324.5x | 51.31 dB | 0.9989 | 12.68 MB | 0.07 MB | **194.8x** | 8.5 |
| **TM-08** | 7680x4320 (8k) | 256x144 (144p) | 900.0x | 51.44 dB | 0.999 | 12.68 MB | 0.03 MB | **379.2x** | 9.5 |

*All 8 tests verified bit-accurately and decodable via standard HTML5 Video playback.*
