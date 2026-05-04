# Mars surface texture

`2304_mars.jpg` is NASA Photojournal entry [PIA02066][pia], a global cylindrical
projection of Mars assembled from a 24-image mosaic captured by the Mars Global
Surveyor on a single day in April 1999. NASA imagery is in the public domain;
the conventional credit string is reproduced below.

> Image credit: NASA / JPL / Malin Space Science Systems
> Source: <https://photojournal.jpl.nasa.gov/catalog/PIA02066>

The image is stored at its native NASA-published resolution (2304 × 1152, 2:1
equirectangular). Higher-resolution variants exist at NASA but at the camera
distances used by the in-game planet renderer this resolution already exceeds
the target framebuffer's sampling rate.

## South-pole synthesis

The PIA02066 source map covers Mars only down to ~64°S — the band between
that latitude and the south pole is solid black in NASA's release (the
imaging campaign that produced the mosaic was a single April-1999 day,
during which the south polar cap was in winter darkness). For continuity in
the in-game planet renderer the missing band has been filled with a
vertically-mirrored copy of the corresponding north hemisphere (rows
`H-1-y` ↦ `y`), with an 8-row linear cross-fade across the seam at y=977
to hide the discontinuity. The mirrored south-pole pixels are not
photographic and should not be cited as Mars surface data; they exist
solely so the rendered globe doesn't have a black skullcap.

[pia]: https://photojournal.jpl.nasa.gov/catalog/PIA02066
