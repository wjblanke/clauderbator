# clauderbator

Turn a photo into a big halftone-dot poster that you print on a home printer, page by page, and tape together.

Works on **macOS** with nothing to install: Python 3 standard library, plus the built-in `sips` image tool (and `swift` for the plain-enlargement mode).

## Quick start

```sh
./rasterbate.sh photo.jpg 16 poster.pdf
```

This makes a poster 16 inches wide. The height comes from the photo's proportions. You get Letter-size PDF pages with 0.25" margins.

## Options

```sh
./rasterbate.sh <image> <poster width in inches> <output> [jpeg] [color] [preview] [enlarge]
```

| Option    | Effect |
|-----------|--------|
| *(none)*  | Black halftone dots on Letter pages, written to `<output>` as a PDF |
| `jpeg`    | 4×6" photo prints at 300 dpi instead. `<output>` is a folder of `rowN_colM.jpg` files. Portrait or landscape prints are picked automatically, whichever needs fewer. |
| `color`   | Full-size dots in each spot's original colour, instead of black dots sized by darkness |
| `preview` | The whole poster on one big page, for checking the look before printing (PDF only) |
| `enlarge` | No dots: the photo itself is enlarged (Lanczos + light sharpening) and tiled the same way. Combine with `jpeg` for photo prints. |

Dot spacing defaults to 0.15". Set `DOT` to change it. Bigger dots give a bolder, more abstract look:

```sh
DOT=0.25 ./rasterbate.sh photo.jpg 24 poster.pdf
```

### Examples

```sh
./rasterbate.sh mask.jpg 15.16 mask.pdf                 # black dots, Letter PDF
./rasterbate.sh mask.jpg 15.16 mask_color.pdf color     # coloured dots
./rasterbate.sh mask.jpg 15.16 mask_4x6 jpeg            # 4x6 photo prints
./rasterbate.sh mask.jpg 15.16 mask_check.pdf preview   # one-page preview
./rasterbate.sh mask.jpg 15.16 mask_big.pdf enlarge     # plain enlargement, no dots
```

## Assembling

Every page has a small grey label at the bottom, e.g. `Row 1 Col 2 (page 2 of 4)`. Neighbouring pages share a 0.5" overlap, marked with dashed grey lines. Trim one page along its dashed line, lay it over its neighbour so the dots line up, and tape. A single-page poster has no overlap.

## How it works

`rasterbate.sh` runs these steps for you. You can also run them by hand:

1. **`sips -s format png -Z 760 photo.jpg --out mid.png`** shrinks the photo to a manageable PNG.
2. **`python3 png2grid.py mid.png grid.txt COLS ROWS`** averages the image into a grid of cells, one per dot, and writes each cell's average colour. `COLS` ≈ poster width ÷ dot spacing; `ROWS` keeps the photo's proportions.
3. **`POSTER_W=… POSTER_H=… python3 rasterbate.py grid.txt out.pdf [jpeg] [color] [preview]`** stretches the contrast, sizes each dot by darkness (area ∝ darkness), and writes the tiled PDF or JPEGs. The PDF is written directly with no PDF library; the JPEGs are drawn into a pixel buffer and converted by `sips`.

`enlarge.swift` is the no-dots version. Run it as `POSTER_W=… POSTER_H=… swift enlarge.swift photo.jpg out.pdf [jpeg]`.

If `POSTER_W`/`POSTER_H` aren't set, the scripts default to 15.16 × 18.95 in, the size of the original Tutankhamun mask poster.

## Other scripts

These were used for logo prints, not rasterbating:

- **`svg2png.swift`**: `swift svg2png.swift in.svg out.png <width px>` renders an SVG to a PNG of the given width.
- **`place_logo.swift`**: `swift place_logo.swift logo.png out.jpg <logo width in> <photo W in> <photo H in>` trims a logo's empty border and centres it on a black photo at 300 dpi (e.g. `4 6 4` = a 4"-wide logo on a 6×4 print).

## Limits

- macOS only (`sips`, CoreImage).
- `png2grid.py` reads 8/16-bit greyscale, RGB, RGBA and palette PNGs, but not interlaced ones. `rasterbate.sh` always feeds it a PNG made by `sips`, which is fine.
- Page size (US Letter) and tile overlap (0.5") are constants at the top of `rasterbate.py` and `enlarge.swift`.
